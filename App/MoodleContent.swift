import SwiftUI
import WebKit
import QuickLook

// Native course content from e-learning: files open in QuickLook, links/pages in the in-app browser,
// announcements / folders / assignments read into native screens. Nothing hands off to Safari.

// MARK: - File type from the course page icons

enum MoodleFileKind: String, Codable {
    case pdf, document, spreadsheet, powerpoint, image, archive, video, audio, text, generic

    init(icon: String) {
        let s = icon.lowercased()
        if s.contains("pdf") { self = .pdf }
        else if s.contains("document") || s.contains("writer") || s.contains("word") { self = .document }
        else if s.contains("spreadsheet") || s.contains("excel") || s.contains("calc") { self = .spreadsheet }
        else if s.contains("powerpoint") || s.contains("impress") || s.contains("presentation") { self = .powerpoint }
        else if s.contains("image") || s.contains("jpeg") || s.contains("png") { self = .image }
        else if s.contains("archive") || s.contains("zip") || s.contains("rar") { self = .archive }
        else if s.contains("video") || s.contains("mpeg") || s.contains("mp4") { self = .video }
        else if s.contains("audio") || s.contains("mp3") { self = .audio }
        else if s.contains("text") { self = .text }
        else { self = .generic }
    }

    init(fileName: String) {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "pdf": self = .pdf
        case "doc", "docx", "rtf", "odt", "pages": self = .document
        case "xls", "xlsx", "csv", "ods", "numbers": self = .spreadsheet
        case "ppt", "pptx", "odp", "key": self = .powerpoint
        case "png", "jpg", "jpeg", "heic", "gif", "webp": self = .image
        case "zip", "rar", "7z": self = .archive
        case "mp4", "mov", "m4v": self = .video
        case "mp3", "m4a", "wav", "aac": self = .audio
        case "txt": self = .text
        default: self = .generic
        }
    }

    var symbol: String {
        switch self {
        case .pdf: return "doc.richtext.fill"
        case .document: return "doc.text.fill"
        case .spreadsheet: return "tablecells.fill"
        case .powerpoint: return "rectangle.on.rectangle.angled.fill"
        case .image: return "photo.fill"
        case .archive: return "doc.zipper"
        case .video: return "play.rectangle.fill"
        case .audio: return "waveform"
        case .text: return "doc.plaintext.fill"
        case .generic: return "doc.fill"
        }
    }
    var tint: Color {
        switch self {
        case .pdf: return Color(red: 0.86, green: 0.2, blue: 0.18)
        case .document: return Color(red: 0.16, green: 0.38, blue: 0.85)
        case .spreadsheet: return Color(red: 0.1, green: 0.55, blue: 0.3)
        case .powerpoint: return Color(red: 0.9, green: 0.42, blue: 0.13)
        case .image: return .teal
        case .archive: return .brown
        case .video: return .purple
        case .audio: return .pink
        case .text, .generic: return .gray
        }
    }
    var label: String {
        switch self {
        case .pdf: return "PDF"
        case .document: return "Word"
        case .spreadsheet: return "Excel"
        case .powerpoint: return "PowerPoint"
        case .image: return "صورة"
        case .archive: return "ملف مضغوط"
        case .video: return "فيديو"
        case .audio: return "صوت"
        case .text: return "نص"
        case .generic: return "ملف"
        }
    }
}

extension MoodleClient {
    /// cm id → file icon name, read from the course page (the AJAX state does not say the file type).
    func fileKinds(courseId: Int) async -> [String: MoodleFileKind] {
        guard let url = URL(string: "https://elearning.yu.edu.jo/course/view.php?id=\(courseId)"),
              let res = try? await MoodleHTTP.session.data(from: url) else { return [:] }
        let html = String(decoding: res.0, as: UTF8.self)
        var out: [String: MoodleFileKind] = [:]
        let chunks = html.components(separatedBy: "id=\"module-")
        for chunk in chunks.dropFirst() {
            let id = String(chunk.prefix { $0.isNumber })
            guard !id.isEmpty else { continue }
            let head = String(chunk.prefix(2500))
            if let m = head.firstMatch(of: #/\/f\/([a-zA-Z0-9_\-]+)/#) {
                out[id] = MoodleFileKind(icon: String(m.1))
            }
        }
        return out
    }
}

/// URLSession that carries the signed-in e-learning cookies.
enum MoodleHTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 40
        c.httpAdditionalHeaders = ["User-Agent": UserAgent.mobileSafari, "Accept-Language": "ar,en;q=0.8"]
        return URLSession(configuration: c)
    }()

    static func isLoginPage(_ resp: URLResponse?) -> Bool {
        let u = resp?.url?.absoluteString ?? ""
        return u.contains("/login/index.php") || u.contains("login.microsoftonline.com") || u.contains("/auth/oidc")
    }
}

