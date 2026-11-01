import Foundation
import Darwin

public enum MCPSocket {
    public static var path: String { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Encore/mcp.sock").path }
    public static let maxLineBytes = 4_000_000

    private static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw MCPFailure("Socket path is too long") }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }

    public static func connect(_ path: String = path) throws -> Int32 {
        var address = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MCPFailure("Socket unavailable") }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0, sameUser(fd) else { close(fd); throw MCPFailure("encore is not running") }
        configure(fd)
        return fd
    }

    public static func sameUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        return getpeereid(fd, &uid, &gid) == 0 && uid == getuid()
    }

    static func configure(_ fd: Int32) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    }

    public static func write(_ data: Data, to fd: Int32) throws {
        let bytes = data + Data([10])
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw MCPFailure("Socket disconnected") }
                offset += count
            }
        }
    }

    public final class Reader {
        private var pending = Data()
        private let fd: Int32
        private let limit: Int
        public init(_ fd: Int32, limit: Int = MCPSocket.maxLineBytes) { self.fd = fd; self.limit = limit }
        public func line() throws -> Data? {
            while true {
                if let end = pending.firstIndex(of: 10) {
                    guard pending.distance(from: pending.startIndex, to: end) <= limit else { throw MCPFailure("Message too large") }
                    let line = Data(pending[..<end]); pending.removeSubrange(...end)
                    return line
                }
                guard pending.count <= limit else { throw MCPFailure("Message too large") }
                var buffer = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(fd, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count >= 0 else { throw MCPFailure("Socket disconnected") }
                if count == 0 { return nil }
                pending.append(contentsOf: buffer.prefix(count))
            }
        }
    }

    public final class Listener: @unchecked Sendable {
        private let source: DispatchSourceRead
        private let path: String
        private let lock = NSLock()
        private var clients = Set<Int32>()
        private var stopped = false
        public init(path: String, handler: @escaping (Data, MCPServer, @escaping (Data?) -> Void) -> Void) throws {
            self.path = path
            var address = try MCPSocket.address(path)
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw MCPFailure("Socket unavailable") }
            // An existing live listener belongs to another instance, and must never be replaced.
            if let existing = try? MCPSocket.connect(path) { close(existing); close(fd); throw MCPFailure("MCP is already running") }
            var info = stat()
            if lstat(path, &info) == 0 {
                guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else { close(fd); throw MCPFailure("Unsafe socket path") }
                unlink(path)
            }
            let bound = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0 else { close(fd); throw MCPFailure("Cannot create MCP socket") }
            guard chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { close(fd); unlink(path); throw MCPFailure("Cannot protect MCP socket") }
            _ = fcntl(fd, F_SETFL, O_NONBLOCK)
            source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "local.kama.Encore.mcp"))
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                self.lock.lock()
                let allowed = !self.stopped && self.clients.count < 16 && MCPSocket.sameUser(client)
                if allowed { self.clients.insert(client) }
                self.lock.unlock()
                guard allowed else { close(client); return }
                MCPSocket.configure(client)
                DispatchQueue.global(qos: .utility).async {
                    defer {
                        self.lock.lock(); self.clients.remove(client); close(client); self.lock.unlock()
                    }
                    let reader = Reader(client)
                    let session = MCPServer(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
                    do {
                        while let line = try reader.line() {
                            let done = DispatchSemaphore(value: 0)
                            handler(line, session) { response in
                                DispatchQueue.global(qos: .utility).async {
                                    if let response { try? MCPSocket.write(response, to: client) }
                                    done.signal()
                                }
                            }
                            done.wait()
                        }
                    } catch {}
                }
            }
            source.setCancelHandler { close(fd); unlink(path) }
            source.resume()
        }
        public func stop() {
            lock.lock()
            guard !stopped else { lock.unlock(); return }
            stopped = true
            for fd in clients { shutdown(fd, SHUT_RDWR) }
            lock.unlock()
            source.cancel()
        }
        deinit { stop() }
    }
}
