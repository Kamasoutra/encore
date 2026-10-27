import SwiftUI
import EncoreCore

struct InspectorView: View {
    @ObservedObject var model: AppModel
    let clip: Clip
    var onClose: (() -> Void)?
    var onDirtyChange: ((Bool) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var name: String
    @State private var tags: String
    @State private var language: String
    @State private var edited = false
    @State private var detailsEdited = false
    @State private var editingPlain = false
    @FocusState private var nameFocused: Bool

    init(model: AppModel, clip: Clip, onClose: (() -> Void)? = nil, onDirtyChange: ((Bool) -> Void)? = nil) {
        self.model = model; self.clip = clip
        self.onClose = onClose; self.onDirtyChange = onDirtyChange
        _text = State(initialValue: clip.text)
        _name = State(initialValue: clip.name)
        _tags = State(initialValue: clip.tags.joined(separator: ", "))
        _language = State(initialValue: clip.language ?? "")
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
                InfoRow(L("First copied"), value: Localization.date(current.firstCopyDate))
                InfoRow(L("Last copied"), value: Localization.date(current.copiedAt))
                InfoRow(L("Expires"), value: model.retentionDecision(for: current).expiresAt.map { Localization.date($0) } ?? L("Forever"))
                if let bytes = current.retentionByteCount { InfoRow(current.kind == .file ? L("File size") : L("Stored content"), value: Localization.bytes(bytes)) }
                if let rule = model.retentionDecision(for: current).ruleName { InfoRow(L("Rule"), value: rule) }
            }.font(.system(size: 12)).padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            VStack(spacing: 8) {
                TextField(L("Snippet name"), text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
                HStack {
                    TextField(L("Tags, separated by commas"), text: $tags).textFieldStyle(.roundedBorder)
                    if clip.kind == .code {
                        Picker(L("Language"), selection: $language) {
                            Text(L("None")).tag("")
                            ForEach(CodeLanguage.common, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().frame(width: 150)
                    }
                }
            }
                .onChanged(name) { _ in detailsEdited = true; onDirtyChange?(true) }
                .onChanged(tags) { _ in detailsEdited = true; onDirtyChange?(true) }
                .onChanged(language) { _ in detailsEdited = true; onDirtyChange?(true) }
            if editable {
                Group {
                    // Rich text is shown as laid out until the user chooses to edit it as plain text.
                    if !editingPlain, clip.kind == .text, let rich = model.richText(for: clip) {
                        ScrollingRichText(text: rich).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12)).clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        TextEditor(text: $text).font(.system(size: 13, design: clip.kind == .code ? .monospaced : .default)).hiddenScrollBackground().padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                    .onChanged(text) { _ in edited = true; onDirtyChange?(true) }
                Text(L("In a favorite, {{name}} asks for a value when pasting. {{date}}, {{time}}, {{clipboard}} and {{cursor}} fill in by themselves.")).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack {
                    Text(L("\(text.count) characters")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if !editingPlain, clip.kind == .text, model.richText(for: clip) != nil {
                        Button(L("Edit")) { editingPlain = true }
                    }
                    Menu(L("Transform")) {
                        ForEach(TextAction.allCases) { action in
                            Button(action.title) {
                                do { text = try action.apply(text); editingPlain = true }
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
                Button(L("Save")) { if save() { onDirtyChange?(false); finish() } }
                    .buttonStyle(.borderedProminent).disabled(!(edited || detailsEdited) || editable && edited && text.isEmpty).keyboardShortcut("s", modifiers: .command)
            }
        }
        .onAppear { if model.renaming { model.renaming = false; nameFocused = true } }
        .padding(25).frame(minWidth: 560, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity).font(.system(size: 13)).tint(Palette.accent).localized()
    }
    private func finish() { if let onClose { onClose() } else { dismiss() } }

    /// Content edits replace the item's formats with plain text; name, tags and language alone leave the content untouched.
    private func save() -> Bool {
        var id = clip.id
        if editable && (edited || !model.library.clips.contains(where: { $0.id == clip.id })) {
            let exists = model.library.clips.contains { $0.id == clip.id }
            guard exists ? model.updateText(clip.id, text: text, title: current.title) : model.addText(text) else { return false }
            if !exists, let added = model.library.clips.first(where: { $0.fingerprint == ClipPayload.text(text).fingerprint }) { id = added.id }
        }
        if detailsEdited { model.updateSnippet(id, name: name, tags: Clip.tags(from: tags), language: language.isEmpty ? nil : language) }
        return true
    }
}
