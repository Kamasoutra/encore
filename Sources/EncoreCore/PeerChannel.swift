import Foundation
import Network
import CryptoKit

final class PeerChannel: @unchecked Sendable {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "local.kama.Encore.peer.channel")
    private var decoder = FrameDecoder()
    private var sender: SessionCipher?
    private var receiver: SessionCipher?
    private var timer: DispatchWorkItem?

    init(_ connection: NWConnection) { self.connection = connection }

    func open(timeout: TimeInterval) async throws {
        deadline(timeout)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { [connection] state in
                let result: Result<Void, Error>
                switch state {
                case .ready: result = .success(())
                case .failed, .waiting: result = .failure(PeerFailure.unavailable)
                case .cancelled: result = .failure(PeerFailure.closed)
                default: return
                }
                if case .failure = result { connection.cancel() }
                once.resume(with: result)
            }
            connection.start(queue: queue)
        }
    }

    func deadline(_ seconds: TimeInterval) {
        queue.async { [self] in
            timer?.cancel()
            let item = DispatchWorkItem { [connection] in connection.cancel() }
            timer = item
            queue.asyncAfter(deadline: .now() + seconds, execute: item)
        }
    }

    func secure(send: SymmetricKey, receive: SymmetricKey) {
        sender = SessionCipher(key: send)
        receiver = SessionCipher(key: receive)
    }

    func send(_ message: PeerMessage) async throws {
        var body = try PeerEnvelope(message).encoded()
        if sender != nil { body = try sender!.seal(body) }
        let frame = try PeerFrame.encode(body)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if error != nil { continuation.resume(throwing: PeerFailure.closed) } else { continuation.resume() }
            })
        }
    }

    func receive() async throws -> PeerMessage {
        while true {
            if var body = try decoder.next() {
                if receiver != nil { body = try receiver!.open(body) }
                return try PeerEnvelope.decode(body)
            }
            decoder.append(try await read())
        }
    }

    func expect() async throws -> PeerMessage {
        let message = try await receive()
        if case .error(let failure) = message { throw failure }
        return message
    }

    func close() {
        queue.async { [self] in timer?.cancel(); timer = nil }
        connection.cancel()
    }

    private func read() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { data, _, complete, error in
                if let data, !data.isEmpty { continuation.resume(returning: data) }
                else if error != nil || complete { continuation.resume(throwing: PeerFailure.closed) }
                else { continuation.resume(returning: Data()) }
            }
        }
    }
}

final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }
    func resume(with result: Result<T, Error>) {
        let pending: CheckedContinuation<T, Error>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(with: result)
    }
}
