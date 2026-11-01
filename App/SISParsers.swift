import Foundation

// Pure parsing of SIS pages (no UI, no WebKit) so it can be tested on its own.

// MARK: - What the page extractor returns

struct SISExtract: Codable, Hashable {
    struct Table: Codable, Hashable {
        var title: String = ""
        var id: String = ""
        var headers: [String] = []
        var rows: [[String]] = []
    }
    struct Link: Codable, Hashable { var t: String; var h: String }
    struct Card: Codable, Hashable { var t: String; var x: String; var h: String }

    var title: String = ""
    var url: String = ""
    var pairs: [[String]] = []        // [label, value, section]
    var tables: [Table] = []
    var lines: [String] = []          // main content only, one visual line each
    var links: [Link] = []
    var cards: [Card] = []
    var login: Bool = false
    var error: String = ""
}

// MARK: - Models

struct AcademicSummary: Codable, Hashable {
    var cumulativeGPA: Double?
    var cumulativeHours: Int?
    var totalMarks: Int?
    var passedHours: Int?
    var honorList: String?
}

struct AcademicTerm: Codable, Hashable, Identifiable {
    var term: String              // "2025/1"
    var termGPA: Double?
    var cumulativeGPA: Double?
    var termHours: Int?
    var studiedHoursTotal: Int?
    var honorList: Bool = false
    var id: String { term }

    var year: Int { Int(term.split(separator: "/").first ?? "") ?? 0 }
    var part: Int { Int(term.split(separator: "/").last ?? "") ?? 0 }

    /// "الفصل الأول" / "الفصل الثاني" / "الفصل الصيفي"
    var semesterName: String {
        switch part {
        case 1: return "الفصل الأول"
        case 2: return "الفصل الثاني"
        case 3: return "الفصل الصيفي"
        default: return "مواد استدراكية"
        }
    }
    /// "2025/2026" for the first and second semesters, "2026" for summer.
    var academicYear: String {
        switch part {
        case 1, 2: return "\(year)/\(year + 1)"
        case 3: return "\(year + 1)"
        default: return "\(year)"
        }
    }
    var isPlaceholder: Bool { (termHours ?? 0) == 0 && (termGPA ?? 0) == 0 }
}

struct AcademicRecord: Codable, Hashable {
    var summary = AcademicSummary()
    var terms: [AcademicTerm] = []      // oldest first
    var isEmpty: Bool { terms.isEmpty && summary.cumulativeGPA == nil }
}

struct InfoRow: Codable, Hashable, Identifiable {
    var label: String
    var value: String
    var id: String { label }
}

struct InfoGroup: Codable, Hashable, Identifiable {
    var title: String
    var rows: [InfoRow]
    var id: String { title }
}

struct StudentInfo: Codable, Hashable {
    var name: String = ""
    var degree: String = ""          // "بكالوريوس / عادي"
    var department: String = ""      // "كلية الآداب / قسم اللغة العربية وآدابها"
    var groups: [InfoGroup] = []
    var isEmpty: Bool { groups.allSatisfy { $0.rows.isEmpty } }
    func value(_ label: String) -> String? {
        for g in groups { if let r = g.rows.first(where: { $0.label == label }), !r.value.isEmpty { return r.value } }
        return nil
    }
}

struct RegisteredCourse: Codable, Hashable, Identifiable {
    var code: String            // "AR 422"
    var name: String
    var section: String
    var hours: Int?
    var from: String            // "09:30"
    var to: String
    var days: [Int]             // 0 = Saturday … 6 = Friday (SIS column order)
    var room: String
    var mode: String            // وجاهي / مدمج / إلكتروني
    var instructor: String
    var cancelled: Bool
    var id: String { code + "-" + section }
    var compactCode: String { code.replacingOccurrences(of: " ", with: "") }
    static let dayNames = ["السبت", "الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة"]
    static let shortDayNames = ["سبت", "أحد", "إثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة"]
}

struct MarkCell: Codable, Hashable { var label: String; var value: String }

