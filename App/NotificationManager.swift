import Foundation
import UserNotifications

/// All the app's local notifications. (A sideloaded app can't receive push, so everything is scheduled on the phone.)
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    let center = UNUserNotificationCenter.current()

    enum Category { static let attendance = "ATTENDANCE", lecture = "LECTURE", homework = "HOMEWORK" }
    enum Action { static let attended = "ATTENDED", absent = "ABSENT", note = "NOTE", open = "OPEN" }

    func setup() {
        center.delegate = self
        let attended = UNNotificationAction(identifier: Action.attended, title: "حضرت ✅", options: [])
        let absent = UNNotificationAction(identifier: Action.absent, title: "غبت", options: [.destructive])
        let note = UNNotificationAction(identifier: Action.note, title: "شو اخدتوا؟ 🎙️", options: [.foreground])
        let open = UNNotificationAction(identifier: Action.open, title: "افتح", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.attendance, actions: [attended, absent, note], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.lecture, actions: [open], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.homework, actions: [open], intentIdentifiers: [])
        ])
    }

    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: - Scheduling

    @MainActor
    func rescheduleAll(store: AppStore) {
        center.removeAllPendingNotificationRequests()
        let s = store.settings
        let t = store.timetable
        var requests: [UNNotificationRequest] = []

        for slot in t.slots {
            guard let course = t.course(slot.courseCode) else { continue }
            let place = slot.isOnline ? "على Teams" : (slot.room.isEmpty ? "" : "بقاعة \(slot.room)")
            let seat = slot.seat.map { " · مقعد \($0)" } ?? ""

            if s.lectureReminders && !s.useAlarms {
                let total = slot.startHour * 60 + slot.startMinute - s.lectureReminderMinutes
                let c = content(title: "\(course.name) بعد \(s.lectureReminderMinutes) دقيقة",
                                body: "الساعة \(slot.startLabel) \(place)\(seat)".trimmingCharacters(in: .whitespaces),
                                category: Category.lecture, info: ["course": course.code, "kind": "lecture"])
                requests.append(weekly("lec-\(slot.id)", c, weekday: slot.weekday, minutes: total))
            }
            if s.attendancePrompts {
                let end = slot.startHour * 60 + slot.startMinute + slot.durationMinutes
                let c = content(title: "خلصت \(course.name)", body: "حضرت المحاضرة؟ وإذا في إشي مهم سجّله «شو اخدتوا؟»",
                                category: Category.attendance, info: ["course": course.code, "kind": "attendance"])
                requests.append(weekly("att-\(slot.id)", c, weekday: slot.weekday, minutes: end))
            }
        }

        if s.morningSummary {
            for weekday in 1...7 {
                let day = t.slots(onWeekday: weekday)
                guard !day.isEmpty else { continue }
                let lines = day.compactMap { sl in t.course(sl.courseCode).map { "\(sl.startLabel) \($0.name)" } }
                let c = content(title: "صباح الخير ☀️ عندك \(day.count) محاضرات اليوم", body: lines.joined(separator: "\n"),
                                category: Category.lecture, info: ["kind": "morning"])
                requests.append(weekly("morning-\(weekday)", c, weekday: weekday, minutes: s.morningHour * 60 + s.morningMinute))
            }
        }

        let now = Date.now
        if s.homeworkReminders {
            for d in store.pendingDeadlines.prefix(8) {
                let name = store.course(moodleId: d.courseId)?.name ?? "الايليرنينغ"
                for (offset, label) in [(-86400.0, "بكرا"), (-3600.0, "بعد ساعة")] {
                    let fire = d.due.addingTimeInterval(offset)
                    guard fire > now else { continue }
                    let c = content(title: "تسليم \(d.name) \(label)", body: "\(name) · آخر موعد \(ArabicFormat.time(d.due))",
                                    category: Category.homework, info: ["kind": "homework", "url": d.url])
                    requests.append(once("hw-\(d.id)-\(Int(offset))", c, at: fire))
                }
            }
        }

        if s.examReminders {
            let cal = Calendar.yarmouk
            for e in store.upcomingExams.prefix(4) {
                let name = store.course(e.courseCode)?.name ?? e.courseCode
                for daysBefore in [7, 3, 2, 1] {
                    guard let day = cal.date(byAdding: .day, value: -daysBefore, to: e.date),
                          let fire = cal.date(bySettingHour: 19, minute: 0, second: 0, of: day), fire > now else { continue }
                    let title = daysBefore == 1 ? "امتحان \(name) بكرا 📚" : "ضايل \(daysBefore) أيام على \(e.title) \(name)"
                    let body = daysBefore == 1 ? "نام بكير، الامتحان الساعة \(ArabicFormat.time(e.date))" : "ساعة دراسة الليلة بتفرق. \(e.notes)"
                    requests.append(once("exam-\(e.id.uuidString)-\(daysBefore)", content(title: title, body: body, category: Category.lecture, info: ["kind": "exam"]), at: fire))
                }
            }
        }

        if s.weeklySummary, let thu = nextWeekday(5, hour: 21, minute: 0) {
            let weekEnd = thu.addingTimeInterval(86400 * 8)
            let hw = store.pendingDeadlines.filter { $0.due < weekEnd }.count
            let ex = store.upcomingExams.filter { $0.date < weekEnd }.count
            var body = "الأسبوع الجاي: \(store.timetable.slots.count) محاضرات"
            if hw > 0 { body += " · \(hw) واجبات" }
            if ex > 0 { body += " · \(ex) امتحانات" }
            requests.append(once("weekly", content(title: "ملخص أسبوعك 🌙", body: body, category: Category.lecture, info: ["kind": "weekly"]), at: thu))
        }

        if s.geofence {
            requests.append(contentsOf: leaveHomeRequests(store: store))
        }

        for r in requests.prefix(60) { center.add(r) }
    }

    /// «يلا اطلع» 40 min before the first in-person lecture of each day (next 7 days).
    /// Arriving on campus cancels that day's one (LocationManager).
    @MainActor
    func leaveHomeRequests(store: AppStore) -> [UNNotificationRequest] {
        let cal = Calendar.yarmouk
        var out: [UNNotificationRequest] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: .now),
                  let first = store.timetable.slots(on: day).first(where: { !$0.isOnline }),
                  let course = store.course(first.courseCode) else { continue }
            let start = store.timetable.interval(of: first, on: day).start
            let fire = start.addingTimeInterval(-40 * 60)
            guard fire > .now else { continue }
            let c = content(title: "يلا اطلع! 🏃‍♂️", body: "\(course.name) الساعة \(first.startLabel)\(first.room.isEmpty ? "" : " بقاعة \(first.room)")",
                            category: Category.lecture, info: ["kind": "leave"])
            out.append(once(Self.leaveId(for: day), c, at: fire))
        }
        return out
    }

    static func leaveId(for day: Date) -> String {
        let c = Calendar.yarmouk.dateComponents([.year, .month, .day], from: day)
        return "leave-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    // MARK: - Immediate

    func newAssignment(_ d: Deadline, course: String?) {
        let c = content(title: "نزل واجب جديد 📝 \(course ?? "")", body: "\(d.name) · آخر موعد \(ArabicFormat.shortDate(d.due)) \(ArabicFormat.time(d.due))",
                        category: Category.homework, info: ["kind": "homework", "url": d.url])
        center.add(UNNotificationRequest(identifier: "new-\(d.id)", content: c, trigger: nil))
    }

    func absenceWarning(course: String, left: Int) {
        let body = left == 0 ? "وصلت الحد المسموح للغياب. أي غياب كمان ممكن يحرمك من المادة." : "ضايلك غياب واحد بس قبل الحرمان."
        let c = content(title: "انتبه على غياباتك بـ\(course) ⚠️", body: body, category: Category.lecture, info: ["kind": "absence"])
        center.add(UNNotificationRequest(identifier: "abs-\(UUID().uuidString)", content: c, trigger: nil))
    }

    func arrivedOnCampus(next: String) {
        let c = content(title: "وصلت الجامعة 👋", body: next, category: Category.lecture, info: ["kind": "campus"])
        center.add(UNNotificationRequest(identifier: "campus-\(Int(Date().timeIntervalSince1970))", content: c, trigger: nil))
    }

    // MARK: - Helpers

    private func content(title: String, body: String, category: String, info: [String: String]) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        c.categoryIdentifier = category
        c.userInfo = info
        c.threadIdentifier = info["course"] ?? info["kind"] ?? "general"
        return c
    }

    private func weekly(_ id: String, _ c: UNNotificationContent, weekday: Int, minutes: Int) -> UNNotificationRequest {
        var m = minutes, w = weekday
        if m < 0 { m += 24 * 60; w = w == 1 ? 7 : w - 1 }
        var dc = DateComponents()
        dc.calendar = Calendar.yarmouk
        dc.timeZone = Calendar.yarmouk.timeZone
        dc.weekday = w; dc.hour = m / 60; dc.minute = m % 60
        return UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: dc, repeats: true))
    }

    private func once(_ id: String, _ c: UNNotificationContent, at date: Date) -> UNNotificationRequest {
        let dc = Calendar.yarmouk.dateComponents(in: Calendar.yarmouk.timeZone, from: date)
        var trimmed = DateComponents()
        trimmed.calendar = Calendar.yarmouk; trimmed.timeZone = Calendar.yarmouk.timeZone
        trimmed.year = dc.year; trimmed.month = dc.month; trimmed.day = dc.day; trimmed.hour = dc.hour; trimmed.minute = dc.minute
        return UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: trimmed, repeats: false))
    }

    private func nextWeekday(_ weekday: Int, hour: Int, minute: Int) -> Date? {
        var dc = DateComponents(); dc.weekday = weekday; dc.hour = hour; dc.minute = minute
        return Calendar.yarmouk.nextDate(after: .now, matching: dc, matchingPolicy: .nextTime)
    }

    // MARK: - Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let code = info["course"] as? String
        await MainActor.run {
            let store = AppStore.shared
            switch response.actionIdentifier {
            case Action.attended: if let code { store.markAttendance(code: code, attended: true) }
            case Action.absent: if let code { store.markAttendance(code: code, attended: false) }
            case Action.note: if let code { Router.shared.openNotes(for: code) }
            default:
                if let url = info["url"] as? String, let u = URL(string: url) { Router.shared.web = WebLink(url: u, title: "الايليرنينغ") }
                else if let code { Router.shared.openCourse(code) }
            }
        }
    }
}
