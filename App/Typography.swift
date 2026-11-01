import SwiftUI
import UIKit

/// IBM Plex Sans Arabic everywhere (bundled in Resources/Fonts), scaled with Dynamic Type.
enum Plex {
    static func name(_ w: Font.Weight) -> String {
        if w == .bold || w == .heavy || w == .black { return "IBMPlexSansArabic-Bold" }
        if w == .semibold { return "IBMPlexSansArabic-SemiBold" }
        if w == .medium { return "IBMPlexSansArabic-Medium" }
        return "IBMPlexSansArabic-Regular"
    }

    static func size(_ s: Font.TextStyle) -> CGFloat {
        switch s {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        default: return 17
        }
    }

    static var isAvailable: Bool { UIFont(name: "IBMPlexSansArabic-Regular", size: 12) != nil }

    static func uiFont(_ size: CGFloat, _ w: Font.Weight) -> UIFont {
        UIFont(name: name(w), size: size) ?? .systemFont(ofSize: size, weight: w == .bold ? .bold : (w == .semibold ? .semibold : .regular))
    }

    /// Navigation bars, tab bar, segmented controls and search fields in the same font.
    static func applyAppearance() {
        let nav = UINavigationBar.appearance()
        let large = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: uiFont(32, .bold))
        let inline = UIFontMetrics(forTextStyle: .headline).scaledFont(for: uiFont(17, .semibold))
        nav.largeTitleTextAttributes = [.font: large]
        nav.titleTextAttributes = [.font: inline]
        let barItem = UIBarButtonItem.appearance()
        barItem.setTitleTextAttributes([.font: uiFont(17, .regular)], for: .normal)
        let tabItem = UITabBarItem.appearance()
        tabItem.setTitleTextAttributes([.font: uiFont(10, .medium)], for: .normal)
        tabItem.setTitleTextAttributes([.font: uiFont(10, .semibold)], for: .selected)
        let seg = UISegmentedControl.appearance()
        seg.setTitleTextAttributes([.font: uiFont(13, .medium)], for: .normal)
        seg.setTitleTextAttributes([.font: uiFont(13, .semibold)], for: .selected)
        UITextField.appearance(whenContainedInInstancesOf: [UISearchBar.self]).font = uiFont(17, .regular)
    }
}

extension Font {
    /// `.plex(.body)`, `.plex(.title2, .bold)`
    static func plex(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        let w: Font.Weight = (style == .headline && weight == .regular) ? .semibold : weight
        return .custom(Plex.name(w), size: Plex.size(style), relativeTo: style)
    }

    /// Fixed design size that still follows Dynamic Type.
    static func plex(size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
        .custom(Plex.name(weight), size: size, relativeTo: style)
    }
}