struct CourseMarks: Codable, Hashable, Identifiable {
    var code: String
    var name: String
    var cells: [MarkCell]       // every other column, in page order
    var main: MarkCell?         // the final mark / grade when the page has one
    var id: String { code + name }
}

struct MarksPage: Codable, Hashable {
    var term: String = ""
    var courses: [CourseMarks] = []
    var emptyMessage: String = ""
}

// MARK: - Helpers

enum SISText {
    static let footerLines: Set<String> = ["Skip to Main Content", "جامعة اليرموك - مركز الحاسب والمعلومات", "نظام معلومات الطلبة"]

    static func normalize(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "\u{00a0}", with: " ")
        // Arabic-Indic digits → Latin
        let map: [Character: Character] = ["٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9","٫":"."]
        out = String(out.map { map[$0] ?? $0 })
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanLines(_ lines: [String]) -> [String] {
        lines.flatMap { $0.components(separatedBy: CharacterSet.newlines) }
            .map(normalize)
            .filter { !$0.isEmpty && !footerLines.contains($0) }
    }

    static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > group, m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group))
    }

    static func allMatches(_ pattern: String, in text: String) -> [(range: NSRange, groups: [String])] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)).map { m in
            var g: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                g.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            return (m.range, g)
        }
    }

    static func double(_ s: String?) -> Double? {
        guard let s else { return nil }
        let n = normalize(s)
        guard let m = firstMatch(#"(\d+(?:\.\d+)?)"#, in: n) else { return nil }
        return Double(m)
    }
    static func int(_ s: String?) -> Int? {
        guard let s else { return nil }
        guard let m = firstMatch(#"(\d+)"#, in: normalize(s)) else { return nil }
        return Int(m)
    }
}

// MARK: - Academic record («السجل الأكاديمي»)

enum AcademicRecordParser {
    static let termPattern = #"(?<![\d/])(\d{4})\s*/\s*([0-4])(?![\d/])"#

    /// Works on the main-content lines, and also on the old one-line blob (whitespace collapsed).
    static func parse(lines: [String], pairs: [[String]] = []) -> AcademicRecord {
        let text = SISText.cleanLines(lines).joined(separator: "\n")
        return parse(text: text, pairs: pairs)
    }

    static func parse(text raw: String, pairs: [[String]] = []) -> AcademicRecord {
        let text = SISText.normalize(raw.replacingOccurrences(of: "\r", with: ""))
        var record = AcademicRecord()

        // Split into: [summary][term block][term block]…
        let hits = SISText.allMatches(termPattern, in: text)
        let ns = text as NSString
        let summaryEnd = hits.first?.range.location ?? ns.length
        let summaryText = ns.substring(to: summaryEnd)

        func num(_ label: String, _ src: String) -> String? {
            SISText.firstMatch(NSRegularExpression.escapedPattern(for: label) + #"\s*[:：]?\s*\(?\s*(\d+(?:\.\d+)?)"#, in: src)
        }
        var s = AcademicSummary()
        s.cumulativeGPA = SISText.double(num("المعدل التراكمي", summaryText))
        s.cumulativeHours = SISText.int(num("مجموع الساعات التراكمية", summaryText))
        s.totalMarks = SISText.int(num("مجموع العلامات التراكمية", summaryText))
        s.passedHours = SISText.int(num("مجموع الساعات التي نجح بها الطالب", summaryText))
        if let h = SISText.firstMatch(#"(?:لائحة|لوحة) الشرف\s*[:：]?\s*\(?\s*(نعم|لا)"#, in: summaryText) { s.honorList = h }
        // Pairs from the DOM win when present.
        for p in pairs where p.count >= 2 {
            let l = SISText.normalize(p[0]), v = SISText.normalize(p[1])
            if l.contains("المعدل التراكمي"), let d = SISText.double(v) { s.cumulativeGPA = d }
            if l.contains("الساعات التراكمية"), let i = SISText.int(v) { s.cumulativeHours = i }
            if l.contains("العلامات التراكمية"), let i = SISText.int(v) { s.totalMarks = i }
            if l.contains("نجح"), let i = SISText.int(v) { s.passedHours = i }
        }
        record.summary = s

        // Term blocks: a header may repeat ("2024/1\n2024/1"); merge consecutive equal headers.
        var blocks: [(term: String, start: Int)] = []
        for h in hits {
            let term = "\(h.groups[1])/\(h.groups[2])"
            if let last = blocks.last, last.term == term {
                let between = ns.substring(with: NSRange(location: last.start, length: h.range.location - last.start))
                // Same header twice with nothing but whitespace/the header itself in between → same block.
                let stripped = between.replacingOccurrences(of: term, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if stripped.isEmpty || !stripped.contains("المعدل") { continue }
            }
            blocks.append((term, h.range.location))
        }
        for (i, b) in blocks.enumerated() {
            let end = i + 1 < blocks.count ? blocks[i + 1].start : ns.length
            let body = ns.substring(with: NSRange(location: b.start, length: end - b.start))
            guard body.contains("المعدل") || body.contains("ساعات") else { continue }
            var t = AcademicTerm(term: b.term)
            t.cumulativeGPA = SISText.double(SISText.firstMatch(#"المعدل التراكمي\s*[:：]?\s*(\d+(?:\.\d+)?)"#, in: body))
            t.termGPA = SISText.double(SISText.firstMatch(#"المعدل الفصلي\s*[:：]?\s*(\d+(?:\.\d+)?)"#, in: body))
            t.termHours = SISText.int(SISText.firstMatch(#"عدد ساعات الفصل\s*[:：]?\s*(\d+)"#, in: body))
            t.studiedHoursTotal = SISText.int(SISText.firstMatch(#"مجموع الساعات التي درسها الطالب\s*[:：]?\s*\(?\s*(\d+)"#, in: body))
            t.honorList = SISText.firstMatch(#"(?:لوحة|لائحة) الشرف\s*[:：]?\s*\(?\s*(نعم)"#, in: body) != nil
            if let idx = record.terms.firstIndex(where: { $0.term == t.term }) { record.terms[idx] = t } else { record.terms.append(t) }
        }
        record.terms.sort { ($0.year, $0.part) < ($1.year, $1.part) }
        return record
    }
}

// MARK: - Student information («المعلومات الأساسية»)

enum StudentInfoParser {
    static let identity = ["الاسم بالعربية", "الاسم بالانجليزية", "الاسم بالإنجليزية", "الرقم الوطني", "الجنس", "الجنسية", "مكان الولادة", "تاريخ الولادة"]
    static let study = ["الكلية", "التخصص", "التخصص الفرعي", "التخصص الدقيق", "مسار اللغة في خطة متطلبات الجامعة الاختيارية", "الحالة الاكاديمية", "الحالة الأكاديمية", "المعدل التراكمي", "متوقع تخرجه؟"]
    static let tabs: Set<String> = ["المعلومات الرئيسية", "أوقات التسجيل", "المعلومات المالية", "معلومات خدمة العلم"]

    static func parse(pairs rawPairs: [[String]], lines rawLines: [String]) -> StudentInfo {
        var info = StudentInfo()
        let lines = SISText.cleanLines(rawLines)
        // Header: the lines before the first tab label are name / degree / college.
        let head = lines.prefix { !tabs.contains($0) && !identity.contains($0) }
        let headList = Array(head.prefix(4))
        if let n = headList.first(where: { !$0.contains("/") && !$0.contains("كلية") }) { info.name = n }
        if let d = headList.first(where: { $0.contains("بكالوريوس") || $0.contains("ماجستير") || $0.contains("دكتوراه") || $0.contains("دبلوم") }) { info.degree = d }
        if let c = headList.first(where: { $0.contains("كلية") }) { info.department = c }

        // label → value, DOM pairs first, then known labels from the lines.
        var values: [(label: String, value: String, section: String)] = []
        var seen = Set<String>()
        for p in rawPairs where p.count >= 2 {
            let l = SISText.normalize(p[0]).trimmingCharacters(in: CharacterSet(charactersIn: ":： "))
            let v = SISText.normalize(p[1])
            let sec = p.count > 2 ? SISText.normalize(p[2]) : ""
            guard !l.isEmpty, !seen.contains(l) else { continue }
            seen.insert(l); values.append((l, v, sec))
        }
        let known = identity + study
        let allLabels = Set(known).union(tabs)
        for (i, line) in lines.enumerated() where known.contains(line) && !seen.contains(line) {
            var v = ""
            if i + 1 < lines.count, !allLabels.contains(lines[i + 1]) { v = lines[i + 1] }
            seen.insert(line); values.append((line, v, ""))
        }
        // Lines like "الجنس: ذكر"
        for line in lines {
            guard let r = line.range(of: ":") else { continue }
            let l = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            let v = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            if known.contains(l), !seen.contains(l) { seen.insert(l); values.append((l, v, "")) }
        }

        func rows(_ labels: [String]) -> [InfoRow] {
            labels.compactMap { lab in values.first(where: { $0.label == lab }).map { InfoRow(label: lab, value: $0.value) } }
                .filter { !$0.value.isEmpty }
        }
        let used = Set(known)
        var groups: [InfoGroup] = [
            InfoGroup(title: "المعلومات الشخصية", rows: rows(identity)),
            InfoGroup(title: "الدراسة", rows: rows(study))
        ]
        // Everything else, grouped by its section on the page.
        var other: [String: [InfoRow]] = [:]
        var order: [String] = []
        for v in values where !used.contains(v.label) && !v.value.isEmpty && v.label.count <= 60 && v.value != v.label {
            let sec = (v.section.isEmpty || v.section == "المعلومات الرئيسية") ? "معلومات أخرى" : v.section
            if other[sec] == nil { other[sec] = []; order.append(sec) }
            other[sec]?.append(InfoRow(label: v.label, value: v.value))
        }
        for sec in order { groups.append(InfoGroup(title: sec, rows: other[sec] ?? [])) }
        info.groups = groups.filter { !$0.rows.isEmpty }
        if info.name.isEmpty, let n = info.value("الاسم بالعربية") { info.name = n }
        return info
    }
}

// MARK: - Registered courses («استطلاع المواد المسجلة»)

enum RegisteredCoursesParser {
    static func parse(tables: [SISExtract.Table]) -> [RegisteredCourse] {
        for t in tables {
            let h = t.headers.map(SISText.normalize)
            func col(_ names: [String]) -> Int? { h.firstIndex { hh in names.contains { hh == $0 } } ?? h.firstIndex { hh in names.contains { hh.contains($0) } } }
            guard let codeI = col(["رمز المساق"]), let nameI = col(["اسم المساق"]) else { continue }
            let dayCols = ["السبت", "الاحد", "الإثنين", "الثلاثاء", "الاربعاء", "الخميس", "الجمعة"].map { d -> Int? in
                h.firstIndex { hh in hh == d || hh.replacingOccurrences(of: "أ", with: "ا").replacingOccurrences(of: "إ", with: "ا") == d.replacingOccurrences(of: "إ", with: "ا") }
            }
            let secI = col(["الشعبة"]), hrsI = col(["عدد الساعات"]), fromI = col(["من"]), toI = col(["الى", "إلى"])
            let roomI = col(["القاعة"]), modeI = col(["طريقة تدريس"]), insI = col(["المدرس"]), cancI = col(["الشعبة ملغاة"])
            var out: [RegisteredCourse] = []
            for row in t.rows {
                func cell(_ i: Int?) -> String { guard let i, i < row.count else { return "" }; return SISText.normalize(row[i]) }
                let code = cell(codeI)
                guard !code.isEmpty, code.rangeOfCharacter(from: .letters) != nil else { continue }
                var days: [Int] = []
                for (d, ci) in dayCols.enumerated() {
                    let v = cell(ci)
                    if !v.isEmpty && v != "-" { days.append(d) }
                }
                out.append(RegisteredCourse(code: code, name: cell(nameI), section: cell(secI), hours: SISText.int(cell(hrsI)),
                                            from: cell(fromI), to: cell(toI), days: days, room: cell(roomI),
                                            mode: cell(modeI), instructor: cell(insI), cancelled: cell(cancI) == "نعم"))
            }
            if !out.isEmpty { return out }
        }
        return []
    }
}

// MARK: - Marks («إستطلاع العلامات»)

enum MarksParser {
    static let mainHeaders = ["العلامة النهائية", "المجموع", "العلامة", "علامة", "التقدير", "النتيجة"]

    static func parse(tables: [SISExtract.Table], lines: [String]) -> MarksPage {
        var page = MarksPage()
        let clean = SISText.cleanLines(lines)
        if let t = clean.first(where: { $0.range(of: #"(الاول|الأول|الثاني|الصيفي)\s+\d{4}"#, options: .regularExpression) != nil && $0.count < 25 }) {
            page.term = t
        }
        for t in tables {
            let h = t.headers.map(SISText.normalize)
            guard !h.isEmpty else { continue }
            let codeI = h.firstIndex { $0.contains("رمز") }
            let nameI = h.firstIndex { $0.contains("اسم المساق") || $0 == "المساق" || $0.contains("اسم المادة") }
            guard codeI != nil || nameI != nil else { continue }
            for row in t.rows {
                func cell(_ i: Int?) -> String { guard let i, i < row.count else { return "" }; return SISText.normalize(row[i]) }
                let code = cell(codeI), name = cell(nameI)
                guard !(code.isEmpty && name.isEmpty) else { continue }
                var cells: [MarkCell] = []
                for (i, v) in row.enumerated() where i != codeI && i != nameI && i < h.count {
                    let value = SISText.normalize(v)
                    let label = h[i]
                    if label.isEmpty || value.isEmpty { continue }
                    cells.append(MarkCell(label: label, value: value))
                }
                var main: MarkCell?
                for key in mainHeaders { if let c = cells.last(where: { $0.label.contains(key) }) { main = c; break } }
                page.courses.append(CourseMarks(code: code, name: name, cells: cells, main: main))
            }
            if !page.courses.isEmpty { break }
        }
        if page.courses.isEmpty {
            page.emptyMessage = clean.first(where: { $0.contains("لا يوجد") || $0.contains("لا توجد") || $0.lowercased().contains("no data") }) ?? ""
        }
        return page
    }
}

// MARK: - Home («نسبة إنجازك»), student number

enum SISHomeParser {
    static func planPercent(lines: [String]) -> Int? {
        let l = SISText.cleanLines(lines)
        guard let i = l.firstIndex(where: { $0.contains("نسبة إنجازك") || $0.contains("نسبة انجازك") }) else { return nil }
        for j in i..<min(i + 4, l.count) {
            if let n = SISText.firstMatch(#"^%?\s*(\d{1,3})\s*%?$"#, in: l[j]) ?? (j == i ? SISText.firstMatch(#"(\d{1,3})\s*%"#, in: l[j]) : nil),
               let v = Int(n), v <= 100 { return v }
        }
        return nil
    }
    static func studentNumber(in text: String) -> String? {
        SISText.firstMatch(#"(?<!\d)(20\d{8})(?!\d)"#, in: SISText.normalize(text))
    }
}

// MARK: - Masking for the developer export

enum SISMask {
    /// Hides names, national/student numbers, birth data and session ids in a saved page.
    static func mask(_ html: String, secrets: [String]) -> String {
        var out = html
        var words = Set<String>()
        for s in secrets {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2 else { continue }
            words.insert(t)
            if t.rangeOfCharacter(from: .decimalDigits) == nil {
                for part in t.split(separator: " ") where part.count >= 3 { words.insert(String(part)) }
            }
        }
        for w in words.sorted(by: { $0.count > $1.count }) {
            out = out.replacingOccurrences(of: w, with: "•••")
        }
        let rules: [(String, String)] = [
            (#"(?<!\d)\d{10}(?!\d)"#, "••••••••••"),                 // national id / student number
            (#"session=\d+"#, "session=0"),
            (#"(P9999_PASSWORD[^>]*value=")[^"]*""#, "$1\""),
        ]
        for (p, r) in rules {
            if let re = try? NSRegularExpression(pattern: p) {
                out = re.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length), withTemplate: r)
            }
        }
        return out
    }
}