// MARK: - Downloads (cached on the phone)

enum FileFetchError: LocalizedError {
    case login, notFile, failed(String)
    var errorDescription: String? {
        switch self {
        case .login: return "جلسة الايليرنينغ خلصت، سجّل دخول مرة ثانية من «حسابي»"
        case .notFile: return "هاد مش ملف بينفتح، رح نفتحه كصفحة"
        case .failed(let s): return s
        }
    }
}

@MainActor
final class FileStore: ObservableObject {
    static let shared = FileStore()
    @Published var downloading: Set<String> = []

    private var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CourseFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func cached(_ key: String) -> URL? {
        let folder = dir.appendingPathComponent(key.safeFileName, isDirectory: true)
        guard let f = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first else { return nil }
        return f
    }

    /// Downloads a Moodle file (resource view URL or pluginfile URL) and returns the local copy.
    func fetch(key: String, url: URL) async throws -> URL {
        if let c = cached(key) { return c }
        downloading.insert(key)
        defer { downloading.remove(key) }
        var target = url
        if url.path.contains("/mod/resource/view.php"), var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            comps.queryItems = (comps.queryItems ?? []).filter { $0.name != "redirect" } + [URLQueryItem(name: "redirect", value: "1")]
            target = comps.url ?? url
        }
        let (tmp, resp) = try await MoodleHTTP.session.download(from: target)
        if MoodleHTTP.isLoginPage(resp) { throw FileFetchError.login }
        let mime = (resp as? HTTPURLResponse)?.mimeType ?? ""
        if mime.contains("text/html") { throw FileFetchError.notFile }
        let name = resp.suggestedFilename ?? resp.url?.lastPathComponent.removingPercentEncoding ?? "file"
        let folder = dir.appendingPathComponent(key.safeFileName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dest = folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        return dest
    }

    var cacheSizeText: String {
        let fm = FileManager.default
        let files = (fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])?.allObjects as? [URL]) ?? []
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func clear() {
        try? FileManager.default.removeItem(at: dir)
        objectWillChange.send()
    }
}

extension String {
    /// "ملخص الوحدة.pdf" → "ملخص الوحدة" (the type shows as an icon + label instead).
    var displayFileName: String {
        let ext = (self as NSString).pathExtension
        guard !ext.isEmpty, ext.count <= 5 else { return self }
        return (self as NSString).deletingPathExtension
    }
    var safeFileName: String { replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression) }
}

// MARK: - Where a Moodle link really goes (Teams, SharePoint, YouTube…)

final class RedirectCatcher: NSObject, URLSessionTaskDelegate {
    var target: URL?
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        if let u = request.url, !(u.host ?? "").contains("elearning.yu.edu.jo") {
            target = u
            return nil
        }
        return request
    }
}

enum LinkResolver {
    static func resolve(_ url: URL) async -> URL {
        guard url.path.contains("/mod/url/view.php"), var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        comps.queryItems = (comps.queryItems ?? []).filter { $0.name != "redirect" } + [URLQueryItem(name: "redirect", value: "1")]
        guard let u = comps.url else { return url }
        let catcher = RedirectCatcher()
        var req = URLRequest(url: u)
        req.timeoutInterval = 15
        _ = try? await MoodleHTTP.session.data(for: req, delegate: catcher)
        return catcher.target ?? url
    }

    static func isTeams(_ url: URL) -> Bool {
        let s = url.absoluteString.lowercased()
        return s.contains("teams.microsoft") || s.contains("teams.live") || s.hasPrefix("msteams:")
    }
}

// MARK: - Reading Moodle pages into native screens

