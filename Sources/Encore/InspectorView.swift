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
                    Text(L("Aperçu & édition")).font(.system(size: 20, weight: .semibold))
                    Text(clip.sourceName).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.toggleFavorite([clip.id]) } label: { Image(systemName: current.favorite ? "star.fill" : "star").foregroundStyle(.orange) }.buttonStyle(.plain).help(L("Favori"))
            }
            VStack(spacing: 5) {
                LabeledContent(L("Première copie"), value: current.firstCopyDate.formatted(date: .numeric, time: .standard))
                LabeledContent(L("Dernière copie"), value: current.copiedAt.formatted(date: .numeric, time: .standard))
                LabeledContent(L("Expiration"), value: model.retentionDecision(for: current).expiresAt.map { $0.formatted(date: .numeric, time: .standard) } ?? L("Indéfiniment"))
                if let bytes = current.retentionByteCount { LabeledContent(current.kind == .file ? L("Taille des fichiers") : L("Contenu conservé"), value: ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) }
                if let rule = model.retentionDecision(for: current).ruleName { LabeledContent(L("Règle"), value: rule) }
            }.font(.system(size: 12)).padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            if editable {
                TextField(L("Titre facultatif"), text: $title).textFieldStyle(.roundedBorder)
                TextEditor(text: $text).font(.system(size: 13, design: clip.kind == .code ? .monospaced : .default)).scrollContentBackground(.hidden).padding(10).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: text) { _, _ in edited = true; onDirtyChange?(true) }
                    .onChange(of: title) { _, _ in edited = true; onDirtyChange?(true) }
                HStack {
                    Text(L("\(text.count) caractères")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Menu(L("Transformer")) {
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
                    Button(L("Créer un extrait texte")) { model.addText(current.recognizedText); finish() }
                } else { Button(L("Reconnaître le texte de l’image")) { model.recognize(clip.id) } }
            } else if clip.kind == .file {
                FilePreview(previews: model.filePreviews, clip: clip, urls: model.fileURLs(for: clip), fitContent: true).frame(maxWidth: .infinity, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 10))
                Text(clip.fileNames.joined(separator: ", ")).font(.system(size: 13)).lineLimit(2)
                Text(L("Les fichiers restent à leur emplacement d’origine.")).font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(clip.fileNames, id: \.self) { name in Label(name, systemImage: "doc") }
                    Text(L("Les fichiers restent à leur emplacement d’origine.")).font(.system(size: 11)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(12)
            }
            HStack {
                if editable && edited { Text(L("Enregistrer remplace les formats de cet élément par du texte.")).font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: 285, alignment: .leading) }
                Spacer()
                Button(L("Fermer")) { finish() }.keyboardShortcut(.cancelAction)
                if editable {
                    Button(L("Enregistrer")) {
                        let saved = model.library.clips.contains(where: { $0.id == clip.id }) ? model.updateText(clip.id, text: text, title: title) : model.addText(text, title: title)
                        if saved { onDirtyChange?(false); finish() }
                    }.buttonStyle(.borderedProminent).disabled(!edited || text.isEmpty).keyboardShortcut("s", modifiers: .command)
                }
            }
        }.padding(25).frame(minWidth: 560, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity).font(.system(size: 13)).tint(Palette.accent)
    }
    private func finish() { if let onClose { onClose() } else { dismiss() } }
}
