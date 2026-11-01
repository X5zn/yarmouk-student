import Foundation
import SwiftUI
#if canImport(AlarmKit) && ALARMKIT
import AlarmKit
import ActivityKit

struct LectureAlarmMetadata: AlarmMetadata {}

/// Real alarms before lectures (ring through silent mode). iOS 26+ AlarmKit.
@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()
    private let idsKey = "alarm.ids"

    func requestAccess() async -> Bool {
        do {
            let state = try await AlarmManager.shared.requestAuthorization()
            return state == .authorized
        } catch { return false }
    }

    func cancelAll() async {
        let ids = (UserDefaults.standard.stringArray(forKey: idsKey) ?? []).compactMap(UUID.init(uuidString:))
        for id in ids { try? AlarmManager.shared.cancel(id: id) }
        UserDefaults.standard.set([String](), forKey: idsKey)
    }

    func sync(store: AppStore) async {
        await cancelAll()
        guard store.settings.useAlarms, AlarmManager.shared.authorizationState == .authorized else { return }
        var saved: [String] = []
        // One weekly alarm per lecture time.
        for slot in store.timetable.slots {
            guard let course = store.course(slot.courseCode) else { continue }
            var total = slot.startHour * 60 + slot.startMinute - store.settings.lectureReminderMinutes
            var weekday = slot.weekday
            if total < 0 { total += 1440; weekday = weekday == 1 ? 7 : weekday - 1 }
            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: "\(course.name) بعد \(store.settings.lectureReminderMinutes) دقيقة"),
                stopButton: AlarmButton(text: "تمام", textColor: .white, systemImageName: "checkmark"),
                secondaryButton: nil,
                secondaryButtonBehavior: nil)
            let attrs = AlarmAttributes<LectureAlarmMetadata>(presentation: AlarmPresentation(alert: alert, countdown: nil, paused: nil),
                                                              metadata: LectureAlarmMetadata(), tintColor: course.color)
            let schedule = Alarm.Schedule.relative(.init(time: .init(hour: total / 60, minute: total % 60),
                                                         repeats: .weekly([Self.localeWeekday(weekday)])))
            let config = AlarmManager.AlarmConfiguration<LectureAlarmMetadata>.alarm(
                schedule: schedule, attributes: attrs, stopIntent: nil, secondaryIntent: nil, sound: .default)
            let id = UUID()
            if (try? await AlarmManager.shared.schedule(id: id, configuration: config)) != nil { saved.append(id.uuidString) }
        }
        UserDefaults.standard.set(saved, forKey: idsKey)
    }

    static func localeWeekday(_ w: Int) -> Locale.Weekday {
        switch w {
        case 1: return .sunday
        case 2: return .monday
        case 3: return .tuesday
        case 4: return .wednesday
        case 5: return .thursday
        case 6: return .friday
        default: return .saturday
        }
    }
}
#else
/// Build without AlarmKit: lecture reminders stay as normal notifications.
@MainActor
final class AlarmScheduler {
    static let shared = AlarmScheduler()
    func requestAccess() async -> Bool { false }
    func cancelAll() async {}
    func sync(store: AppStore) async {}
}
#endif
