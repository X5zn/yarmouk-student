import Foundation
import WebKit

/// One shared, persistent web session for SIS + e-learning (+ Microsoft login).
/// Every web view in the app uses it, so he signs in once.
@MainActor
final class WebSession {
    static let shared = WebSession()
    var dataStore: WKWebsiteDataStore { .default() }

    private let cookieFile: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cookies.json")
    }()

    func configuration() -> WKWebViewConfiguration {
        let c = WKWebViewConfiguration()
        c.websiteDataStore = dataStore
        c.allowsInlineMediaPlayback = true
        c.defaultWebpagePreferences.allowsContentJavaScript = true
        return c
    }

    /// Copy WebKit cookies into URLSession's jar (and to disk, including session cookies,
    /// so background refresh can call e-learning after the app was closed).
    func syncCookiesToURLSession() async {
        let cookies = await dataStore.httpCookieStore.allCookies()
        let relevant = cookies.filter { $0.domain.contains("yu.edu.jo") }
        for c in relevant { HTTPCookieStorage.shared.setCookie(c) }
        let saved = relevant.map(SavedCookie.init)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: cookieFile, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Restore saved cookies into both jars at launch.
    func restoreCookies() async {
        guard let data = try? Data(contentsOf: cookieFile),
              let saved = try? JSONDecoder().decode([SavedCookie].self, from: data) else { return }
        for s in saved {
            guard let c = s.cookie else { continue }
            HTTPCookieStorage.shared.setCookie(c)
            await dataStore.httpCookieStore.setCookie(c)
        }
    }

    func signOutEverything() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        try? FileManager.default.removeItem(at: cookieFile)
    }
}

struct SavedCookie: Codable {
    var name: String, value: String, domain: String, path: String
    var expires: Date?
    var secure: Bool
    init(_ c: HTTPCookie) {
        name = c.name; value = c.value; domain = c.domain; path = c.path
        expires = c.expiresDate; secure = c.isSecure
    }
    var cookie: HTTPCookie? {
        var p: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if let expires { p[.expires] = expires }
        if secure { p[.secure] = "TRUE" }
        return HTTPCookie(properties: p)
    }
}

