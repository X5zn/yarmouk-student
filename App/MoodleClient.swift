import Foundation
import WebKit

enum MoodleError: Error { case needsLogin, badResponse(String) }

/// Talks to elearning.yu.edu.jo the same way the site's own pages do (session AJAX),
/// using the session he created by signing in inside the app.
final class MoodleClient {
    static let shared = MoodleClient()
    let base = URL(string: "https://elearning.yu.edu.jo")!
    private var sesskey: String?
    private(set) var userId: Int?

    private var session: URLSession {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 25
        c.httpAdditionalHeaders = ["User-Agent": UserAgent.mobileSafari, "Accept-Language": "ar,en;q=0.8"]
        return URLSession(configuration: c)
    }

    // MARK: session

    /// Loads /my/ and reads the sesskey. Throws needsLogin if Moodle shows the login page.
    @discardableResult
    func ensureSession() async throws -> String {
        let (data, resp) = try await session.data(from: base.appendingPathComponent("my/"))
        let finalURL = (resp as? HTTPURLResponse)?.url?.absoluteString ?? ""
        let html = String(decoding: data, as: UTF8.self)
        if finalURL.contains("/login/") || !html.contains("\"sesskey\"") { throw MoodleError.needsLogin }
        guard let key = html.firstMatch(of: #/"sesskey":"([^"]+)"/#)?.1 else { throw MoodleError.needsLogin }
        sesskey = String(key)
        if let uid = html.firstMatch(of: #/"userId":(\d+)/#)?.1 { userId = Int(uid) }
        return String(key)
    }

    /// Microsoft keeps him signed in ("stay signed in"), so an expired Moodle session can be
    /// renewed silently by visiting the OIDC entry in an invisible web view.
    @MainActor
    func silentReauth() async -> Bool {
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: WebSession.shared.configuration())
        wv.customUserAgent = UserAgent.mobileSafari
        wv.load(URLRequest(url: base.appendingPathComponent("auth/oidc/").appending(queryItems: [URLQueryItem(name: "source", value: "loginpage")])))
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(500))
            if let u = wv.url?.absoluteString, u.contains("elearning.yu.edu.jo/my") {
                await WebSession.shared.syncCookiesToURLSession()
                return true
            }
        }
        return false
    }

    func withSession<T>(_ body: () async throws -> T) async throws -> T {
        do {
            if sesskey == nil { try await ensureSession() }
            return try await body()
        } catch MoodleError.needsLogin {
            try await ensureSession()
            return try await body()
        }
    }

    // MARK: AJAX

    func call(_ method: String, _ args: [String: Any]) async throws -> Any {
        guard let key = sesskey else { throw MoodleError.needsLogin }
        var comps = URLComponents(url: base.appendingPathComponent("lib/ajax/service.php"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "sesskey", value: key), URLQueryItem(name: "info", value: method)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [["index": 0, "methodname": method, "args": args]])
        let (data, _) = try await session.data(for: req)
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], let first = arr.first else {
            // A login redirect returns HTML, not JSON.
            sesskey = nil
            throw MoodleError.needsLogin
        }
        if (first["error"] as? Bool) == true {
            let exc = first["exception"] as? [String: Any]
            let code = exc?["errorcode"] as? String ?? "unknown"
            if code == "servicerequireslogin" || code == "invalidsesskey" || code == "requireloginerror" {
                sesskey = nil
                throw MoodleError.needsLogin
            }
            throw MoodleError.badResponse(code)
        }
        return first["data"] ?? NSNull()
    }

    // MARK: Typed reads

    func courses() async throws -> [MoodleCourse] {
        try await withSession {
            let d = try await call("core_course_get_enrolled_courses_by_timeline_classification",
                                   ["classification": "inprogress", "limit": 0, "offset": 0, "sort": "fullname"])
            let list = (d as? [String: Any])?["courses"] as? [[String: Any]] ?? []
            return list.map {
                MoodleCourse(id: J.int($0["id"]), fullName: J.str($0["fullname"]).trimmingCharacters(in: .whitespaces),
                             shortName: J.str($0["shortname"]), progress: $0["progress"] as? Double)
            }
        }
    }

    func profile() async throws -> (fullName: String, firstName: String, idNumber: String, email: String)? {
        try await withSession {
            guard let uid = userId else { return nil }
            let d = try await call("core_user_get_users_by_field", ["field": "id", "values": [String(uid)]])
            guard let u = (d as? [[String: Any]])?.first else { return nil }
            return (J.str(u["fullname"]), J.str(u["firstname"]), J.str(u["idnumber"]), J.str(u["email"]))
        }
    }

    /// All upcoming dated activities (assignments, quizzes) + which of them still need action.
    func deadlines(known: [Deadline]) async throws -> [Deadline] {
        try await withSession {
            let up = try await call("core_calendar_get_calendar_upcoming_view", ["courseid": 1, "categoryid": 0])
            let events = (up as? [String: Any])?["events"] as? [[String: Any]] ?? []
            let now = Int(Date().timeIntervalSince1970)
            let act = try? await call("core_calendar_get_action_events_by_timesort",
                                      ["timesortfrom": now - 86400 * 30, "limitnum": 50])
            let actionable = Set(((act as? [String: Any])?["events"] as? [[String: Any]] ?? []).map { J.int($0["id"]) })
            let knownById = Dictionary(known.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return events.compactMap { e -> Deadline? in
                let module = J.str(e["modulename"])
                guard ["assign", "quiz", "workshop", "lesson"].contains(module) else { return nil }
                let id = J.int(e["id"])
                let course = e["course"] as? [String: Any]
                let name = J.str(e["activityname"]).isEmpty ? J.str(e["name"]) : J.str(e["activityname"])
                return Deadline(id: id, name: name, courseId: J.int(course?["id"]),
                                due: Date(timeIntervalSince1970: TimeInterval(J.int(e["timesort"]))),
                                url: J.str(e["url"]), kind: module,
                                submitted: !actionable.contains(id),
                                firstSeen: knownById[id]?.firstSeen ?? .now)
            }
        }
    }

    func sections(courseId: Int) async throws -> [MoodleSection] {
        try await withSession {
            let d = try await call("core_courseformat_get_state", ["courseid": courseId])
            var obj: [String: Any] = [:]
            if let s = d as? String, let data = s.data(using: .utf8) {
                obj = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            } else if let o = d as? [String: Any] { obj = o }
            let cms = (obj["cm"] as? [[String: Any]] ?? []).reduce(into: [String: MoodleModule]()) { acc, c in
                guard (c["uservisible"] as? Bool) ?? true else { return }
                let id = J.str(c["id"])
                acc[id] = MoodleModule(id: id, name: J.str(c["name"]), kind: J.str(c["module"]), url: c["url"] as? String)
            }
            let secs = obj["section"] as? [[String: Any]] ?? []
            return secs.compactMap { (s) -> MoodleSection? in
                let mods = (s["cmlist"] as? [Any] ?? []).compactMap { cms[J.str($0)] }
                if mods.isEmpty { return nil }
                var title = J.str(s["title"])
                if title == "General" { title = "عام" }
                if title == "New section" { title = "القسم \(J.int(s["number"]))" }
                return MoodleSection(id: J.str(s["id"]), number: J.int(s["number"]), title: title, modules: mods)
            }
        }
    }

    func notices() async throws -> [MoodleNotice] {
        try await withSession {
            guard let uid = userId else { return [] }
            let d = try await call("message_popup_get_popup_notifications", ["useridto": uid, "limit": 30, "offset": 0])
            let list = (d as? [String: Any])?["notifications"] as? [[String: Any]] ?? []
            return list.map {
                MoodleNotice(id: J.int($0["id"]), subject: J.str($0["subject"]),
                             text: J.str($0["smallmessage"]), url: $0["contexturl"] as? String,
                             date: Date(timeIntervalSince1970: TimeInterval(J.int($0["timecreated"]))),
                             read: ($0["read"] as? Bool) ?? false)
            }
        }
    }
}

/// Lenient JSON value readers (Moodle mixes strings and numbers).
enum J {
    static func int(_ v: Any?) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) ?? 0 }
        if let n = v as? NSNumber { return n.intValue }
        return 0
    }
    static func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let i = v as? Int { return String(i) }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }
}
