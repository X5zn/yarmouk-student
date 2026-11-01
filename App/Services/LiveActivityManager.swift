import Foundation
import ActivityKit

/// Countdown to the next lecture on the Dynamic Island + lock screen. Started on the phone, no server.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// Auto: when the app opens within 3 h of a lecture, show its countdown (if enabled).
    func refresh(store: AppStore) {
        endFinished()
        guard store.settings.liveActivity, ActivityAuthorizationInfo().areActivitiesEnabled,
              let next = store.timetable.nextLecture(), let course = store.course(next.slot.courseCode) else { return }
        let soon = next.interval.start.timeIntervalSinceNow < 3 * 3600
        let running = Activity<LectureActivityAttributes>.activities.contains {
            $0.content.state.start == next.interval.start && $0.activityState == .active
        }
        if soon && !running { start(slot: next.slot, interval: next.interval, course: course) }
    }

    func start(slot: LectureSlot, interval: DateInterval, course: CourseInfo) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        for a in Activity<LectureActivityAttributes>.activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        let state = LectureActivityAttributes.ContentState(courseName: course.name,
                                                            room: slot.isOnline ? "Teams" : slot.room,
                                                            seat: slot.seat, start: interval.start, end: interval.end)
        let attrs = LectureActivityAttributes(courseCode: course.code, colorHex: course.colorHex)
        let content = ActivityContent(state: state, staleDate: interval.end, relevanceScore: 100)
        _ = try? Activity.request(attributes: attrs, content: content, pushType: nil)
    }

    private func endFinished() {
        for a in Activity<LectureActivityAttributes>.activities where a.content.state.end < .now {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
