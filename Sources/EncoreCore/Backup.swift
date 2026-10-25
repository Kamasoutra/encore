import Foundation

public struct Backup: Codable {
    public struct Entry: Codable {
        public var clip: Clip
        public var payload: ClipPayload
        public init(clip: Clip, payload: ClipPayload) { self.clip = clip; self.payload = payload }
    }
    public var version: Int
    public var collections: [ClipCollection]
    public var entries: [Entry]
    public init(version: Int = 1, collections: [ClipCollection], entries: [Entry]) { self.version = version; self.collections = collections; self.entries = entries }

    public func merged(into original: Library, budgetBytes: Int) throws -> (library: Library, payloads: [(UUID, ClipPayload)]) {
        guard version == 1 else { throw CocoaError(.coderReadCorrupt) }
        var seen = Set(original.clips.map(\.fingerprint))
        var extraBytes = 0
        for entry in entries {
            guard !entry.payload.items.isEmpty, entry.payload.byteCount <= PasteboardCapture.maxBytes else { throw CocoaError(.coderReadCorrupt) }
            if seen.insert(entry.payload.fingerprint).inserted { extraBytes += entry.payload.byteCount }
        }
        guard original.clips.reduce(0, { $0 + $1.byteCount }) + extraBytes <= budgetBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        var library = original
        var payloads: [(UUID, ClipPayload)] = []
        for var collection in collections where !library.collections.contains(where: { $0.id == collection.id }) {
            collection.colorIndex = max(0, min(4, collection.colorIndex))
            collection.name = String(collection.name.prefix(100))
            library.collections.append(collection)
        }
        let collectionIDs = Set(library.collections.map(\.id))
        var indices = Dictionary(library.clips.enumerated().map { ($0.element.fingerprint, $0.offset) }, uniquingKeysWith: { first, _ in first })
        var ids = Set(library.clips.map(\.id))
        for entry in entries {
            let fingerprint = entry.payload.fingerprint
            if let index = indices[fingerprint] {
                library.clips[index].firstCopiedAt = min(library.clips[index].firstCopyDate, entry.clip.firstCopyDate)
                library.clips[index].copiedAt = max(library.clips[index].copiedAt, entry.clip.copiedAt)
                library.clips[index].favorite = library.clips[index].favorite || entry.clip.favorite
                library.clips[index].collectionIDs.formUnion(entry.clip.collectionIDs.intersection(collectionIDs))
                continue
            }
            var clip = entry.clip
            if ids.contains(clip.id) { clip.id = UUID() }
            ids.insert(clip.id)
            clip.fingerprint = fingerprint
            clip.byteCount = entry.payload.byteCount
            if clip.referencedFileBytes.map({ $0 < 0 }) == true { clip.referencedFileBytes = nil }
            clip.collectionIDs.formIntersection(collectionIDs)
            indices[fingerprint] = library.clips.count
            library.clips.append(clip)
            payloads.append((clip.id, entry.payload))
        }
        library.clips.sort { $0.copiedAt > $1.copiedAt }
        return (library, payloads)
    }
}
