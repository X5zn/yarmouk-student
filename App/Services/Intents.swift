import AppIntents
import Foundation

/// «يا سيري، شو عندي بكرا بجامعة اليرموك؟»
struct TomorrowScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "شو عندي بكرا"
    static var description = IntentDescription("محاضراتك بكرا وأقرب واجب")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        let cal = Calendar.yarmouk
        let tomorrow = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        let slots = store.timetable.slots(on: tomorrow)
        var text: String
        if slots.isEmpty {
            text = "بكرا ما عندك محاضرات."
        } else {
            let list = slots.compactMap { s in store.course(s.courseCode).map { "\($0.name) الساعة \(s.startLabel)" } }
            text = "بكرا عندك \(slots.count): " + list.joined(separator: "، ") + "."
        }
        let dueSoon = store.pendingDeadlines.filter { $0.due < tomorrow.addingTimeInterval(86400 * 2) }
        if let d = dueSoon.first { text += " وانتبه، تسليم \(d.name) \(ArabicFormat.relative(d.due))." }
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct NextLectureIntent: AppIntent {
    static var title: LocalizedStringResource = "المحاضرة الجاية"
    static var description = IntentDescription("شو محاضرتك الجاية ووين")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = AppStore.shared
        guard let next = store.timetable.nextLecture(), let c = store.course(next.slot.courseCode) else {
            return .result(dialog: "ما في محاضرات قريبة.")
        }
        var text = "\(c.name) \(ArabicFormat.relative(next.interval.start))، الساعة \(next.slot.startLabel)"
        if next.slot.isOnline { text += " على Teams" } else if !next.slot.room.isEmpty { text += " بقاعة \(next.slot.room)" }
        if let seat = next.slot.seat { text += "، مقعدك \(seat)" }
        return .result(dialog: IntentDialog(stringLiteral: text + "."))
    }
}

struct YarmoukShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TomorrowScheduleIntent(),
                    phrases: ["شو عندي بكرا في \(.applicationName)", "جدول بكرا في \(.applicationName)"],
                    shortTitle: "شو عندي بكرا", systemImageName: "calendar")
        AppShortcut(intent: NextLectureIntent(),
                    phrases: ["المحاضرة الجاية في \(.applicationName)"],
                    shortTitle: "المحاضرة الجاية", systemImageName: "clock")
    }
}
