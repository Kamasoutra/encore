import Foundation
import Network
import CryptoKit

public protocol PeerContentProvider: Sendable {
    func list(_ request: ListRequest) async -> [RemoteClip]
    func payload(_ id: UUID) async -> ClipPayload?
}

public final class PairingSession: @unchecked Sendable {
    public enum State: Equatable, Sendable {
        case connecting, comparing, confirmed, paired, failed(PeerFailure)
        public var isFinal: Bool { switch self { case .paired, .failed: true; default: false } }
    }
    public let incoming: Bool
    private let lock = NSLock()
    private var current = State.connecting
    private var device: PeerDevice?
    private var shortCode: String?
    private var decision: Bool?
    private var decisionWaiter: CheckedContinuation<Bool, Never>?
    private var finishWaiters: [CheckedContinuation<State, Never>] = []
    private var handler: (@Sendable (State) -> Void)?
    var closer: (@Sendable () -> Void)?

    init(incoming: Bool) { self.incoming = incoming }

    public var state: State { lock.withLock { current } }
    public var remote: PeerDevice? { lock.withLock { device } }
    public var code: String? { lock.withLock { shortCode } }
    public var onUpdate: (@Sendable (State) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    public func confirm() { decide(true) }
    public func cancel() {
        decide(false)
        closer?()
    }

    public func finished() async -> State {
        await withCheckedContinuation { continuation in
            let done: State? = lock.withLock {
                if current.isFinal { return current }
                finishWaiters.append(continuation)
                return nil
            }
            if let done { continuation.resume(returning: done) }
        }
    }

    func waitForUser() async -> Bool {
        await withCheckedContinuation { continuation in
            let value: Bool? = lock.withLock {
                if decision == nil { decisionWaiter = continuation }
                return decision
            }
            if let value { continuation.resume(returning: value) }
        }
    }

    func comparing(_ remote: PeerDevice, code: String) {
        lock.withLock { device = remote; shortCode = code }
        update(.comparing)
    }

    func update(_ state: State) {
        let (waiters, handler): ([CheckedContinuation<State, Never>], (@Sendable (State) -> Void)?) = lock.withLock {
            guard !current.isFinal else { return ([], nil) }
            current = state
            guard state.isFinal else { return ([], self.handler) }
            defer { finishWaiters = [] }
            return (finishWaiters, self.handler)
        }
        handler?(state)
        for waiter in waiters { waiter.resume(returning: state) }
    }

    func fail(_ error: Error) {
        decide(false)
        update(.failed(error as? PeerFailure ?? .unavailable))
    }

    private func decide(_ value: Bool) {
        let waiter: CheckedContinuation<Bool, Never>? = lock.withLock {
            guard decision == nil else { return nil }
            decision = value
            defer { decisionWaiter = nil }
            return decisionWaiter
        }
        waiter?.resume(returning: value)
    }
}

public final class PeerService: @unchecked Sendable {
    public let identity: PeerDevice
    private let store: PeerSecretStore
    private let provider: PeerContentProvider
    private let advertise: Bool
    private let loopbackOnly: Bool
    private let queue = DispatchQueue(label: "local.kama.Encore.peers")
    private let lock = NSLock()
    private var secrets: [String: PeerSecret]
    private var discovered: [String: (PeerDevice, NWEndpoint)] = [:]
    private var manual: [String: (PeerDevice, NWEndpoint)] = [:]
    private var listener: NWListener?
    private var listenerPort: UInt16?
    private var browser: NWBrowser?
    private var activePairing: PairingSession?
    private var changeHandler: (@Sendable () -> Void)?
    private var pairingHandler: (@Sendable (PairingSession) -> Void)?

