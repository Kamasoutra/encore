import Foundation
import ImageIO

/// What a Mac agrees to share with its paired Macs: its browsable history, its favorites and snippets for syncing, or both.
public struct ShareAccess: Sendable {
    public var history: Bool
    public var synced: Set<PinnedCategory>
    public init(history: Bool, synced: Set<PinnedCategory>) { self.history = history; self.synced = synced }
}

public struct LibraryShare: PeerContentProvider {
    public typealias Snapshot = @Sendable () async -> (library: Library, excluded: Set<String>)
    public typealias Access = @Sendable () async -> ShareAccess
    public let storage: Storage
    public let access: Access
    public let snapshot: Snapshot
    public init(storage: Storage, access: @escaping Access = { ShareAccess(history: true, synced: Set(PinnedCategory.allCases)) }, snapshot: @escaping Snapshot) {
        self.storage = storage; self.access = access; self.snapshot = snapshot
    }

    public func list(_ request: ListRequest) async -> [RemoteClip] {
        guard await access().history else { return [] }
        let (library, excluded) = await snapshot()
        let query = ClipQuery(query: request.query ?? "")
        let limit = max(1, min(PeerProtocol.maxListLimit, request.limit))
        var result: [RemoteClip] = []
        for clip in library.clips.sorted(by: { $0.copiedAt > $1.copiedAt }) where result.count < limit {
            guard Self.shareable(clip, excluded: excluded), request.before.map({ clip.copiedAt < $0 }) ?? true, query.matches(clip) else { continue }
            var thumbnail: Data?
            if clip.kind != .image || clip.byteCount <= 8 * 1_048_576 {
                guard let payload = storage.payload(clip.id), !Self.concealed(payload) else { continue }
                if clip.kind == .image { thumbnail = Self.thumbnail(payload) }
            }
            result.append(RemoteClip(clip, thumbnail: thumbnail))
        }
        return result
    }

    public func pinned() async -> PinnedState? {
        let categories = await access().synced
        guard !categories.isEmpty else { return nil }
        let (library, excluded) = await snapshot()
        var state = library.pinnedState(categories: categories, excluded: excluded)
        // Concealed content is never synced, like it is never listed.
        state.items.removeAll { item in item.kind != .image && storage.payload(item.id).map(Self.concealed) ?? true }
        return state
    }

    public func payload(_ id: UUID) async -> ClipPayload? {
        let (library, excluded) = await snapshot()
        let access = await access()
        guard let clip = library.clips.first(where: { $0.id == id }), access.history || access.synced.contains(where: clip.pinned(in:)), Self.shareable(clip, excluded: excluded),
              let payload = storage.payload(id), !Self.concealed(payload), payload.byteCount <= PasteboardCapture.maxBytes else { return nil }
        return payload
    }

    /// Detected secrets never leave this Mac.
    public static func shareable(_ clip: Clip, excluded: Set<String>) -> Bool { clip.kind != .file && clip.secret == nil && !excluded.contains(clip.sourceBundle) }

    public static func concealed(_ payload: ClipPayload) -> Bool {
        payload.items.contains { item in PasteboardCapture.ignoredTypes.contains { item.representations[$0] != nil } }
    }

    public static func thumbnail(_ payload: ClipPayload) -> Data? {
        let types = ["public.png", "public.tiff", "public.jpeg", "public.heic"]
        guard let data = payload.items.lazy.compactMap({ item in types.lazy.compactMap { item.representations[$0] }.first }).first,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: PeerProtocol.thumbnailPixels] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