/// Loads a signed-in Moodle page in an invisible web view and runs a small extractor on its DOM.
@MainActor
enum HTMLReader {
    static func read<T: Decodable>(_ url: URL, script: String, as type: T.Type) async throws -> T {
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: WebSession.shared.configuration())
        wv.customUserAgent = UserAgent.mobileSafari
        wv.load(URLRequest(url: url))
        var waited = 0
        try? await Task.sleep(for: .milliseconds(400))
        while wv.isLoading && waited < 60 { try? await Task.sleep(for: .milliseconds(250)); waited += 1 }
        let u = wv.url?.absoluteString ?? ""
        if u.contains("/login/") || u.contains("microsoftonline") || u.contains("/auth/oidc") { throw FileFetchError.login }
        let result = try await wv.evaluateJavaScript("JSON.stringify((function(){\(script)})())")
        guard let s = result as? String, let data = s.data(using: .utf8) else { throw FileFetchError.failed("ما قدرنا نقرأ الصفحة") }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct ForumDiscussion: Codable, Hashable, Identifiable {
    var id: String
    var subject: String
    var author: String
    var date: String
    var url: String
}

struct ForumPost: Codable, Hashable, Identifiable {
    var id: String
    var author: String
    var date: String
    var subject: String
    var text: String
    var attachments: [ForumAttachment]
}

struct ForumAttachment: Codable, Hashable, Identifiable {
    var name: String
    var url: String
    var id: String { url }
}

struct FolderFile: Codable, Hashable, Identifiable {
    var name: String
    var url: String
    var id: String { url }
}

struct AssignInfo: Codable, Hashable {
    var intro: String
    var dates: [[String]]
    var status: [[String]]
    var files: [FolderFile]
}

enum MoodleScripts {
    static let forum = """
    var seen = {}; var out = [];
    document.querySelectorAll('a[href*="discuss.php?d="]').forEach(function(a){
      var m = a.href.match(/d=(\\d+)/); if(!m || seen[m[1]]) return;
      var t = (a.textContent||'').trim(); if(!t) return;
      seen[m[1]] = 1;
      var row = a.closest('tr, [data-region="discussion-list-item"], .discussion');
      var author = '', date = '';
      if (row) {
        var au = row.querySelector('.author-info .text-truncate, [data-region="author-name"], .author a, td.author');
        author = au ? au.textContent.trim() : '';
        var tm = row.querySelector('time, td.lastpost, .lastpost');
        date = tm ? tm.textContent.trim().split('\\n')[0] : '';
      }
      out.push({id: m[1], subject: t, author: author, date: date, url: a.href});
    });
    return out;
    """

    static let discussion = """
    var out = [];
    var posts = document.querySelectorAll('[data-region="post"], article.forum-post-container, .forumpost');
    posts.forEach(function(p, i){
      var au = p.querySelector('[data-region="author-name"], .author a, header a[href*="user/view.php"]');
      var tm = p.querySelector('time');
      var sj = p.querySelector('[data-region-content="forum-post-core-subject"], h3, h4, .subject');
      var body = p.querySelector('.post-content-container, .posting, [id^="post-content"]');
      var atts = [];
      p.querySelectorAll('a[href*="pluginfile.php"]').forEach(function(a){
        var n = (a.textContent||'').trim() || decodeURIComponent(a.href.split('/').pop().split('?')[0]);
        atts.push({name: n, url: a.href});
      });
      out.push({id: p.getAttribute('data-post-id') || String(i), author: au ? au.textContent.trim() : '',
        date: tm ? tm.textContent.trim() : '', subject: sj ? sj.textContent.trim() : '',
        text: body ? body.innerText.trim() : '', attachments: atts});
    });
    return out;
    """

    static let folder = """
    var out = []; var seen = {};
    document.querySelectorAll('#region-main a[href*="pluginfile.php"], .foldertree a[href*="pluginfile.php"]').forEach(function(a){
      if (seen[a.href]) return; seen[a.href] = 1;
      var n = (a.textContent||'').trim() || decodeURIComponent(a.href.split('/').pop().split('?')[0]);
      out.push({name: n, url: a.href});
    });
    return out;
    """

    static let assign = """
    var intro = document.querySelector('.activity-description, #intro, .box.generalbox .no-overflow');
    var dates = [];
    document.querySelectorAll('[data-region="activity-dates"] div, .activity-dates div').forEach(function(d){
      var s = d.querySelector('strong'); if (!s) return;
      var label = s.textContent.replace(':','').trim(); var val = d.textContent.replace(s.textContent,'').trim();
      if (label && val) dates.push([label, val]);
    });
    var status = [];
    document.querySelectorAll('.submissionstatustable tr, table.generaltable tr').forEach(function(tr){
      var th = tr.querySelector('th'), td = tr.querySelector('td');
      if (th && td) { var v = td.innerText.trim(); if (v.length < 300) status.push([th.textContent.trim(), v]); }
    });
    var files = [];
    document.querySelectorAll('.activity-description a[href*="pluginfile.php"], #intro a[href*="pluginfile.php"], .fileuploadsubmission a[href*="pluginfile.php"]').forEach(function(a){
      files.push({name: (a.textContent||'').trim() || 'ملف', url: a.href});
    });
    return {intro: intro ? intro.innerText.trim() : '', dates: dates, status: status, files: files};
    """
}
