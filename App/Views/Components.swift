import SwiftUI

// Shared states so no screen is ever blank, raw, or a dead end.

/// Centered card for empty / error / "connect" states, always with a way forward.
struct StateCard: View {
    var symbol: String
    var tint: Color = Brand.green
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint == Brand.green ? Brand.accent : tint)
                .frame(width: 60, height: 60)
                .background(tint.opacity(0.14), in: Circle())
                .symbolEffect(.bounce, value: title)
            Text(title).font(.plex(.headline)).multilineTextAlignment(.center)
            Text(message)
                .font(.plex(.subheadline)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button { Haptics.tap(); action() } label: {
                    Text(actionTitle).font(.plex(.body, .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(tint)
                .buttonBorderShape(.capsule)
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Small inline hint row inside a card (e.g. "no assignments").
struct InlineEmpty: View {
    var symbol: String
    var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(uiColor: .tertiarySystemFill), in: Circle())
            Text(text).font(.plex(.subheadline)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Soft moving highlight for loading placeholders.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1
    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: phase * geo.size.width * 1.6)
                        .blendMode(.plusLighter)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

/// Placeholder rows shaped like the real list, while content loads.
struct SkeletonList: View {
    var rows: Int = 4
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule().frame(width: CGFloat([170, 130, 190, 120][i % 4]), height: 11)
                        Capsule().frame(width: CGFloat([90, 70, 110, 60][i % 4]), height: 9).opacity(0.7)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                if i < rows - 1 { Divider().padding(.leading, 64) }
            }
        }
        .foregroundStyle(Color(uiColor: .tertiarySystemFill))
        .shimmering()
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityLabel("عم نحمّل")
    }
}

/// "Last updated" line under a screen.
struct UpdatedFooter: View {
    var source: String
    var date: Date?
    var body: some View {
        if let date {
            Label("آخر تحديث من \(source) \(ArabicFormat.relative(date))", systemImage: "checkmark.icloud")
                .font(.plex(.caption)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
        }
    }
}

/// Coloured rounded symbol tile used in rows (Settings style).
struct SymbolTile: View {
    var symbol: String
    var tint: Color
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

/// E-learning not connected yet: explains what appears here and opens the sign-in sheet in place.
struct MoodleConnectCard: View {
    var message: String
    @State private var show = false
    var body: some View {
        StateCard(symbol: "books.vertical.fill", title: "اربط الايليرنينغ",
                  message: message, actionTitle: "سجّل دخول بإيميل الجامعة") { show = true }
            .sheet(isPresented: $show) { MoodleLoginSheet() }
    }
}

/// Large screen-level placeholder when there is nothing at all (centered in the scroll area).
struct ScreenState: View {
    var symbol: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(Brand.green.opacity(0.85))
                .padding(.bottom, 4)
            Text(title).font(.plex(.title3, .bold))
            Text(message).font(.plex(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
