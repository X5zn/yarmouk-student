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
    @Published var sis = SISData.load() { didSet { if !loading { sis.save() } } }
    @Published var sisNeedsLogin = false
    @Published var sisRefreshing = false
    private var backgroundSIS: SISSync?
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
        if let reg = sis.registered, !reg.isEmpty { syncTimetable(with: reg) }
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
        var merged = sis
        merged.merge(r.data)
        sis = merged
        SISDebugStore.save(r)
        sisNeedsLogin = false
        if !r.planCategories.isEmpty { planCategories = r.planCategories }
        if let reg = sis.registered, !reg.isEmpty {
            syncTimetable(with: reg)
        } else if !r.rooms.isEmpty {
            var t = timetable
            for i in t.slots.indices where !t.slots[i].isOnline {
                if let room = r.rooms[t.slots[i].courseCode], !room.isEmpty { t.slots[i].room = room }
            }
            timetable = t
        }
        sisLinked = true
        rescheduleEverything()
    }


    // MARK: - Timetable from SIS («استطلاع المواد المسجلة»)

    static let coursePalette = ["#006B3F", "#E07A1F", "#5B4BC4", "#1D74D8", "#0E8C8C", "#C2410C", "#B4236B", "#4D7C0F"]

    /// "09:30" / "4:30" / "16:30" → (hour, minute) on a 24h clock (university hours 8:00–19:00).
    static func clock(_ s: String) -> (Int, Int)? {
        let digits = s.replacingOccurrences(of: ".", with: ":").split(separator: ":").map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard digits.count >= 2, var h = digits[0], let m = digits[1] else { return nil }
        if h < 7 { h += 12 }
        return (h, m)
    }

    /// His real registered courses become the timetable: days, times, rooms, instructors.
    /// Seats and colours he already has are kept; e-learning ids are matched by course code.
    func syncTimetable(with reg: [RegisteredCourse]) {
        let old = timetable
        var courses: [CourseInfo] = []
        var slots: [LectureSlot] = []
        for (i, rc) in reg.enumerated() where !rc.cancelled {
            let code = rc.compactCode
            let prev = old.course(code)
            var moodle: Int? = prev?.moodleId
            if moodle == nil {
                for mc in moodleCourses {
                    let s = (mc.shortName + " " + mc.fullName).replacingOccurrences(of: " ", with: "")
                    if s.localizedCaseInsensitiveContains(code) { moodle = mc.id; break }
                }
            }
            if !courses.contains(where: { $0.code == code }) {
                courses.append(CourseInfo(code: code, name: rc.name.isEmpty ? (prev?.name ?? code) : rc.name,
                                          instructor: rc.instructor.isEmpty ? (prev?.instructor ?? "") : rc.instructor,
                                          moodleId: moodle, creditHours: rc.hours ?? prev?.creditHours ?? 3,
                                          colorHex: prev?.colorHex ?? Self.coursePalette[i % Self.coursePalette.count]))
            }
            guard let start = Self.clock(rc.from) else { continue }
            let h = start.0, m = start.1
            var duration = 60
            if let end = Self.clock(rc.to) { duration = max((end.0 * 60 + end.1) - (h * 60 + m), 30) }
            let online = rc.mode.contains("إلكتروني") || rc.mode.contains("الكتروني") || rc.mode.contains("عن بعد")
            let room = online && rc.room.isEmpty ? "Teams" : rc.room
            for d in rc.days {
                let weekday = d == 0 ? 7 : d          // SIS: 0 = Saturday … 6 = Friday
                let seat = old.slots.first { $0.courseCode == code && $0.weekday == weekday }?.seat
                    ?? old.slots.first { $0.courseCode == code }?.seat
                slots.append(LectureSlot(courseCode: code, weekday: weekday, startHour: h, startMinute: m,
                                         durationMinutes: duration, room: room, seat: seat))
            }
        }
        guard !courses.isEmpty else { return }
        let t = Timetable(courses: courses, slots: slots)
        if t != timetable { timetable = t }
    }

    /// Refresh SIS in the background with the saved session (no login screen).
    /// Returns false when SIS wants a new login; cached data stays on screen either way.
    @discardableResult
    func refreshSIS() async -> Bool {
        if sisRefreshing { return true }
        guard let s = SISSync.savedSession, !s.isEmpty else { sisNeedsLogin = sisLinked; return false }
        sisRefreshing = true
        defer { sisRefreshing = false; backgroundSIS = nil }
        let ok: Bool = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let sync = SISSync(interactive: false)
            backgroundSIS = sync
            let once = ResumeOnce(c)
            sync.onFinished = { [weak self] result in
                self?.applySIS(result)
                once.resume(true)
            }
            sync.onNeedsLogin = { once.resume(false) }
            sync.start()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(90))
                once.resume(false)
            }
        }
        if !ok { sisNeedsLogin = SISSync.savedSession == nil }
        return ok
    }

    /// When the app comes to the front: refresh SIS quietly if the data is older than 20 minutes.
    func refreshSISIfStale() async {
        guard sisLinked else { return }
        if let d = sis.updatedAt, Date.now.timeIntervalSince(d) < 20 * 60 { return }
        await refreshSIS()
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
            if !courses.isEmpty {
                moodleCourses = courses
                if let reg = sis.registered, !reg.isEmpty { syncTimetable(with: reg) }
            }
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

    enum LoadResult { case ok, needsLogin, failed }
    @Published var fileKinds: [String: MoodleFileKind] = [:]

    /// Course content (sections, files, links). Renews the session silently once if it expired.
    @discardableResult
    func loadSections(courseId: Int) async -> LoadResult {
        let client = MoodleClient.shared
        do {
            let s = try await client.sections(courseId: courseId)
            sections[courseId] = s
            moodleNeedsLogin = false
        } catch MoodleError.needsLogin {
            guard await client.silentReauth(), let s = try? await client.sections(courseId: courseId) else {
                moodleNeedsLogin = true
                return .needsLogin
            }
            sections[courseId] = s
        } catch {
            return .failed
        }
        let kinds = await client.fileKinds(courseId: courseId)
        if !kinds.isEmpty { fileKinds.merge(kinds) { _, n in n } }
        return .ok
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
        SISSync.savedSession = nil
        sis = SISData(); sisNeedsLogin = false
        try? FileManager.default.removeItem(at: SISDebugStore.dir)
        moodleLinked = false; sisLinked = false; onboarded = false
        moodleCourses = []; deadlines = []; notices = []; sections = [:]
    }
}

/// Resumes a continuation exactly once (finish, needs-login or timeout — whichever comes first).
final class ResumeOnce: @unchecked Sendable {
    private var c: CheckedContinuation<Bool, Never>?
    init(_ c: CheckedContinuation<Bool, Never>) { self.c = c }
    func resume(_ v: Bool) { c?.resume(returning: v); c = nil }
}
