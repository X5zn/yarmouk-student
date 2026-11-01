import Foundation
import WebKit
import SwiftUI

/// Signs in to SIS inside the app (his own username, password and SMS code),
/// then walks the SIS pages in the same web view and turns them into native data.
@MainActor
final class SISSync: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    enum Phase: Equatable { case login, syncing(String), done, failed(String) }

    @Published var phase: Phase = .login
    @Published var rememberPassword = true
    let webView: WKWebView
    var onFinished: (@MainActor (SISResult) -> Void)?

    private var navContinuation: CheckedContinuation<Void, Never>?
    private var started = false
    static let root = URL(string: "https://sis.yu.edu.jo/ords/")!

    override init() {
        let config = WebSession.shared.configuration()
        let ucc = WKUserContentController()
        config.userContentController = ucc
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.customUserAgent = UserAgent.mobileSafari
        webView.navigationDelegate = self
        ucc.add(WeakHandler(self), name: "sisCreds")
        ucc.addUserScript(WKUserScript(source: Self.loginHelperJS(prefill: Keychain.load()),
                                       injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    func start() {
        started = false
        phase = .login
        webView.load(URLRequest(url: Self.root))
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navContinuation?.resume(); navContinuation = nil
        guard !started, let current = webView.url else { return }
        // After username/password + SMS code, APEX lands on /home.
        if current.absoluteString.contains("/ords/r/sis/sis/home") {
            started = true
            Task { await self.runSync(homeURL: current) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navContinuation?.resume(); navContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navContinuation?.resume(); navContinuation = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: String], let u = body["u"], let p = body["p"], !u.isEmpty, !p.isEmpty else { return }
        if rememberPassword { Keychain.save(username: u, password: p) }
    }

    private func go(_ url: URL) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            navContinuation?.resume()
            navContinuation = c
            webView.load(URLRequest(url: url))
        }
        try? await Task.sleep(for: .milliseconds(1200))
    }

    private func extract() async -> [String: Any] {
        guard let raw = try? await webView.evaluateJavaScript(Self.extractJS) as? String,
              let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    // MARK: Sync

    private func runSync(homeURL: URL) async {
        let session = URLComponents(url: homeURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "session" })?.value ?? ""
        var result = SISResult()
        func page(_ slug: String) -> URL {
            URL(string: "https://sis.yu.edu.jo/ords/r/sis/sis/\(slug)?session=\(session)")!
        }

        phase = .syncing("الصفحة الرئيسية")
        let home = await extract()
        if (home["login"] as? Bool) == true { phase = .failed("انتهت الجلسة، سجّل دخول مرة ثانية"); started = false; return }
        result.pages["home"] = Self.page(from: home, key: "home", url: homeURL)
        let links = (home["links"] as? [[String: String]] ?? []).compactMap { l -> (String, URL)? in
            guard let t = l["t"], let h = l["h"], let u = URL(string: h) else { return nil }
            return (t, u)
        }

        // Known pages + discovered ones by their Arabic menu names.
        var targets: [(key: String, title: String, url: URL)] = [
            ("info", "المعلومات الأساسية", page("student-information")),
            ("records", "السجل الأكاديمي", page("academic-records")),
            ("plan", "الخطة الدراسية", page("study-plan"))
        ]
        let wanted: [(String, String, [String])] = [
            ("schedule", "الجدول الدراسي", ["الجدول", "جدول"]),
            ("marks", "العلامات", ["العلامات", "علامات"]),
            ("finance", "المالية", ["المالي", "الرسوم", "الذمم", "كشف حساب", "الدفع"])
        ]
        for (key, title, words) in wanted {
            if let hit = links.first(where: { l in words.contains { l.0.contains($0) } }) {
                targets.append((key, title, hit.1))
            }
        }

        for t in targets {
            phase = .syncing(t.title)
            await go(t.url)
            let obj = await extract()
            if (obj["login"] as? Bool) == true { break }
            result.pages[t.key] = Self.page(from: obj, key: t.key, url: t.url, fallbackTitle: t.title)

            if t.key == "plan" {
                let cards = obj["cards"] as? [[String: String]] ?? []
                for card in cards {
                    let text = card["x"] ?? ""
                    let nums = text.matches(of: #/(\d+)/#).compactMap { Int($0.1) }
                    var cat = PlanCategory(title: card["t"] ?? "", required: nil, completed: nil, detail: text)
                    if nums.count >= 2 { cat.required = max(nums[0], nums[1]); cat.completed = min(nums[0], nums[1]) }
                    if !cat.title.isEmpty { result.planCategories.append(cat) }
                }
            }
        }

        result.profile = Self.profile(from: result.pages)
        result.rooms = Self.rooms(from: result.pages["schedule"])
        phase = .done
        await WebSession.shared.syncCookiesToURLSession()
        onFinished?(result)
    }

    // MARK: Parsing

    static func page(from obj: [String: Any], key: String, url: URL, fallbackTitle: String = "") -> SISPage {
        let tables = (obj["tables"] as? [[String: Any]] ?? []).map {
            SISTable(headers: $0["headers"] as? [String] ?? [], rows: $0["rows"] as? [[String]] ?? [])
        }
        let title = (obj["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle
        return SISPage(key: key, title: title, url: url.absoluteString,
                       pairs: obj["pairs"] as? [[String]] ?? [], tables: tables,
                       text: obj["text"] as? String ?? "", fetchedAt: .now)
    }

    static func profile(from pages: [String: SISPage]) -> StudentProfile {
        var p = StudentProfile()
        let allPairs = pages.values.flatMap(\.pairs).filter { $0.count >= 2 }
        func value(_ words: [String]) -> String? {
            allPairs.first(where: { pair in words.contains { pair[0].contains($0) } })?[1]
        }
        let allText = pages.values.map(\.text).joined(separator: " \n ")
        func number(after words: [String]) -> Double? {
            for w in words {
                if let v = value([w]), let d = Double(v.filter { "0123456789.".contains($0) }) { return d }
                if let r = allText.range(of: w) {
                    let tail = allText[r.upperBound...].prefix(40)
                    if let m = tail.firstMatch(of: #/(\d+(?:\.\d+)?)/#), let d = Double(m.1) { return d }
                }
            }
            return nil
        }
        p.fullName = value(["اسم الطالب", "الاسم"]) ?? ""
        p.major = value(["التخصص"]) ?? ""
        p.college = value(["الكلية"]) ?? ""
        p.studentNumber = value(["الرقم الجامعي"]) ?? (allText.firstMatch(of: #/(20\d{8})/#).map { String($0.1) } ?? "")
        p.gpa = number(after: ["المعدل التراكمي"])
        if let h = number(after: ["الساعات المجتازة", "الساعات المقطوعة", "الساعات المنجزة"]) { p.passedHours = Int(h) }
        if let pct = number(after: ["نسبة إنجازك"]) { p.planPercent = Int(pct) }
        p.expectedToGraduate = value(["متوقع تخرجه"])
        p.updatedAt = .now
        return p
    }

    /// Room per course code from the SIS schedule table, if it has a room column.
    static func rooms(from page: SISPage?) -> [String: String] {
        guard let page else { return [:] }
        var out: [String: String] = [:]
        for t in page.tables {
            guard let roomCol = t.headers.firstIndex(where: { $0.contains("القاعة") || $0.contains("المكان") }) else { continue }
            for row in t.rows where row.count > roomCol {
                let joined = row.joined(separator: " ")
                if let m = joined.firstMatch(of: #/([A-Z]{2,4})\s?(\d{3}[A-Z]?)/#) {
                    let code = "\(m.1)\(m.2)"
                    let room = row[roomCol].trimmingCharacters(in: .whitespaces)
                    if !room.isEmpty { out[code] = room }
                }
            }
        }
        return out
    }

    // MARK: JS

    static func loginHelperJS(prefill: (username: String, password: String)?) -> String {
        func esc(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
            let json = String(decoding: data, as: UTF8.self)
            return String(json.dropFirst().dropLast())
        }
        let u = prefill.map { esc($0.username) } ?? "\"\""
        let p = prefill.map { esc($0.password) } ?? "\"\""
        return """
        (function(){
          var u = document.getElementById('P9999_USERNAME'), p = document.getElementById('P9999_PASSWORD');
          if (!u || !p) return;
          var pu = \(u), pp = \(p);
          if (pu && !u.value) u.value = pu;
          if (pp && !p.value) p.value = pp;
          function send(){ try { window.webkit.messageHandlers.sisCreds.postMessage({u: u.value, p: p.value}); } catch(e){} }
          document.addEventListener('click', function(e){ if (e.target.closest('button')) send(); }, true);
          p.addEventListener('keydown', function(e){ if (e.key === 'Enter') send(); });
        })();
        """
    }

    static let extractJS = """
    (function(){
      var clean = function(s){ return (s||'').replace(/\\s+/g,' ').trim(); };
      var pairs = [];
      document.querySelectorAll('.t-Form-fieldContainer').forEach(function(fc){
        var l = fc.querySelector('label, .t-Form-label');
        var v = fc.querySelector('.display_only, .t-Form-inputContainer');
        if (l && v) { var a = clean(l.innerText), b = clean(v.innerText); if (a && b && a !== b) pairs.push([a, b]); }
      });
      var tables = [];
      document.querySelectorAll('table').forEach(function(t){
        var rows = Array.prototype.map.call(t.rows, function(r){ return Array.prototype.map.call(r.cells, function(c){ return clean(c.innerText); }); });
        if (rows.length < 2) return;
        var ths = t.querySelectorAll('thead th');
        var headers = ths.length ? Array.prototype.map.call(ths, function(th){ return clean(th.innerText); }) : rows[0];
        var body = ths.length ? rows.slice(t.tHead ? t.tHead.rows.length : 1) : rows.slice(1);
        body = body.filter(function(r){ return r.some(function(x){ return x; }); }).slice(0, 300);
        if (body.length) tables.push({headers: headers, rows: body});
      });
      var cards = Array.prototype.map.call(document.querySelectorAll('.t-Card, .a-CardView, .t-Cards-item'), function(c){
        var t = c.querySelector('.t-Card-title, .a-CardView-title, h3');
        var a = c.querySelector('a');
        return {t: clean(t ? t.innerText : ''), x: clean(c.innerText), h: a ? a.href : ''};
      });
      var links = Array.prototype.map.call(document.querySelectorAll('a[href*="/ords/r/sis/"]'), function(a){ return {t: clean(a.innerText), h: a.href}; });
      return JSON.stringify({title: document.title, pairs: pairs, tables: tables, cards: cards, links: links,
        text: clean(document.body ? document.body.innerText : '').slice(0, 5000),
        login: !!document.getElementById('P9999_USERNAME')});
    })();
    """
}

struct SISResult {
    var profile = StudentProfile()
    var pages: [String: SISPage] = [:]
    var planCategories: [PlanCategory] = []
    var rooms: [String: String] = [:]
}

/// Avoids a retain cycle between WKUserContentController and its handler.
final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ t: WKScriptMessageHandler) { target = t }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}

/// The SIS web view, shown during login (SMS code etc.), then it syncs by itself.
struct SISLoginView: UIViewRepresentable {
    let sync: SISSync
    func makeUIView(context: Context) -> WKWebView { sync.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