    public init(identity: PeerDevice, store: PeerSecretStore, provider: PeerContentProvider, advertise: Bool = true, loopbackOnly: Bool = false) throws {
        self.identity = identity; self.store = store; self.provider = provider; self.advertise = advertise; self.loopbackOnly = loopbackOnly
        secrets = Dictionary(try store.load().map { ($0.device.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public var onChange: (@Sendable () -> Void)? {
        get { lock.withLock { changeHandler } }
        set { lock.withLock { changeHandler = newValue } }
    }
    public var onIncomingPairing: (@Sendable (PairingSession) -> Void)? {
        get { lock.withLock { pairingHandler } }
        set { lock.withLock { pairingHandler = newValue } }
    }
    public var paired: [PeerDevice] { lock.withLock { secrets.values.map(\.device) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    public var nearby: [PeerDevice] { lock.withLock { discovered.merging(manual) { _, new in new }.values.map(\.0) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    public var isSharing: Bool { lock.withLock { listener != nil } }
    public func isOnline(_ id: String) -> Bool { lock.withLock { discovered[id] != nil || manual[id] != nil } }

    @discardableResult public func startSharing() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        if loopbackOnly { parameters.requiredInterfaceType = .loopback }
        let created = try NWListener(using: parameters)
        let existing: UInt16?? = lock.withLock {
            if listener != nil { return .some(listenerPort) }
            listener = created
            return .none
        }
        if let existing { return existing ?? 0 }
        if advertise { created.service = NWListener.Service(name: identity.name, type: PeerProtocol.serviceType, domain: nil, txtRecord: NWTXTRecord(["id": identity.id, "name": identity.name])) }
        created.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            self.accept(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            created.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let port = created.port?.rawValue ?? 0
                    self?.lock.withLock { self?.listenerPort = port }
                    once.resume(with: .success(port))
                case .failed(let error):
                    self?.stopSharing()
                    once.resume(with: .failure(error))
                case .cancelled:
                    once.resume(with: .failure(PeerFailure.closed))
                default: break
                }
            }
            created.start(queue: queue)
        }
    }

    public func stopSharing() {
        let current: NWListener? = lock.withLock {
            defer { listener = nil; listenerPort = nil }
            return listener
        }
        current?.cancel()
    }

    public func startBrowsing() {
        let created = NWBrowser(for: .bonjourWithTXTRecord(type: PeerProtocol.serviceType, domain: nil), using: .tcp)
        guard lock.withLock({ browser == nil ? { browser = created; return true }() : false }) else { return }
        created.browseResultsChangedHandler = { [weak self] results, _ in self?.update(results) }
        created.start(queue: queue)
    }

    public func stopBrowsing() {
        let current: NWBrowser? = lock.withLock {
            defer { browser = nil; discovered = [:] }
            return browser
        }
        current?.cancel()
        notify()
    }

    public func register(_ device: PeerDevice, endpoint: NWEndpoint) {
        lock.withLock { manual[device.id] = (device, endpoint) }
        notify()
    }

    public func stop() {
        stopSharing()
        stopBrowsing()
    }

    public func revoke(_ id: String) throws {
        try store.remove(id)
        _ = lock.withLock { secrets.removeValue(forKey: id) }
        notify()
    }

    public func pair(with device: PeerDevice) -> PairingSession {
        guard let endpoint = endpoint(device.id) else {
            let session = PairingSession(incoming: false)
            session.fail(PeerFailure.unavailable)
            return session
        }
        return pair(with: endpoint)
    }

    public func pair(with endpoint: NWEndpoint) -> PairingSession {
        let session = PairingSession(incoming: false)
        let channel = PeerChannel(NWConnection(to: endpoint, using: .tcp))
        session.closer = { channel.close() }
        Task {
            do {
                try await channel.open(timeout: 15)
                let key = P256.KeyAgreement.PrivateKey()
                let publicKey = key.publicKey.x963Representation
                try await channel.send(.pairRequest(device: identity, commitment: PairingCrypto.commitment(publicKey)))
                guard case .pairKey(let remote, let remoteKey) = try await channel.expect(), remote.id != identity.id else { throw PeerFailure.malformed }
                try await channel.send(.pairReveal(key: publicKey))
                try await completePairing(session, channel: channel, key: key, remote: remote, remoteKey: remoteKey)
            } catch { session.fail(error) }
            channel.close()
        }
        return session
    }

    public func list(_ peerID: String, request: ListRequest = .init()) async throws -> [RemoteClip] {
        let channel = try await session(peerID)
        defer { channel.close() }
        try await channel.send(.list(request))
        guard case .clips(let clips) = try await channel.expect() else { throw PeerFailure.malformed }
        return clips
    }

    public func payload(_ peerID: String, id: UUID) async throws -> ClipPayload {
        let channel = try await session(peerID)
        defer { channel.close() }
        channel.deadline(120)
        try await channel.send(.payload(id: id))
        var data = Data()
        var expected = 0
        var total: Int?
        while true {
            guard case .chunk(let index, let count, let part) = try await channel.expect(), index == expected, count > 0, total == nil || total == count else { throw PeerFailure.malformed }
            total = count
            data.append(part)
            guard data.count <= PasteboardCapture.maxBytes * 2 else { throw PeerFailure.tooLarge }
            expected += 1
            if expected == count { break }
        }
        guard let payload = try? PropertyListDecoder().decode(ClipPayload.self, from: data) else { throw PeerFailure.malformed }
        guard payload.byteCount <= PasteboardCapture.maxBytes else { throw PeerFailure.tooLarge }
        return payload
    }

    private func session(_ peerID: String) async throws -> PeerChannel {
        guard let secret = secret(peerID) else { throw PeerFailure.unknownPeer }
        guard let endpoint = endpoint(peerID) else { throw PeerFailure.unavailable }
        let channel = PeerChannel(NWConnection(to: endpoint, using: .tcp))
        do {
            try await channel.open(timeout: 15)
            let ephemeral = Curve25519.KeyAgreement.PrivateKey()
            let hello = PeerHello(device: identity, nonce: Self.random(), key: ephemeral.publicKey.rawRepresentation, mac: nil)
            try await channel.send(.hello(hello))
            guard case .hello(let server) = try await channel.expect(), server.device.id == peerID,
                  let remoteKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: server.key) else { throw PeerFailure.authenticationFailed }
            let shared = try ephemeral.sharedSecretFromKeyAgreement(with: remoteKey).withUnsafeBytes { Data($0) }
            let keys = SessionKeys(secret: secret.key, shared: shared, client: hello, server: server)
            guard keys.verify(server.mac, role: "server") else { throw PeerFailure.authenticationFailed }
            try await channel.send(.finish(mac: keys.mac("client")))
            channel.secure(send: keys.clientToServer, receive: keys.serverToClient)
            channel.deadline(30)
            return channel
        } catch {
            channel.close()
            throw error
        }
    }

    private func accept(_ connection: NWConnection) {
        let channel = PeerChannel(connection)
        Task {
            do {
                try await channel.open(timeout: 15)
                switch try await channel.receive() {
                case .hello(let hello): try await serve(channel, hello: hello)
                case .pairRequest(let device, let commitment): try await respondToPairing(channel, device: device, commitment: commitment)
                default: throw PeerFailure.malformed
                }
            } catch let failure as PeerFailure where failure != .closed {
                try? await channel.send(.error(failure))
            } catch {}
            channel.close()
        }
    }

    private func serve(_ channel: PeerChannel, hello: PeerHello) async throws {
        guard let secret = secret(hello.device.id) else { throw PeerFailure.unknownPeer }
        guard let remoteKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: hello.key) else { throw PeerFailure.malformed }
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        var reply = PeerHello(device: identity, nonce: Self.random(), key: ephemeral.publicKey.rawRepresentation, mac: nil)
        let shared = try ephemeral.sharedSecretFromKeyAgreement(with: remoteKey).withUnsafeBytes { Data($0) }
        let keys = SessionKeys(secret: secret.key, shared: shared, client: hello, server: reply)
        reply.mac = keys.mac("server")
        try await channel.send(.hello(reply))
        guard case .finish(let mac) = try await channel.expect(), keys.verify(mac, role: "client") else { throw PeerFailure.authenticationFailed }
        channel.secure(send: keys.serverToClient, receive: keys.clientToServer)
        while true {
            channel.deadline(60)
            let message: PeerMessage
            do { message = try await channel.receive() } catch PeerFailure.closed { return }
            guard self.secret(hello.device.id) != nil, isSharing else { throw PeerFailure.forbidden }
            switch message {
            case .list(let request):
                try await channel.send(.clips(await provider.list(request)))
            case .payload(let id):
                guard let payload = await provider.payload(id) else { try await channel.send(.error(.notFound)); continue }
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                let data = try encoder.encode(payload)
                let count = max(1, (data.count + PeerProtocol.chunkBytes - 1) / PeerProtocol.chunkBytes)
                channel.deadline(120)
                for index in 0..<count {
                    let start = data.startIndex + index * PeerProtocol.chunkBytes
                    try await channel.send(.chunk(index: index, count: count, data: Data(data[start..<min(data.endIndex, start + PeerProtocol.chunkBytes)])))
                }
            default: throw PeerFailure.malformed
            }
        }
    }

    private func respondToPairing(_ channel: PeerChannel, device: PeerDevice, commitment: Data) async throws {
        guard let handler = onIncomingPairing, device.id != identity.id, isSharing else { throw PeerFailure.pairingRejected }
        let session = PairingSession(incoming: true)
        session.closer = { channel.close() }
        guard lock.withLock({ activePairing == nil ? { activePairing = session; return true }() : false }) else { throw PeerFailure.pairingBusy }
        defer { lock.withLock { if activePairing === session { activePairing = nil } } }
        do {
            let key = P256.KeyAgreement.PrivateKey()
            try await channel.send(.pairKey(device: identity, key: key.publicKey.x963Representation))
            guard case .pairReveal(let remoteKey) = try await channel.expect(), PairingCrypto.commitment(remoteKey) == commitment else { throw PeerFailure.authenticationFailed }
            handler(session)
            try await completePairing(session, channel: channel, key: key, remote: device, remoteKey: remoteKey)
        } catch {
            session.fail(error)
            throw error
        }
    }

    private func completePairing(_ session: PairingSession, channel: PeerChannel, key: P256.KeyAgreement.PrivateKey, remote: PeerDevice, remoteKey: Data) async throws {
        let transcript = PairingCrypto.transcript((identity, key.publicKey.x963Representation), (remote, remoteKey))
        let secret = try PairingCrypto.secret(privateKey: key, remoteKey: remoteKey, transcript: transcript)
        session.comparing(remote, code: PairingCrypto.code(transcript: transcript))
        channel.deadline(180)
        let confirmation = Task { () -> Bool in
            let confirmed = (try? await channel.expect()) == .pairConfirm
            if !confirmed { session.fail(PeerFailure.cancelled) }
            return confirmed
        }
        guard await session.waitForUser() else {
            try? await channel.send(.error(.cancelled))
            throw PeerFailure.cancelled
        }
        session.update(.confirmed)
        try await channel.send(.pairConfirm)
        guard await confirmation.value else { throw PeerFailure.pairingRejected }
        let peer = PeerSecret(device: remote, key: secret)
        try store.save(peer)
        lock.withLock { secrets[remote.id] = peer }
        session.update(.paired)
        notify()
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var found: [String: (PeerDevice, NWEndpoint)] = [:]
        for result in results {
            guard case .bonjour(let record) = result.metadata, let id = record["id"], id != identity.id else { continue }
            found[id] = (PeerDevice(id: id, name: record["name"] ?? id), result.endpoint)
        }
        lock.withLock { discovered = found }
        notify()
    }

    private func secret(_ id: String) -> PeerSecret? { lock.withLock { secrets[id] } }
    private func endpoint(_ id: String) -> NWEndpoint? { lock.withLock { manual[id]?.1 ?? discovered[id]?.1 } }
    private func notify() { onChange?() }
    private static func random() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }
}
