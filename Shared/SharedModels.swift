import Foundation
import SwiftUI
#if canImport(ActivityKit)
import ActivityKit
#endif

// MARK: - App group

enum AppGroup {
    static let id = "group.com.baihas.yarmoukstudent"
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return url }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Brand

enum Brand {
    static let green = Color(red: 0/255, green: 107/255, blue: 63/255)        // #006b3f
    static let greenDark = Color(red: 0/255, green: 84/255, blue: 50/255)
    static let gold = Color(red: 201/255, green: 162/255, blue: 39/255)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

// MARK: - Courses & timetable

struct CourseInfo: Codable, Hashable, Identifiable {
    var code: String          // "AR422"
    var name: String          // "الشعر العربي الحديث"
    var instructor: String
    var moodleId: Int?
    var creditHours: Int
    var colorHex: String
    var id: String { code }

    var color: Color { Color(hex: colorHex) }
    var moodleURL: URL? {
        guard let moodleId else { return nil }
        return URL(string: "https://elearning.yu.edu.jo/course/view.php?id=\(moodleId)")
    }
}

/// One weekly meeting. weekday uses Calendar numbering: 1 = Sunday … 7 = Saturday.
struct LectureSlot: Codable, Hashable, Identifiable {
    var courseCode: String
    var weekday: Int
    var startHour: Int
    var startMinute: Int
    var durationMinutes: Int
    var room: String          // "اد 253" or "Teams"
    var seat: String?         // "44"
    var id: String { "\(courseCode)-\(weekday)-\(startHour)\(startMinute)" }

    var isOnline: Bool { room.lowercased().contains("teams") }
    var startLabel: String { Self.timeLabel(startHour, startMinute) }
    var endLabel: String {
        let total = startHour * 60 + startMinute + durationMinutes
        return Self.timeLabel(total / 60, total % 60)
    }
    static func timeLabel(_ h: Int, _ m: Int) -> String {
        let h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h)
        return String(format: "%d:%02d", h12, m)
    }
}

struct Timetable: Codable, Hashable {
    var courses: [CourseInfo]
    var slots: [LectureSlot]

    func course(_ code: String) -> CourseInfo? { courses.first { $0.code == code } }

    func slots(onWeekday weekday: Int) -> [LectureSlot] {
        slots.filter { $0.weekday == weekday }.sorted { ($0.startHour, $0.startMinute) < ($1.startHour, $1.startMinute) }
    }

    func slots(on date: Date, calendar: Calendar = .yarmouk) -> [LectureSlot] {
        slots(onWeekday: calendar.component(.weekday, from: date))
    }

    /// Concrete start/end for a slot on a given day.
    func interval(of slot: LectureSlot, on date: Date, calendar: Calendar = .yarmouk) -> DateInterval {
        let start = calendar.date(bySettingHour: slot.startHour, minute: slot.startMinute, second: 0, of: date) ?? date
        return DateInterval(start: start, duration: TimeInterval(slot.durationMinutes * 60))
    }

