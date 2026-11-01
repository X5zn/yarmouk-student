import Foundation
import WebKit
import SwiftUI

/// One SIS session for the whole app.
/// Signs in once (his own username, password and SMS code inside the university's page),
/// remembers the APEX session id, and reuses it for every SIS page until SIS itself expires it.
@MainActor
final class SISSync: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    enum Phase: Equatable { case checking, login, syncing(String), done, needsLogin, failed(String) }

    @Published var phase: Phase = .checking
    @Published var rememberPassword = true
    let webView: WKWebView
    /// true = the login sheet (shows the page when SIS asks for a login); false = background refresh.
    let interactive: Bool
    var onFinished: (@MainActor (SISResult) -> Void)?
    var onNeedsLogin: (@MainActor () -> Void)?

    private var navContinuation: CheckedContinuation<Void, Never>?
    private var started = false
    private var triedSaved = false
    private var timeoutTask: Task<Void, Never>?

    static let base = "https://sis.yu.edu.jo/ords/r/sis/sis/"
    static let root = URL(string: "https://sis.yu.edu.jo/ords/")!
    private static let sessionKey = "sis.apexSession"

    static var savedSession: String? {
        get { UserDefaults.standard.string(forKey: sessionKey) }
        set { UserDefaults.standard.set(newValue, forKey: sessionKey) }
    }

    init(interactive: Bool = true) {
        self.interactive = interactive
        let config = WebSession.shared.configuration()
        let ucc = WKUserContentController()
        config.userContentController = ucc
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        super.init()
        webView.customUserAgent = UserAgent.mobileSafari
        webView.navigationDelegate = self
        webView.isInspectable = true
        ucc.add(WeakHandler(self), name: "sisCreds")
        ucc.addUserScript(WKUserScript(source: Self.loginHelperJS(prefill: Keychain.load()),
                                       injectionTime: .atDocumentEnd, forMainFrameOnly: true))
    }

    /// Try the saved session first; only show the login page when SIS really asks for it.
    func start() {
        started = false
        timeoutTask?.cancel()
        Task {
            await WebSession.shared.restoreCookies()
            if let s = Self.savedSession, !s.isEmpty {
                triedSaved = true
                phase = .checking
                webView.load(URLRequest(url: URL(string: Self.base + "home?session=\(s)")!))
                armTimeout(seconds: 25)
            } else {
                triedSaved = false
                showLogin()
            }
        }
    }

    private func showLogin() {
        timeoutTask?.cancel()
        if interactive {
            phase = .login
            if webView.url == nil || !(webView.url?.absoluteString.contains("login") ?? false) {
                webView.load(URLRequest(url: Self.root))
            }
        } else {
            phase = .needsLogin
            onNeedsLogin?()
        }
    }

    private func armTimeout(seconds: Double) {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled, !self.started else { return }
            if self.phase == .checking { self.showLogin() }
        }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navContinuation?.resume(); navContinuation = nil
        guard !started, let current = webView.url else { return }
        Task { await self.evaluateLanding(current) }
    }

    private func evaluateLanding(_ current: URL) async {
        guard !started else { return }
        let isLogin = ((try? await webView.evaluateJavaScript(Self.isLoginJS)) as? Bool) ?? false
        let path = current.absoluteString
        if !isLogin, path.contains("/ords/r/sis/sis/home"), let session = Self.session(in: current), !session.isEmpty {
            started = true
            timeoutTask?.cancel()
            Self.savedSession = session
            await runSync(session: session)
        } else if isLogin {
            if phase == .checking || !interactive {
                if triedSaved { Self.savedSession = nil }
                showLogin()
            }
        }
        // anything else (SMS code page, redirects) → wait for the next page
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navContinuation?.resume(); navContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navContinuation?.resume(); navContinuation = nil
        if !started && phase == .checking {
            phase = .failed("ما قدرنا نوصل لـ SIS، تأكد من النت")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: String], let u = body["u"], let p = body["p"], !u.isEmpty, !p.isEmpty else { return }
        if rememberPassword { Keychain.save(username: u, password: p) }
    }

    static func session(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "session" })?.value
    }

    private func go(_ url: URL) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            navContinuation?.resume()
            navContinuation = c
            webView.load(URLRequest(url: url))
        }
        // APEX fills some reports right after load; wait until the page stops changing.
        var last = -1
        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(400))
            let n = ((try? await webView.evaluateJavaScript("document.querySelectorAll('td, dd, .display_only, .t-Card').length")) as? Int) ?? 0
            if n == last && n > 0 { break }
            last = n
        }
    }

    private func extract() async -> SISExtract {
        guard let raw = try? await webView.evaluateJavaScript(Self.extractJS) as? String,
              let data = raw.data(using: .utf8),
              var obj = try? JSONDecoder().decode(SISExtract.self, from: data) else { return SISExtract() }
        obj.url = webView.url?.absoluteString ?? ""
        return obj
    }

    private func pageHTML() async -> String {
        ((try? await webView.evaluateJavaScript("document.documentElement.outerHTML")) as? String) ?? ""
    }

    // MARK: Sync

    private func runSync(session: String) async {
        var result = SISResult()
        func page(_ slug: String) -> URL { URL(string: Self.base + slug + "?session=\(session)")! }

        phase = .syncing("الصفحة الرئيسية")
        if !(webView.url?.absoluteString.contains("/home") ?? false) { await go(page("home")) }
        let home = await extract()
        if home.login { Self.savedSession = nil; started = false; showLogin(); return }
        result.extracts["home"] = home
        result.html["home"] = await pageHTML()

        // Menu items, by their Arabic names (links carry the live session).
        func link(_ words: [String], excluding: [String] = []) -> URL? {
            home.links.first { l in
                words.contains { l.t.contains($0) } && !excluding.contains { l.t.contains($0) } && l.h.contains("/ords/r/sis/sis/")
            }.flatMap { URL(string: $0.h) }
        }
        func slug(_ arabic: String) -> String { arabic.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? arabic }

        let targets: [(key: String, title: String, urls: [URL])] = [
            ("info", "المعلومات الأساسية", [page("student-information")]),
            ("records", "السجل الأكاديمي", [page("academic-records")]),
            ("registered", "موادي هالفصل", [link(["المواد المسجلة"]), page(slug("استطلاع-المواد-المسجلة"))].compactMap { $0 }),
            ("marks", "العلامات", [link(["إستطلاع العلامات", "استطلاع العلامات", "العلامات"], excluding: ["التراكمية"]),
                                   page(slug("إستطلاع-العلامات")), page(slug("استطلاع-العلامات"))].compactMap { $0 }),
            ("plan", "الخطة الدراسية", [page("study-plan")]),
            ("finance", "المالية", [link(["الخدمات المالية", "المالية"])].compactMap { $0 })
        ]

        for t in targets {
            phase = .syncing(t.title)
            for url in t.urls {
                await go(url)
                let obj = await extract()
                if obj.login {
                    // SIS dropped the session mid-way: keep what we have, ask for login next time.
                    Self.savedSession = nil
                    break
                }
                let landedHome = (webView.url?.absoluteString.contains("/home?") ?? false) && t.key != "home"
                if !obj.error.isEmpty || landedHome { continue }   // wrong guess → try the next address
                result.extracts[t.key] = obj
                result.html[t.key] = await pageHTML()
                break
            }
            if Self.savedSession == nil { break }
        }

        result.build()
        phase = .done
        await WebSession.shared.syncCookiesToURLSession()
        onFinished?(result)
    }

    // MARK: JS

    static let isLoginJS = "!!(document.getElementById('P9999_USERNAME') || document.querySelector('input[type=password]'))"

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
          if (!u) {
            // SMS code page: let iOS offer the code from Messages above the keyboard.
            document.querySelectorAll('input[type=text], input[type=number], input[type=tel], input:not([type])').forEach(function(i){
              i.setAttribute('autocomplete', 'one-time-code'); i.setAttribute('inputmode', 'numeric');
            });
          }
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

    /// Reads the page from its DOM (label → value items, report tables by column header,
    /// main-content lines). Never the whole body text: navigation, header and footer are skipped.
    static let extractJS = #"""
    (function(){
      function clean(s){ return (s||'').replace(/[\u00a0\s]+/g,' ').trim(); }
      var NAV = '#t_TreeNav, .t-Body-nav, .t-Header, .t-Footer, nav, header.t-Header, .t-NavigationBar, .a-TreeView';
      function inNav(el){ return !!(el && el.closest && el.closest(NAV)); }
      var main = document.querySelector('.t-Body-contentInner') || document.querySelector('#t_Body_content') ||
                 document.querySelector('main') || document.querySelector('.t-Body-main') || document.body;

      function regionTitle(el){
        var r = el.closest('.t-Region, .t-TabsRegion-item, .a-Tabs-panel, section');
        while (r) {
          var t = r.querySelector('.t-Region-title, .t-Region-header h2, h2');
          if (r.getAttribute && r.getAttribute('aria-label')) return clean(r.getAttribute('aria-label'));
          if (t && clean(t.textContent)) return clean(t.textContent);
          r = r.parentElement ? r.parentElement.closest('.t-Region, section') : null;
        }
        return '';
      }
      function valueOf(el){
        if (!el) return '';
        if (el.tagName === 'SELECT') { var o = el.options[el.selectedIndex]; return o ? clean(o.text) : ''; }
        if (el.tagName === 'INPUT') { if (el.type === 'password' || el.type === 'hidden') return ''; if (el.type === 'checkbox' || el.type === 'radio') return el.checked ? 'نعم' : ''; return clean(el.value); }
        if (el.tagName === 'TEXTAREA') return clean(el.value);
        var d = el.querySelector && el.querySelector('.display_only, .apex-item-display-only, select, input:not([type=hidden]), textarea');
        if (d && d !== el) return valueOf(d);
        var m = el.querySelector && el.querySelector('[aria-valuenow]');
        if (m && !clean(el.textContent)) return clean(m.getAttribute('aria-valuenow')) + '%';
        return clean(el.textContent);
      }

      var pairs = [], seen = {};
      function add(l, v, sec){
        l = clean(clean(l).replace(/\(Value Required\)/ig, '')).replace(/[:：]\s*$/, ''); v = clean(v);
        if (!l || l.length > 90 || v.length > 400) return;
        if (l === v) v = '';
        var k = l + '|' + v; if (seen[k]) return; seen[k] = 1;
        pairs.push([l, v, sec || '']);
      }
      var used = new Set();
      main.querySelectorAll('.t-Form-fieldContainer').forEach(function(fc){
        if (inNav(fc)) return;
        var l = fc.querySelector('.t-Form-labelContainer label, .t-Form-label, label');
        var v = fc.querySelector('.t-Form-inputContainer, .t-Form-itemWrapper, .display_only');
        if (l) { used.add(l); add(l.textContent, valueOf(v), regionTitle(fc)); }
      });
      main.querySelectorAll('label[for]').forEach(function(l){
        if (used.has(l) || inNav(l)) return;
        var id = l.getAttribute('for');
        var t = document.getElementById(id) || document.getElementById(id + '_DISPLAY');
        if (t) add(l.textContent, valueOf(t), regionTitle(l));
      });
      main.querySelectorAll('[aria-labelledby]').forEach(function(el){
        if (inNav(el) || el.closest('table')) return;
        var l = document.getElementById(el.getAttribute('aria-labelledby').split(' ')[0]);
        if (l && !used.has(l) && l.tagName !== 'TABLE') add(l.textContent, valueOf(el), regionTitle(el));
      });
      main.querySelectorAll('dl').forEach(function(dl){
        if (inNav(dl)) return;
        var dts = dl.querySelectorAll('dt');
        dts.forEach(function(dt){ var dd = dt.nextElementSibling; while (dd && dd.tagName !== 'DD') dd = dd.nextElementSibling; if (dd) add(dt.textContent, valueOf(dd), regionTitle(dl)); });
      });
      main.querySelectorAll('.t-AVPList-label, .t-ContextualInfo-label, [class*="-label"]:not(label):not(.t-Form-label)').forEach(function(l){
        if (inNav(l)) return;
        var v = l.nextElementSibling;
        if (v && /value/i.test(v.className || '')) add(l.textContent, valueOf(v), regionTitle(l));
      });

      var tables = [];
      main.querySelectorAll('table').forEach(function(t){
        if (inNav(t) || t.querySelector('table')) return;
        var ths = Array.prototype.slice.call(t.querySelectorAll('thead th'));
        if (!ths.length && t.rows.length) ths = Array.prototype.slice.call(t.rows[0].querySelectorAll('th'));
        var headers = ths.map(function(th){ return clean(th.textContent); });
        var byId = {}; ths.forEach(function(th, i){ if (th.id) byId[th.id] = i; });
        var rows = [];
        Array.prototype.forEach.call(t.querySelectorAll('tbody tr'), function(tr){
          var tds = tr.querySelectorAll('td');
          if (!tds.length) return;
          if (tds.length === 1 && tr.querySelectorAll('th').length === 1) { add(tr.querySelector('th').textContent, valueOf(tds[0]), regionTitle(t)); return; }
          var row = headers.length ? headers.map(function(){ return ''; }) : [];
          Array.prototype.forEach.call(tds, function(td, i){
            var idx = i, h = (td.getAttribute('headers') || '').split(' ')[0];
            if (h && byId[h] !== undefined) idx = byId[h];
            var v = valueOf(td);
            if (!v && td.querySelector('img[alt], [title]')) { var x = td.querySelector('img[alt], [title]'); v = clean(x.getAttribute('alt') || x.getAttribute('title')); }
            row[idx] = v;
          });
          if (row.some(function(x){ return x; })) rows.push(row.slice(0, Math.max(headers.length, row.length)));
        });
        if (rows.length) tables.push({title: regionTitle(t), id: t.id || '', headers: headers, rows: rows.slice(0, 400)});
      });

      var cards = Array.prototype.map.call(main.querySelectorAll('.t-Card, .a-CardView, .t-Cards-item'), function(c){
        var t = c.querySelector('.t-Card-title, .a-CardView-title, h3');
        var a = c.querySelector('a');
        return {t: clean(t ? t.textContent : ''), x: clean(c.innerText), h: a ? a.href : ''};
      });

      var links = [], lseen = {};
      function addLink(t, h){ t = clean(t); if (!t || !h || lseen[t + h]) return; lseen[t + h] = 1; links.push({t: t, h: h}); }
      document.querySelectorAll('a[href]').forEach(function(a){
        var h = a.getAttribute('href') || '';
        if (h.indexOf('javascript:') === 0) return;
        addLink(a.textContent, a.href);
      });
      // APEX builds the side menu from JSON in a script; read it too (collapsed items have no <a> yet).
      Array.prototype.forEach.call(document.scripts, function(s){
        var src = s.textContent || '';
        if (src.indexOf('/ords/r/sis/') < 0 && src.indexOf('"link"') < 0) return;
        var re = /"label"\s*:\s*"((?:[^"\\]|\\.)*)"[^{}]*?"link"\s*:\s*"((?:[^"\\]|\\.)*)"/g, m;
        while ((m = re.exec(src))) {
          try { var t = JSON.parse('"' + m[1] + '"'), h = JSON.parse('"' + m[2] + '"'); addLink(t, new URL(h, location.href).href); } catch(e) {}
        }
      });

      var lines = (main.innerText || '').split('\n').map(clean).filter(function(x){ return x; }).slice(0, 2000);
      var err = document.querySelector('.t-Alert--danger, #t_Alert_Notification .t-Alert-title, .apex-page-error');
      var title = document.title || '';
      var errText = err ? clean(err.textContent) : '';
      if (/404|not found|غير موجود|Error/i.test(title) && !tables.length && !pairs.length) errText = errText || title;
      return JSON.stringify({title: title, url: location.href, pairs: pairs, tables: tables, lines: lines, links: links, cards: cards,
        login: !!(document.getElementById('P9999_USERNAME') || document.querySelector('input[type=password]')),
        error: errText});
    })();
    """#
}

/// Everything one sync brought back, already parsed.
struct SISResult {
    var extracts: [String: SISExtract] = [:]
    var html: [String: String] = [:]
    var profile = StudentProfile()
    var pages: [String: SISPage] = [:]
    var planCategories: [PlanCategory] = []
    var rooms: [String: String] = [:]
    var data = SISData()

    mutating func build() {
        for (key, e) in extracts {
            pages[key] = SISPage(key: key, title: e.title, url: e.url, pairs: e.pairs.map { Array($0.prefix(2)) },
                                 tables: e.tables.map { SISTable(headers: $0.headers, rows: $0.rows) },
                                 text: e.lines.joined(separator: "\n"), fetchedAt: .now)
        }
        if let e = extracts["records"] { data.record = AcademicRecordParser.parse(lines: e.lines, pairs: e.pairs) }
        if let e = extracts["info"] { data.info = StudentInfoParser.parse(pairs: e.pairs, lines: e.lines) }
        if let e = extracts["registered"] { data.registered = RegisteredCoursesParser.parse(tables: e.tables) }
        if let e = extracts["marks"] {
            var m = MarksParser.parse(tables: e.tables, lines: e.lines)
            if let term = e.pairs.first(where: { $0.count >= 2 && $0[0].contains("الفصل") && !$0[1].isEmpty })?[1] { m.term = term }
            data.marks = m
        }
        data.otherPages = pages.filter { ["finance"].contains($0.key) }
        data.updatedAt = .now

        if let e = extracts["plan"] {
            for card in e.cards {
                let nums = SISText.allMatches(#"(\d+)"#, in: card.x).compactMap { Int($0.groups[1]) }
                var cat = PlanCategory(title: card.t, required: nil, completed: nil, detail: card.x)
                if nums.count >= 2 { cat.required = max(nums[0], nums[1]); cat.completed = min(nums[0], nums[1]) }
                if !cat.title.isEmpty { planCategories.append(cat) }
            }
        }

        var p = StudentProfile()
        if let info = data.info {
            p.fullName = info.value("الاسم بالعربية") ?? info.name
            p.major = info.value("التخصص") ?? ""
            p.college = info.value("الكلية") ?? ""
            p.expectedToGraduate = info.value("متوقع تخرجه؟")
            if p.gpa == nil { p.gpa = SISText.double(info.value("المعدل التراكمي")) }
        }
        if let r = data.record {
            p.gpa = r.summary.cumulativeGPA ?? p.gpa
            p.passedHours = r.summary.passedHours ?? r.summary.cumulativeHours
        }
        if let reg = data.registered, !reg.isEmpty {
            p.inProgressHours = reg.compactMap(\.hours).reduce(0, +)
            for c in reg where !c.room.isEmpty { rooms[c.compactCode] = c.room }
        }
        if let home = extracts["home"] {
            p.planPercent = SISHomeParser.planPercent(lines: home.lines)
            p.studentNumber = SISHomeParser.studentNumber(in: home.links.map(\.t).joined(separator: " ") + " " + home.lines.joined(separator: " ")) ?? ""
        }
        p.updatedAt = .now
        profile = p
    }

    /// Strings to hide in the developer export.
    var secrets: [String] {
        var s: [String] = []
        if let info = data.info {
            s += [info.name, info.value("الاسم بالعربية"), info.value("الاسم بالانجليزية"), info.value("الاسم بالإنجليزية"),
                  info.value("الرقم الوطني"), info.value("تاريخ الولادة"), info.value("مكان الولادة")].compactMap { $0 }
        }
        if !profile.studentNumber.isEmpty { s.append(profile.studentNumber) }
        return s
    }
}

/// Parsed SIS data the native screens show. Saved on the phone.
struct SISData: Codable, Hashable {
    var record: AcademicRecord?
    var info: StudentInfo?
    var registered: [RegisteredCourse]?
    var marks: MarksPage?
    var otherPages: [String: SISPage] = [:]
    var updatedAt: Date?

    private static var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sis-data.json")
    }
    static func load() -> SISData {
        guard let d = try? Data(contentsOf: file), let v = try? JSONDecoder().decode(SISData.self, from: d) else { return SISData() }
        return v
    }
    func save() {
        if let d = try? JSONEncoder().encode(self) {
            try? d.write(to: Self.file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
    /// Keep old values when a page didn't come this time.
    mutating func merge(_ new: SISData) {
        if let r = new.record, !r.isEmpty { record = r }
        if let i = new.info, !i.isEmpty { info = i }
        if let g = new.registered, !g.isEmpty { registered = g }
        if let m = new.marks { marks = m }
        otherPages.merge(new.otherPages) { _, n in n }
        updatedAt = new.updatedAt ?? updatedAt
    }
}

/// Masked copies of the SIS pages, for «ارسل صفحة للمطور».
enum SISDebugStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("sis-pages", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static let titles: [String: String] = ["home": "الرئيسية", "info": "المعلومات الأساسية", "records": "السجل الأكاديمي",
                                           "registered": "موادي هالفصل", "marks": "العلامات", "plan": "الخطة الدراسية", "finance": "المالية"]
    static func save(_ result: SISResult) {
        let secrets = result.secrets
        for (key, html) in result.html where !html.isEmpty {
            let masked = SISMask.mask(html, secrets: secrets)
            let url = dir.appendingPathComponent("sis-\(key).html")
            try? Data(masked.utf8).write(to: url, options: .atomic)
        }
    }
    struct File: Identifiable { var key: String; var title: String; var url: URL; var date: Date; var id: String { key } }
    static func files() -> [File] {
        let keys = ["records", "info", "marks", "registered", "plan", "finance", "home"]
        return keys.compactMap { k in
            let u = dir.appendingPathComponent("sis-\(k).html")
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: u.path) else { return nil }
            return File(key: k, title: titles[k] ?? k, url: u, date: attrs[.modificationDate] as? Date ?? .now)
        }
    }
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
