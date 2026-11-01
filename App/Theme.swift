import SwiftUI
import UIKit

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
}

/// Press style used on every tappable card/row: a gentle scale + a light tap.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

extension View {
    /// Apple Health style white card.
    func healthCard(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Section header like Health's "Pinned" / "Highlights".
struct SectionTitle: View {
    var title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Spacer()
            if let action, let onAction {
                Button(action) { Haptics.tap(); onAction() }
                    .font(.body)
                    .foregroundStyle(Brand.green)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

/// Health card header row: coloured symbol + title on the leading side, time/chevron trailing.
struct CardHeader: View {
    var symbol: String
    var title: String
    var tint: Color
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.subheadline.weight(.semibold))
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            if let trailing { Text(trailing).font(.footnote).foregroundStyle(.secondary) }
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(tint)
    }
}

/// Round grey quick action like Reflect's.
struct QuickAction: View {
    var symbol: String
    var title: String
    var action: () -> Void
    var body: some View {
        Button {
            Haptics.tap(); action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 54, height: 54)
                    .background(Color(uiColor: .systemGray6), in: Circle())
                Text(title).font(.caption).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PressableStyle(scale: 0.92))
    }
}

struct Pill: View {
    var text: String
    var tint: Color
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct EmptyHint: View {
    var symbol: String
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
