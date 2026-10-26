import SwiftUI

// Encore runs on macOS 12: these wrappers keep the current SwiftUI APIs where they exist.

extension View {
    /// `onChange` whose two-value form only exists from macOS 14.
    @ViewBuilder func onChanged<V: Equatable>(_ value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14, *) { onChange(of: value) { _, new in action(new) } }
        else { onChange(of: value, perform: action) }
    }
}

/// ContentUnavailableView arrived in macOS 14.
struct EmptyState: View {
    let title: String
    let systemImage: String
    var description: String?

    init(_ title: String, systemImage: String, description: String? = nil) {
        self.title = title; self.systemImage = systemImage; self.description = description
    }

    var body: some View {
        if #available(macOS 14, *) {
            ContentUnavailableView(title, systemImage: systemImage, description: description.map { Text($0) })
        } else {
            VStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 34)).foregroundStyle(.secondary)
                Text(title).font(.system(size: 17, weight: .semibold))
                if let description { Text(description).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension View {
    /// Lists and editors draw their own background before macOS 13.
    @ViewBuilder func hiddenScrollBackground() -> some View {
        if #available(macOS 13, *) { scrollContentBackground(.hidden) } else { self }
    }
}

/// LabeledContent arrived in macOS 13.
struct InfoRow: View {
    let label: String
    let value: String

    init(_ label: String, value: String) { self.label = label; self.value = value }

    var body: some View {
        if #available(macOS 13, *) {
            LabeledContent(label, value: value)
        } else {
            HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
        }
    }
}

/// Grouped settings form. macOS 12 has no grouped style: its form overflows and does not scroll, so it gets a scroll view of card sections.
struct SettingsForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 13, *) {
            Form { content }.formStyle(.grouped)
        } else {
            ScrollView {
                // Lazy, like the list behind the native form: only visible sections are laid out on each scroll or hover.
                LazyVStack(alignment: .leading, spacing: 20) { content }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }

    var body: some View {
        if #available(macOS 13, *) {
            Section(title) { content }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 10) { content }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
            }
        }
    }
}

/// AppKit-backed buttons are slow to measure on macOS 12, and a settings page relayouts them on every event.
/// There, small rows of buttons are drawn by SwiftUI instead.
struct LightButtons: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13, *) { content } else { content.buttonStyle(PillButtonStyle()) }
    }
}

private struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(configuration.isPressed ? 0.2 : 0.1)))
            .contentShape(Rectangle())
    }
}