    /// Next lecture that has not ended yet (searching up to 8 days ahead).
    func nextLecture(after now: Date = .now, calendar: Calendar = .yarmouk) -> (slot: LectureSlot, interval: DateInterval)? {
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            for slot in slots(on: day, calendar: calendar) {
                let iv = interval(of: slot, on: day, calendar: calendar)
                if iv.end > now { return (slot, iv) }
            }
        }
        return nil
    }

    static let seed = Timetable(
        courses: [
            CourseInfo(code: "AR422", name: "الشعر العربي الحديث", instructor: "د. سمية الشوابكة", moodleId: 2347, creditHours: 3, colorHex: "#006B3F"),
            CourseInfo(code: "HUM128", name: "المدخل إلى علم الاجتماع", instructor: "د. محمد الحراحشة", moodleId: 2805, creditHours: 3, colorHex: "#E07A1F"),
            CourseInfo(code: "AR241", name: "العروض والإيقاع الشعري", instructor: "د. عمر العامري", moodleId: 2476, creditHours: 3, colorHex: "#5B4BC4"),
            CourseInfo(code: "SCI108", name: "مهارات حاسوب", instructor: "د. عبير البطاينه", moodleId: 3760, creditHours: 3, colorHex: "#1D74D8"),
            CourseInfo(code: "SA100", name: "الأخلاقيات والعمل التطوعي", instructor: "", moodleId: 3678, creditHours: 0, colorHex: "#0E8C8C")
        ],
        slots: [
            // الشعر العربي الحديث — أحد/ثلاثاء/خميس 9:30
            LectureSlot(courseCode: "AR422", weekday: 1, startHour: 9, startMinute: 30, durationMinutes: 60, room: "اد 253", seat: nil),
            LectureSlot(courseCode: "AR422", weekday: 3, startHour: 9, startMinute: 30, durationMinutes: 60, room: "اد 253", seat: nil),
            LectureSlot(courseCode: "AR422", weekday: 5, startHour: 9, startMinute: 30, durationMinutes: 60, room: "اد 253", seat: nil),
            // علم الاجتماع — أحد/ثلاثاء 10:30 (الخميس مدمج)
            LectureSlot(courseCode: "HUM128", weekday: 1, startHour: 10, startMinute: 30, durationMinutes: 60, room: "", seat: nil),
            LectureSlot(courseCode: "HUM128", weekday: 3, startHour: 10, startMinute: 30, durationMinutes: 60, room: "", seat: nil),
            // العروض والإيقاع — أحد/ثلاثاء/خميس 12:30، مقعد 44
            LectureSlot(courseCode: "AR241", weekday: 1, startHour: 12, startMinute: 30, durationMinutes: 60, room: "", seat: "44"),
            LectureSlot(courseCode: "AR241", weekday: 3, startHour: 12, startMinute: 30, durationMinutes: 60, room: "", seat: "44"),
            LectureSlot(courseCode: "AR241", weekday: 5, startHour: 12, startMinute: 30, durationMinutes: 60, room: "", seat: "44"),
            // مهارات حاسوب — أحد/ثلاثاء 4:30 على Teams
            LectureSlot(courseCode: "SCI108", weekday: 1, startHour: 16, startMinute: 30, durationMinutes: 60, room: "Teams", seat: nil),
            LectureSlot(courseCode: "SCI108", weekday: 3, startHour: 16, startMinute: 30, durationMinutes: 60, room: "Teams", seat: nil)
        ]
    )
}

extension Calendar {
    static var yarmouk: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Amman") ?? .current
        c.locale = Locale(identifier: "ar_JO")
        return c
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Shared store (app <-> widgets)

enum SharedStore {
    private static let timetableKey = "timetable.v1"

    static func loadTimetable() -> Timetable {
        if let data = AppGroup.defaults.data(forKey: timetableKey),
           let t = try? JSONDecoder().decode(Timetable.self, from: data) { return t }
        return .seed
    }

    static func saveTimetable(_ t: Timetable) {
        if let data = try? JSONEncoder().encode(t) { AppGroup.defaults.set(data, forKey: timetableKey) }
    }
}

// MARK: - Arabic formatting helpers

enum ArabicFormat {
    static let dayNames = [1: "الأحد", 2: "الاثنين", 3: "الثلاثاء", 4: "الأربعاء", 5: "الخميس", 6: "الجمعة", 7: "السبت"]

    static func dayName(_ weekday: Int) -> String { dayNames[weekday] ?? "" }

    static func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ar_JO")
        f.timeZone = Calendar.yarmouk.timeZone
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let c = Calendar.yarmouk.dateComponents([.hour, .minute], from: date)
        return LectureSlot.timeLabel(c.hour ?? 0, c.minute ?? 0)
    }

    static func relative(_ date: Date, from now: Date = .now) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ar")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: now)
    }

    static func daysLeft(to date: Date, from now: Date = .now) -> Int {
        let cal = Calendar.yarmouk
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }
}

// MARK: - Live Activity

#if canImport(ActivityKit)
struct LectureActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var courseName: String
        var room: String
        var seat: String?
        var start: Date
        var end: Date
    }
    var courseCode: String
    var colorHex: String
}
#endif
