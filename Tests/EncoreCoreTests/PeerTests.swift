import XCTest
import Network
import CryptoKit
import ImageIO
@testable import EncoreCore

final class PeerFramingTests: XCTestCase {
    func testFramesSurvivePartialAndCoalescedDelivery() throws {
        let first = try PeerEnvelope(.list(.init(query: "café", limit: 20, before: Date(timeIntervalSince1970: 1_700_000_000)))).encoded()
        let second = try PeerEnvelope(.payload(id: UUID())).encoded()
        let stream = try PeerFrame.encode(first) + PeerFrame.encode(second)
        var decoder = FrameDecoder()
        var frames: [Data] = []
        for byte in stream {
            decoder.append(Data([byte]))
            while let frame = try decoder.next() { frames.append(frame) }
        }
        XCTAssertEqual(frames, [first, second])
        XCTAssertEqual(try PeerEnvelope.decode(frames[0]), .list(.init(query: "café", limit: 20, before: Date(timeIntervalSince1970: 1_700_000_000))))
        var coalesced = FrameDecoder()
        coalesced.append(stream + stream.prefix(3))
        XCTAssertEqual(try coalesced.next(), first)
        XCTAssertEqual(try coalesced.next(), second)
        XCTAssertNil(try coalesced.next())
    }

    func testOversizedFramesAreRejectedBeforeBuffering() {
        XCTAssertThrowsError(try PeerFrame.encode(Data(count: 33), maxLength: 32)) { XCTAssertEqual($0 as? PeerFailure, .tooLarge) }
        var decoder = FrameDecoder(maxLength: 1024)
        decoder.append(Data([0, 0, 4, 1]))
        XCTAssertThrowsError(try decoder.next()) { XCTAssertEqual($0 as? PeerFailure, .tooLarge) }
        var hostile = FrameDecoder()
        hostile.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertThrowsError(try hostile.next())
    }

