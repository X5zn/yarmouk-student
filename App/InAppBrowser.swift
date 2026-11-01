import SwiftUI
import WebKit

/// A page from SIS / e-learning opened INSIDE the app: top bar with back, title, reload.
/// Never hands off to Safari. Shares the signed-in session.
struct InAppBrowser: View {
    let url: URL
    var title: String = ""
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = BrowserModel()

    var body: some View {
        NavigationStack {
            WebViewContainer(url: url, model: model)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) {
                    if model.progress < 1 {
                        ProgressView(value: model.progress)
                            .progressViewStyle(.linear)
                            .tint(Brand.green)
                    }
                }
                .navigationTitle(model.title.isEmpty ? title : model.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { Haptics.tap(); dismiss() } label: {
                            Label("رجوع", systemImage: "xmark")
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { Haptics.tap(); model.webView?.goBack() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!model.canGoBack)
                        Button { Haptics.tap(); model.webView?.reload() } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
        }
        .onDisappear { Task { await WebSession.shared.syncCookiesToURLSession() } }
    }
}

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    @Published var title = ""
    @Published var progress: Double = 0
    @Published var canGoBack = false
    @Published var currentURL: String = ""
    weak var webView: WKWebView?
    private var observers: [NSKeyValueObservation] = []

    func attach(_ wv: WKWebView) {
        webView = wv
        observers = [
            wv.observe(\.title) { [weak self] wv, _ in Task { @MainActor in self?.title = wv.title ?? "" } },
            wv.observe(\.estimatedProgress) { [weak self] wv, _ in Task { @MainActor in self?.progress = wv.estimatedProgress } },
            wv.observe(\.canGoBack) { [weak self] wv, _ in Task { @MainActor in self?.canGoBack = wv.canGoBack } },
            wv.observe(\.url) { [weak self] wv, _ in Task { @MainActor in self?.currentURL = wv.url?.absoluteString ?? "" } }
        ]
    }
}

struct WebViewContainer: UIViewRepresentable {
    let url: URL
    let model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: WebSession.shared.configuration())
        wv.navigationDelegate = context.coordinator
        wv.uiDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = UserAgent.mobileSafari
        model.attach(wv)
        wv.load(URLRequest(url: url))
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        // target=_blank → open in the same view instead of leaving the app.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return .allow }
            if ["http", "https", "about", "blob", "data"].contains(scheme) { return .allow }
            // Only Teams / mail / phone links leave to their own apps.
            if ["msteams", "mailto", "tel"].contains(scheme) { await UIApplication.shared.open(url) }
            return .cancel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { await WebSession.shared.syncCookiesToURLSession() }
        }
    }
}

enum UserAgent {
    static let mobileSafari = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}

/// Identifiable wrapper so any view can present a page with `.sheet(item:)`.
struct WebLink: Identifiable, Hashable {
    let url: URL
    var title: String = ""
    var id: String { url.absoluteString }
}
