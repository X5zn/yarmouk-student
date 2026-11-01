import Foundation
import SwiftUI
import WidgetKit

/// Everything the app knows, saved on the phone. Screens read from here.
@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var timetable: Timetable = SharedStore.loadTimetable() { didSet { SharedStore.saveTimetable(timetable); WidgetCenter.shared.reloadAllTimelines() } }
    @Published var profile = StudentProfile() { didSet { save() } }
    @Published var planCategories: [PlanCategory] = [] { didSet { save() } }
    @Published var sisPages: [String: SISPage] = [:] { didSet { save() } }
    @Published var moodleCourses: [MoodleCourse] = [] { didSet { save() } }
    @Published var sections: [Int: [MoodleSection]] = [:] { didSet { save() } }
    @Published var deadlines: [Deadline] = [] { didSet { save() } }
    @Published var notices: [MoodleNotice] = [] { didSet { save() } }
    @Published var exams: [Exam] = [] { didSet { save() } }
    @Published var attendance: [AttendanceMark] = [] { didSet { save() } }
    @Published var notes: [CourseNote] = [] { didSet { save() } }
    @Published var settings = AppSettings() { didSet { save() } }
    @Published var moodleLinked = false { didSet { save() } }
    @Published var sisLinked = false { didSet { save() } }
    @Published var onboarded = false { didSet { save() } }
    @Published var lastMoodleSync: Date? { didSet { save() } }

    @Published var isRefreshing = false
    @Published var moodleNeedsLogin = false
    @Published var lastError: String?

    private var loading = true
    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.json")
    }()
    static var mediaDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Notes")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private struct Snapshot: Codable {
        var profile: StudentProfile
        var planCategories: [PlanCategory]
        var sisPages: [String: SISPage]
        var moodleCourses: [MoodleCourse]
        var sections: [Int: [MoodleSection]]
        var deadlines: [Deadline]
        var notices: [MoodleNotice]
        var exams: [Exam]
        var attendance: [AttendanceMark]
        var notes: [CourseNote]
        var settings: AppSettings
        var moodleLinked: Bool
        var sisLinked: Bool
        var onboarded: Bool
        var lastMoodleSync: Date?
    }

    init() {
        if let data = try? Data(contentsOf: fileURL), let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            profile = s.profile; planCategories = s.planCategories; sisPages = s.sisPages
            moodleCourses = s.moodleCourses; sections = s.sections; deadlines = s.deadlines; notices = s.notices
            exams = s.exams; attendance = s.attendance; notes = s.notes; settings = s.settings
            moodleLinked = s.moodleLinked; sisLinked = s.sisLinked; onboarded = s.onboarded; lastMoodleSync = s.lastMoodleSync
        } else {
            seed()
        }
        loading = false
    }

    /// Timetable + known exam so the app is useful before the first sync.
    private func seed() {
        // Personal details (name, number, GPA, hours) arrive from SIS / e-learning after he signs in.
        profile = StudentProfile(planTotalHours: 132)
        let cal = Calendar.yarmouk
        if let mid = cal.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 9, minute: 30)) {
            exams = [Exam(courseCode: "AR422", title: "الامتحان النصفي", date: mid,
                          notes: "محذوف: صفحات 52–72 · للقراءة فقط: 82–93")]
        }
    }

    private func save() {
        guard !loading else { return }
        let s = Snapshot(profile: profile, planCategories: planCategories, sisPages: sisPages, moodleCourses: moodleCourses,
                         sections: sections, deadlines: deadlines, notices: notices, exams: exams, attendance: attendance,
                         notes: notes, settings: settings, moodleLinked: moodleLinked, sisLinked: sisLinked,
                         onboarded: onboarded, lastMoodleSync: lastMoodleSync)
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: - Derived

    var firstName: String { profile.firstName.isEmpty ? (profile.fullName.split(separator: " ").first.map(String.init) ?? "") : profile.firstName }
    var avatarLetter: String { firstName.isEmpty ? "ط" : String(firstName.prefix(1)) }
    var greeting: String { firstName.isEmpty ? "أهلاً وسهلاً" : "أهلاً \(firstName)" }

    func course(_ code: String) -> CourseInfo? { timetable.course(code) }
    func course(moodleId: Int) -> CourseInfo? { timetable.courses.first { $0.moodleId == moodleId } }

    var todaysSlots: [LectureSlot] { timetable.slots(on: .now) }

    var pendingDeadlines: [Deadline] {
        deadlines.filter { !$0.submitted && $0.due > .now }.sorted { $0.due < $1.due }
    }
    var submittedCount: Int { deadlines.filter(\.submitted).count }

    var upcomingExams: [Exam] { exams.filter { $0.date > .now.addingTimeInterval(-3600 * 3) }.sorted { $0.date < $1.date } }

    func absences(for code: String) -> Int { attendance.filter { $0.courseCode == code && !$0.attended }.count }
    func attended(for code: String) -> Int { attendance.filter { $0.courseCode == code && $0.attended }.count }

    /// Allowed absences before حرمان for the semester (meetings/week × weeks × limit%).
    func absenceLimit(for code: String) -> Int {
        let perWeek = timetable.slots.filter { $0.courseCode == code }.count
        let total = Double(perWeek * settings.weeksInSemester)
        return max(Int((total * settings.absenceLimitPercent / 100).rounded(.down)), 1)
    }

    func attendanceRate(for code: String) -> Double? {
        let a = attended(for: code), b = absences(for: code)
        guard a + b > 0 else { return nil }
        return Double(a) / Double(a + b)
    }

    // MARK: - Actions

    func markAttendance(code: String, attended: Bool, date: Date = .now) {
        let cal = Calendar.yarmouk
        attendance.removeAll { $0.courseCode == code && cal.isDate($0.date, inSameDayAs: date) }
        attendance.append(AttendanceMark(courseCode: code, date: date, attended: attended))
        if !attended {
            let left = absenceLimit(for: code) - absences(for: code)
            if left <= 1 { NotificationManager.shared.absenceWarning(course: course(code)?.name ?? code, left: max(left, 0)) }
        }
    }

    func applySIS(_ r: SISResult) {
        var p = r.profile
        // Keep known values when a page did not show them.
        if p.fullName.isEmpty { p.fullName = profile.fullName }
        if p.firstName.isEmpty { p.firstName = p.fullName.split(separator: " ").first.map(String.init) ?? profile.firstName }
        if p.studentNumber.isEmpty { p.studentNumber = profile.studentNumber }
        if p.major.isEmpty { p.major = profile.major }
        if p.college.isEmpty { p.college = profile.college }
        if p.email.isEmpty { p.email = profile.email }
        p.gpa = p.gpa ?? profile.gpa
        p.passedHours = p.passedHours ?? profile.passedHours
        p.inProgressHours = p.inProgressHours ?? profile.inProgressHours
        p.planPercent = p.planPercent ?? profile.planPercent
        p.expectedToGraduate = p.expectedToGraduate ?? profile.expectedToGraduate
        profile = p
        sisPages.merge(r.pages) { _, new in new }
        if !r.planCategories.isEmpty { planCategories = r.planCategories }
        if !r.rooms.isEmpty {
            var t = timetable
            for i in t.slots.indices where !t.slots[i].isOnline {
                if let room = r.rooms[t.slots[i].courseCode], !room.isEmpty { t.slots[i].room = room }
            }
            timetable = t
        }
        sisLinked = true
        rescheduleEverything()
    }

    /// Pull fresh e-learning data. Returns the deadlines that are new since last time.
    @discardableResult
    func refreshMoodle(background: Bool = false) async -> [Deadline] {
        if isRefreshing { return [] }
        isRefreshing = true
        defer { isRefreshing = false }
        let client = MoodleClient.shared
        do {
            do { try await client.ensureSession() } catch MoodleError.needsLogin {
                if background { throw MoodleError.needsLogin }
                guard await client.silentReauth() else { throw MoodleError.needsLogin }
                try await client.ensureSession()
            }
            let oldIds = Set(deadlines.map(\.id))
            async let c = client.courses()
            async let d = client.deadlines(known: deadlines)
            async let n = client.notices()
            let (courses, dl, nt) = try await (c, d, n)
            if !courses.isEmpty { moodleCourses = courses }
            deadlines = dl
            notices = nt
            if let prof = try? await client.profile() {
                if !prof.fullName.isEmpty { profile.fullName = prof.fullName }
                if !prof.firstName.isEmpty { profile.firstName = prof.firstName }
                if !prof.idNumber.isEmpty { profile.studentNumber = prof.idNumber }
                if !prof.email.isEmpty { profile.email = prof.email }
            }
            moodleLinked = true
            moodleNeedsLogin = false
            lastMoodleSync = .now
            lastError = nil
            let fresh = dl.filter { !oldIds.contains($0.id) && !$0.submitted && $0.due > .now }
            if !oldIds.isEmpty, !fresh.isEmpty {
                for f in fresh { NotificationManager.shared.newAssignment(f, course: course(moodleId: f.courseId)?.name) }
            }
            rescheduleEverything()
            return fresh
        } catch MoodleError.needsLogin {
            moodleNeedsLogin = true
            return []
        } catch {
            lastError = "ما قدرنا نحدّث من الايليرنينغ هلأ"
            return []
        }
    }

    func loadSections(courseId: Int) async {
        if let s = try? await MoodleClient.shared.sections(courseId: courseId) { sections[courseId] = s }
    }

    func rescheduleEverything() {
        NotificationManager.shared.rescheduleAll(store: self)
        if settings.useAlarms { Task { await AlarmScheduler.shared.sync(store: self) } }
        LocationManager.shared.apply(enabled: settings.geofence)
        LiveActivityManager.shared.refresh(store: self)
        WidgetCenter.shared.reloadAllTimelines()
    }

    func signOut() async {
        await WebSession.shared.signOutEverything()
        Keychain.delete()
        moodleLinked = false; sisLinked = false; onboarded = false
        moodleCourses = []; deadlines = []; notices = []; sections = [:]
    }
}
