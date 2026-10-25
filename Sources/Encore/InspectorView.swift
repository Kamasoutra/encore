import SwiftUI
import EncoreCore

struct InspectorView: View {
    @ObservedObject var model: AppModel
    let clip: Clip
    var onClose: (() -> Void)?
    var onDirtyChange: ((Bool) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var title: String
    @State private var edited = false

    init(model: AppModel, clip: Clip, onClose: (() -> Void)? = nil, onDirtyChange: ((Bool) -> Void)? = nil) {
        self.model = model; self.clip = clip
        self.onClose = onClose; self.onDirtyChange = onDirtyChange
        _text = State(initialValue: clip.text)
        _title = State(initialValue: clip.title)
    }

    private var current: Clip { model.library.clips.first { $0.id == clip.id } ?? clip }
    private var editable: Bool { [.text, .link, .code, .color].contains(clip.kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: clip.kind.symbol).font(.system(size: 22)).foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Preview & edit")).font(.system(size: 20, weight: .semibold))
                    Text(clip.sourceName).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.toggleFavorite([clip.id]) } label: { Image(systemName: current.favorite ? "star.fill" : "star").foregroundStyle(.orange) }.buttonStyle(.plain).help(L("Favorite"))
            }
            VStack(spacing: 5) {
                LabeledContent(L("First copied"), value: Localization.date(current.firstCopyDate))
                LabeledContent(L("Last copied"), value: Localization.date(current.copiedAt))
                LabeledContent(L("Expires"), value: model.retentionDecision(for: current).expiresAt.map { Localization.date($0) } ?? L("Forever"))
                if let bytes = current.retentionByteCount { LabeledContent(current.kind == .file ? L("File size") : L("Stored content"), value: Localization.bytes(bytes)) }
                if let rule = model.retentionDecision(for: current).ruleName { LabeledContent(L("Rule"), value: rule) }
            }.font(.system(size: 12)).padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            if editable {
                TextField(L("Optional title"), text: $title).textFieldStyle(.roundedBorder)
                TextEditor(text: $text).font(.system(size: 13, design: clip.kind == .code ? .monospaced : .default)).scrollContentBackground(.hidden).padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: text) { _, _ in edited = true; onDirtyChange?(true) }
                    .onChange(of: title) { _, _ in edited = true; onDirtyChange?(true) }
                HStack {
                    Text(L("\(text.count) characters")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Menu(L("Transform")) {
                        ForEach(TextAction.allCases) { action in
                            Button(action.title) {
                                do { text = try action.apply(text) }
                                catch { model.notify(error.localizedDescription) }
                            }
                        }
                    }.frame(width: 170)
                }
            } else if clip.kind == .image, let image = model.image(for: clip) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 300).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
                if !current.recognizedText.isEmpty {
                    ScrollView { Text(current.recognizedText).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }.frame(height: 100).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    Button(L("Create text snippet")) { model.addText(current.recognizedText); finish() }
                } else { Button(L("Recognize image text")) { model.recognize(clip.id) } }
            } else if clip.kind == .file {
                FilePreview(previews: model.filePreviews, clip: clip, urls: model.fileURLs(for: clip), fitContent: true).frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
                Text(clip.fileNames.joined(separator: ", ")).font(.system(size: 13)).lineLimit(2)
                Text(L("Files remain at their original location.")).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(clip.fileNames, id: \.self) { name in Label(name, systemImage: "doc") }
                    Text(L("Files remain at their original location.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
            }
            HStack {
                if editable && edited { Text(L("Saving replaces this item's formats with plain text.")).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: 285, alignment: .leading) }
                Spacer()
                Button(L("Close")) { finish() }.keyboardShortcut(.cancelAction)
                if editable {
                    Button(L("Save")) {
                        let saved = model.library.clips.contains(where: { $0.id == clip.id }) ? model.updateText(clip.id, text: text, title: title) : model.addText(text, title: title)
                        if saved { onDirtyChange?(false); finish() }
                    }.buttonStyle(.borderedProminent).disabled(!edited || text.isEmpty).keyboardShortcut("s", modifiers: .command)
                }
            }
        }.padding(25).frame(minWidth: 560, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity).font(.system(size: 13)).tint(Palette.accent).localized()
    }
    private func finish() { if let onClose { onClose() } else { dismiss() } }
}