    func testCorruptedOrUnsupportedMessagesAreRejected() throws {
        XCTAssertThrowsError(try PeerEnvelope.decode(Data("{not json".utf8))) { XCTAssertEqual($0 as? PeerFailure, .malformed) }
        XCTAssertThrowsError(try PeerEnvelope.decode(Data(#"{"v":1,"message":{"bogus":{}}}"#.utf8))) { XCTAssertEqual($0 as? PeerFailure, .malformed) }
        XCTAssertThrowsError(try PeerEnvelope.decode(PeerEnvelope(.pairConfirm, version: 99).encoded())) { XCTAssertEqual($0 as? PeerFailure, .unsupportedVersion) }
        let key = SymmetricKey(size: .bits256)
        var sender = SessionCipher(key: key)
        var receiver = SessionCipher(key: key)
        let sealed = try sender.seal(Data("hello".utf8))
        var tampered = sealed
        tampered[tampered.startIndex] ^= 1
        XCTAssertThrowsError(try receiver.open(tampered)) { XCTAssertEqual($0 as? PeerFailure, .authenticationFailed) }
        XCTAssertEqual(try receiver.open(sealed), Data("hello".utf8))
        XCTAssertThrowsError(try receiver.open(sealed), "replayed frames must fail")
    }
}

final class PairingCryptoTests: XCTestCase {
    func testCodeIsDeterministicSymmetricAndSecretMatches() throws {
        let a = PeerDevice(id: "A-\(UUID())", name: "Mac A"), b = PeerDevice(id: "B-\(UUID())", name: "Mac B")
        let keyA = P256.KeyAgreement.PrivateKey(), keyB = P256.KeyAgreement.PrivateKey()
        let publicA = keyA.publicKey.x963Representation, publicB = keyB.publicKey.x963Representation
        let seenByA = PairingCrypto.transcript((a, publicA), (b, publicB))
        let seenByB = PairingCrypto.transcript((b, publicB), (a, publicA))
        XCTAssertEqual(seenByA, seenByB)
        let code = PairingCrypto.code(transcript: seenByA)
        XCTAssertEqual(code, PairingCrypto.code(transcript: seenByB))
        XCTAssertEqual(code.count, 6)
        XCTAssertTrue(code.allSatisfy(\.isNumber))
        let other = PairingCrypto.transcript((a, P256.KeyAgreement.PrivateKey().publicKey.x963Representation), (b, publicB))
        XCTAssertNotEqual(other, seenByA)
        let secretA = try PairingCrypto.secret(privateKey: keyA, remoteKey: publicB, transcript: seenByA)
        let secretB = try PairingCrypto.secret(privateKey: keyB, remoteKey: publicA, transcript: seenByB)
        XCTAssertEqual(secretA, secretB)
        XCTAssertEqual(secretA.count, 32)
        XCTAssertEqual(PairingCrypto.commitment(publicA), PairingCrypto.commitment(publicA))
        XCTAssertNotEqual(PairingCrypto.commitment(publicA), PairingCrypto.commitment(publicB))
    }

    func testSessionKeysAgreeAndAuthenticateEachRole() {
        let secret = Data(repeating: 7, count: 32), shared = Data(repeating: 9, count: 32)
        let client = PeerHello(device: .init(id: "c", name: "C"), nonce: Data(repeating: 1, count: 32), key: Data(repeating: 2, count: 32), mac: nil)
        let server = PeerHello(device: .init(id: "s", name: "S"), nonce: Data(repeating: 3, count: 32), key: Data(repeating: 4, count: 32), mac: nil)
        let one = SessionKeys(secret: secret, shared: shared, client: client, server: server)
        let two = SessionKeys(secret: secret, shared: shared, client: client, server: server)
        XCTAssertTrue(two.verify(one.mac("server"), role: "server"))
        XCTAssertFalse(two.verify(one.mac("server"), role: "client"))
        XCTAssertFalse(SessionKeys(secret: Data(repeating: 8, count: 32), shared: shared, client: client, server: server).verify(one.mac("client"), role: "client"))
    }
}

final class PeerLoopbackTests: XCTestCase {
    private var cleanup: [() -> Void] = []
    override func tearDown() {
        for action in cleanup.reversed() { action() }
        cleanup = []
        super.tearDown()
    }

    private func makeStore(_ label: String) -> PeerSecretStore {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("encore-peers-\(label)-\(UUID().uuidString)")
        cleanup.append { try? FileManager.default.removeItem(at: folder) }
        return FilePeerSecretStore(url: folder.appendingPathComponent("Peers.json"))
    }

    private func makeService(_ name: String, store: PeerSecretStore, library: Library = Library(), excluded: Set<String> = []) throws -> (PeerService, Storage) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Encore-Peer-\(name)-\(UUID())")
        cleanup.append { try? FileManager.default.removeItem(at: root) }
        let storage = try Storage(root: root)
        let provider = LibraryShare(storage: storage) { (library, excluded) }
        let service = try PeerService(identity: .init(id: UUID().uuidString, name: name), store: store, provider: provider, advertise: false, loopbackOnly: true)
        cleanup.append { service.stop() }
        return (service, storage)
    }

    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 0.6, green: 0.4, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }

    func testPairedMacsListAndFetchWhileStrangersAndRevokedPeersAreRefused() async throws {
        let text = ClipPayload.text("Bonjour depuis l’autre Mac " + String(repeating: "x", count: 500))
        let image = ClipPayload(items: [.init(["public.png": try pngData(width: 640, height: 400)])])
        let secret = ClipPayload(items: [.init(["public.utf8-plain-text": Data("hunter2".utf8), "org.nspasteboard.ConcealedType": Data()])])
        let now = Date()
        let textClip = Clip(fingerprint: text.fingerprint, kind: .text, text: String(decoding: text.items[0].representations["public.utf8-plain-text"]!, as: UTF8.self), sourceName: "Notes", sourceBundle: "com.apple.Notes", copiedAt: now.addingTimeInterval(-10), byteCount: text.byteCount)
        let imageClip = Clip(fingerprint: image.fingerprint, kind: .image, text: "", sourceName: "Aperçu", sourceBundle: "com.apple.Preview", copiedAt: now, byteCount: image.byteCount)
        let hiddenClip = Clip(fingerprint: secret.fingerprint, kind: .text, text: "hunter2", sourceName: "Safari", sourceBundle: "com.apple.Safari", copiedAt: now.addingTimeInterval(-5), byteCount: secret.byteCount)
        let excludedPayload = ClipPayload.text("vault")
        let excludedClip = Clip(fingerprint: excludedPayload.fingerprint, kind: .text, text: "vault", sourceName: "Vault", sourceBundle: "com.example.vault", copiedAt: now.addingTimeInterval(-1), byteCount: excludedPayload.byteCount)
        var library = Library()
        library.clips = [imageClip, excludedClip, hiddenClip, textClip]

        let sharerStore = makeStore("sharer"), readerStore = makeStore("reader")
        let (sharer, storage) = try makeService("Mac Studio", store: sharerStore, library: library, excluded: ["com.example.vault"])
        storage.save(library, payloads: [(textClip.id, text), (imageClip.id, image), (hiddenClip.id, secret), (excludedClip.id, excludedPayload)])
        storage.flush()
        let (reader, _) = try makeService("MacBook", store: readerStore)
        let port = try await sharer.startSharing()
        let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: try XCTUnwrap(NWEndpoint.Port(rawValue: port)))

        let incoming = Box<PairingSession>()
        sharer.onIncomingPairing = { session in incoming.value = session; session.confirm() }
        let outgoing = reader.pair(with: endpoint)
        outgoing.confirm()
        let outcome = await outgoing.finished()
        XCTAssertEqual(outcome, .paired)
        let responder = try XCTUnwrap(incoming.value)
        let responderOutcome = await responder.finished()
        XCTAssertEqual(responderOutcome, .paired)
        XCTAssertEqual(outgoing.code, responder.code)
        XCTAssertEqual(outgoing.remote?.id, sharer.identity.id)
        XCTAssertEqual(reader.paired.map(\.id), [sharer.identity.id])
        XCTAssertEqual(sharer.paired.map(\.id), [reader.identity.id])
        let storedBySharer = try XCTUnwrap(try sharerStore.load().first), storedByReader = try XCTUnwrap(try readerStore.load().first)
        XCTAssertEqual(storedBySharer.key, storedByReader.key)
        XCTAssertEqual(storedBySharer.key.count, 32)
        XCTAssertEqual(storedByReader.device, sharer.identity)

        reader.register(sharer.identity, endpoint: endpoint)
        let clips = try await reader.list(sharer.identity.id)
        XCTAssertEqual(clips.map(\.id), [imageClip.id, textClip.id])
        XCTAssertEqual(clips[1].preview.count, PeerProtocol.previewLength)
        XCTAssertEqual(clips[1].sourceBundle, "com.apple.Notes")
        let thumbnail = try XCTUnwrap(clips[0].thumbnail)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelWidth] as? Int ?? .max, PeerProtocol.thumbnailPixels)
        let filtered = try await reader.list(sharer.identity.id, request: .init(query: "bonjour", limit: 5))
        XCTAssertEqual(filtered.map(\.id), [textClip.id])
        let older = try await reader.list(sharer.identity.id, request: .init(limit: 5, before: now.addingTimeInterval(-1)))
        XCTAssertEqual(older.map(\.id), [textClip.id])

        let fetchedText = try await reader.payload(sharer.identity.id, id: textClip.id)
        XCTAssertEqual(fetchedText, text)
        let fetchedImage = try await reader.payload(sharer.identity.id, id: imageClip.id)
        XCTAssertEqual(fetchedImage, image)
        do { _ = try await reader.payload(sharer.identity.id, id: hiddenClip.id); XCTFail("concealed content must stay private") }
        catch { XCTAssertEqual(error as? PeerFailure, .notFound) }

        let (stranger, _) = try makeService("Intrus", store: MemoryPeerSecretStore())
        do { _ = try await stranger.list(sharer.identity.id); XCTFail("no secret, no request") }
        catch { XCTAssertEqual(error as? PeerFailure, .unknownPeer) }
        let forged = MemoryPeerSecretStore()
        try forged.save(PeerSecret(device: sharer.identity, key: Data(repeating: 1, count: 32)))
        let impostor = try PeerService(identity: reader.identity, store: forged, provider: LibraryShare(storage: storage) { (Library(), []) }, advertise: false, loopbackOnly: true)
        impostor.register(sharer.identity, endpoint: endpoint)
        do { _ = try await impostor.list(sharer.identity.id); XCTFail("wrong secret must fail") }
        catch { XCTAssertEqual(error as? PeerFailure, .authenticationFailed) }
        let unknown = try PeerService(identity: .init(id: UUID().uuidString, name: "Inconnu"), store: forged, provider: LibraryShare(storage: storage) { (Library(), []) }, advertise: false, loopbackOnly: true)
        unknown.register(sharer.identity, endpoint: endpoint)
        do { _ = try await unknown.list(sharer.identity.id); XCTFail("unpaired peer must be refused") }
        catch { XCTAssertEqual(error as? PeerFailure, .unknownPeer) }

        try sharer.revoke(reader.identity.id)
        XCTAssertTrue(sharer.paired.isEmpty)
        do { _ = try await reader.list(sharer.identity.id); XCTFail("revoked peer must be refused") }
        catch { XCTAssertEqual(error as? PeerFailure, .unknownPeer) }
    }

    func testCancelledPairingStoresNothingOnEitherSide() async throws {
        let (sharer, _) = try makeService("Mac mini", store: MemoryPeerSecretStore())
        let (reader, _) = try makeService("iMac", store: MemoryPeerSecretStore())
        let port = try await sharer.startSharing()
        sharer.onIncomingPairing = { session in session.cancel() }
        let outgoing = reader.pair(with: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(NWEndpoint.Port(rawValue: port))))
        outgoing.confirm()
        guard case .failed = await outgoing.finished() else { return XCTFail("pairing should fail") }
        XCTAssertTrue(reader.paired.isEmpty)
        XCTAssertTrue(sharer.paired.isEmpty)
    }

    func testSharingDisabledRefusesConnections() async throws {
        let (sharer, _) = try makeService("Off", store: MemoryPeerSecretStore())
        let (reader, _) = try makeService("Reader", store: MemoryPeerSecretStore())
        let port = try await sharer.startSharing()
        sharer.stopSharing()
        let outgoing = reader.pair(with: .hostPort(host: "127.0.0.1", port: try XCTUnwrap(NWEndpoint.Port(rawValue: port))))
        outgoing.confirm()
        guard case .failed = await outgoing.finished() else { return XCTFail("closed listener must refuse") }
    }
}

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class PeerSecretFileTests: XCTestCase {
    private var folder: URL!
    override func setUp() { super.setUp(); folder = FileManager.default.temporaryDirectory.appendingPathComponent("encore-secrets-\(UUID().uuidString)") }
    override func tearDown() { try? FileManager.default.removeItem(at: folder); super.tearDown() }

    private final class FailingStore: PeerSecretStore, @unchecked Sendable {
        func load() throws -> [PeerSecret] { throw CocoaError(.userCancelled) }
        func save(_ secret: PeerSecret) throws {}
        func remove(_ id: String) throws {}
    }

    func testSecretsPersistPrivatelyAndCanBeRemoved() throws {
        let url = folder.appendingPathComponent("Peers.json")
        let store = FilePeerSecretStore(url: url)
        let mini = PeerSecret(device: .init(id: "a", name: "Mac mini"), key: Data(repeating: 1, count: 32))
        try store.save(mini)
        try store.save(PeerSecret(device: .init(id: "b", name: "iMac"), key: Data(repeating: 2, count: 32)))
        try store.save(PeerSecret(device: .init(id: "a", name: "Mac mini"), key: Data(repeating: 3, count: 32)))
        try store.remove("b")
        XCTAssertEqual(try FilePeerSecretStore(url: url).load(), [PeerSecret(device: mini.device, key: Data(repeating: 3, count: 32))])
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testExistingPairingsMoveOverOnceFromTheKeychain() throws {
        let url = folder.appendingPathComponent("Peers.json")
        let legacy = MemoryPeerSecretStore()
        let secret = PeerSecret(device: .init(id: "a", name: "Mac Studio"), key: Data(repeating: 7, count: 32))
        try legacy.save(secret)
        XCTAssertEqual(try FilePeerSecretStore(url: url, legacy: legacy).load(), [secret])
        try legacy.remove("a")
        XCTAssertEqual(try FilePeerSecretStore(url: url, legacy: legacy).load(), [secret], "Once migrated, the file is the only source.")
    }

    func testRefusedKeychainReadIsRetriedLater() throws {
        let url = folder.appendingPathComponent("Peers.json")
        XCTAssertThrowsError(try FilePeerSecretStore(url: url, legacy: FailingStore()).load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try FilePeerSecretStore(url: url, legacy: MemoryPeerSecretStore()).load(), [])
    }
}
