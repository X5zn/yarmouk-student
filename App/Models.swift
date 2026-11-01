import Foundation

// MARK: - Student profile (from SIS + Moodle)

struct StudentProfile: Codable, Hashable {
    var fullName: String = ""
    var firstName: String = ""
    var studentNumber: String = ""
    var major: String = ""
    var college: String = ""
    var email: String = ""
    var gpa: Double? = nil
    var passedHours: Int? = nil
    var inProgressHours: Int? = nil
    var planTotalHours: Int = 132
    var planPercent: Int? = nil
    var expectedToGraduate: String? = nil
    var updatedAt: Date? = nil

    var remainingHours: Int? {
        guard let passedHours else { return nil }
        return max(planTotalHours - passedHours, 0)
    }

    /// Rough estimate: remaining hours after this term at 15 h per regular semester.
    var graduationEstimate: String? {
        guard let passed = passedHours else { return nil }
        let afterThisTerm = max(planTotalHours - passed - (inProgressHours ?? 0), 0)
        if afterThisTerm == 0 { return "نهاية هذا الفصل" }
        let semesters = Int((Double(afterThisTerm) / 15.0).rounded(.up))
        // Current term = first semester (Sep–Jan). Count regular semesters forward.
        let cal = Calendar.yarmouk
        let now = Date.now
        var year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        var isFirst = month >= 9 || month <= 1
        if month < 9 { year -= 1 }
        for _ in 0..<semesters {
            if isFirst { isFirst = false } else { isFirst = true; year += 1 }
        }
        let label = isFirst ? "الفصل الأول \(year)/\(year + 1)" : "الفصل الثاني \(year)/\(year + 1)"
        return label
    }
}

struct PlanCategory: Codable, Hashable, Identifiable {
    var title: String
    var required: Int?
    var completed: Int?
    var detail: String
    var id: String { title }
}

/// A generic SIS page turned into native data (tables + label/value pairs).
struct SISPage: Codable, Hashable {
    var key: String
    var title: String
    var url: String
    var pairs: [[String]]
    var tables: [SISTable]
    var text: String
    var fetchedAt: Date
}

struct SISTable: Codable, Hashable, Identifiable {
    var headers: [String]
    var rows: [[String]]
    var id: String { headers.joined(separator: "|") + "\(rows.count)" }
}

// MARK: - Moodle

struct MoodleCourse: Codable, Hashable, Identifiable {
    var id: Int
    var fullName: String
    var shortName: String
    var progress: Double?
}

struct MoodleSection: Codable, Hashable, Identifiable {
    var id: String
    var number: Int
    var title: String
    var modules: [MoodleModule]
}

struct MoodleModule: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: String       // resource, folder, url, assign, forum, quiz, page, label
    var url: String?

    var symbol: String {
        switch kind {
        case "resource": return "doc.text"
        case "folder": return "folder"
        case "url": return "link"
        case "assign": return "square.and.pencil"
        case "quiz": return "checklist"
        case "forum": return "megaphone"
        case "page": return "doc.plaintext"
        case "label": return "text.alignright"
        default: return "square.grid.2x2"
        }
    }
    var kindLabel: String {
        switch kind {
        case "resource": return "ملف"
        case "folder": return "مجلد"
        case "url": return "رابط"
        case "assign": return "واجب"
        case "quiz": return "كويز"
        case "forum": return "إعلانات ونقاش"
        case "page": return "صفحة"
        default: return ""
        }
    }
}

struct Deadline: Codable, Hashable, Identifiable {
    var id: Int
    var name: String
    var courseId: Int
    var due: Date
    var url: String
    var kind: String        // assign / quiz
    var submitted: Bool     // Moodle no longer lists it as an action → done
    var firstSeen: Date
}

struct MoodleNotice: Codable, Hashable, Identifiable {
    var id: Int
    var subject: String
    var text: String
    var url: String?
    var date: Date
    var read: Bool
}

// MARK: - Things he keeps himself

struct Exam: Codable, Hashable, Identifiable {
    var id = UUID()
    var courseCode: String
    var title: String        // "نصفي"
    var date: Date
    var notes: String = ""
}

struct AttendanceMark: Codable, Hashable, Identifiable {
    var id = UUID()
    var courseCode: String
    var date: Date
    var attended: Bool
}

struct CourseNote: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case text, audio, photo }
    var id = UUID()
    var courseCode: String
    var kind: Kind
    var text: String = ""
    var fileName: String? = nil
    var date: Date = .now
}

struct AppSettings: Codable, Hashable {
    var lectureReminderMinutes: Int = 15
    var lectureReminders = true
    var useAlarms = false
    var morningSummary = true
    var morningHour = 7
    var morningMinute = 30
    var attendancePrompts = true
    var homeworkReminders = true
    var examReminders = true
    var weeklySummary = true
    var geofence = false
    var liveActivity = true
    var absenceLimitPercent: Double = 15
    var weeksInSemester = 16
}
