import WidgetKit
import SwiftUI
import ActivityKit

@main
struct YarmoukWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NextLectureWidget()
        VerseWidget()
        LectureLiveActivity()
    }
}

// MARK: - Next lecture

struct LectureEntry: TimelineEntry {
    let date: Date
    let course: CourseInfo?
    let slot: LectureSlot?
    let start: Date?
}

struct LectureProvider: TimelineProvider {
    func placeholder(in context: Context) -> LectureEntry {
        let t = Timetable.seed
        return LectureEntry(date: .now, course: t.courses.first, slot: t.slots.first, start: .now.addingTimeInterval(1800))
    }

    func getSnapshot(in context: Context, completion: @escaping (LectureEntry) -> Void) {
        completion(entry(at: .now, timetable: SharedStore.loadTimetable()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LectureEntry>) -> Void) {
        let t = SharedStore.loadTimetable()
        var entries: [LectureEntry] = [entry(at: .now, timetable: t)]
        // A new entry at the end of each upcoming lecture (next 2 days) so it moves on by itself.
        var cursor = Date.now
        for _ in 0..<8 {
            guard let next = t.nextLecture(after: cursor) else { break }
            cursor = next.interval.end.addingTimeInterval(1)
            entries.append(entry(at: cursor, timetable: t))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date, timetable t: Timetable) -> LectureEntry {
        guard let next = t.nextLecture(after: date) else { return LectureEntry(date: date, course: nil, slot: nil, start: nil) }
        return LectureEntry(date: date, course: t.course(next.slot.courseCode), slot: next.slot, start: next.interval.start)
    }
}

struct NextLectureView: View {
    @Environment(\.widgetFamily) var family
    let entry: LectureEntry

    var place: String {
        guard let s = entry.slot else { return "" }
        var p = s.isOnline ? "Teams" : s.room
        if let seat = s.seat { p += p.isEmpty ? "مقعد \(seat)" : " · مقعد \(seat)" }
        return p
    }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.course?.name ?? "ما في محاضرات").font(.headline).lineLimit(1)
                if let s = entry.slot, let start = entry.start {
                    Text("\(s.startLabel) · \(place)").font(.caption).lineLimit(1)
                    Text(start, style: .relative).font(.caption2)
                }
            }
        case .accessoryInline:
            Text(entry.course.map { "\($0.name) \(entry.slot?.startLabel ?? "")" } ?? "ما في محاضرات")
        default:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: "graduationcap.fill")
                    Text("المحاضرة الجاية")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.green)
                Spacer(minLength: 0)
                if let c = entry.course, let s = entry.slot, let start = entry.start {
                    Text(c.name).font(.headline).lineLimit(2)
                    Text(s.startLabel).font(.system(size: 26, weight: .bold, design: .rounded))
                    if !place.isEmpty { Text(place).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    Text(start, style: .relative).font(.caption2.weight(.semibold)).foregroundStyle(Brand.green)
                } else {
                    Text("ما في محاضرات قريبة").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct NextLectureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextLecture", provider: LectureProvider()) { entry in
            NextLectureView(entry: entry)
                .environment(\.layoutDirection, .rightToLeft)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("المحاضرة الجاية")
        .description("المادة والوقت والقاعة ومقعدك")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - بيت اليوم

struct VerseEntry: TimelineEntry { let date: Date; let verse: Verse }

struct VerseProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerseEntry { VerseEntry(date: .now, verse: Poetry.verses[0]) }
    func getSnapshot(in context: Context, completion: @escaping (VerseEntry) -> Void) {
        completion(VerseEntry(date: .now, verse: Poetry.verseOfTheDay()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<VerseEntry>) -> Void) {
        let tomorrow = Calendar.yarmouk.startOfDay(for: .now.addingTimeInterval(86400))
        completion(Timeline(entries: [VerseEntry(date: .now, verse: Poetry.verseOfTheDay())], policy: .after(tomorrow)))
    }
}

struct VerseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Verse", provider: VerseProvider()) { entry in
            VStack(spacing: 6) {
                Text(entry.verse.first)
                Text(entry.verse.second)
                Text("\(entry.verse.poet) · شو بحره؟").font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
            }
            .font(.system(.subheadline, design: .serif).weight(.medium))
            .multilineTextAlignment(.center)
            .minimumScaleFactor(0.7)
            .environment(\.layoutDirection, .rightToLeft)
            .containerBackground(for: .widget) { Brand.green.opacity(0.08) }
        }
        .configurationDisplayName("بيت اليوم")
        .description("بيت شعر كل يوم، وخمّن بحره")
        .supportedFamilies([.systemMedium, .systemSmall])
    }
}

// MARK: - Live Activity (Dynamic Island + lock screen)

struct LectureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LectureActivityAttributes.self) { context in
            let tint = Color(hex: context.attributes.colorHex)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.start > .now ? "المحاضرة الجاية" : "المحاضرة هلأ").font(.caption).foregroundStyle(.secondary)
                    Text(context.state.courseName).font(.headline)
                    Text(placeText(context.state)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(timerInterval: Date.now...max(context.state.start, Date.now.addingTimeInterval(1)), countsDown: true)
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
            }
            .padding(16)
            .environment(\.layoutDirection, .rightToLeft)
            .activityBackgroundTint(Color(uiColor: .systemBackground).opacity(0.9))
        } dynamicIsland: { context in
            let tint = Color(hex: context.attributes.colorHex)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "graduationcap.fill").font(.title2).foregroundStyle(tint).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...max(context.state.start, Date.now.addingTimeInterval(1)), countsDown: true)
                        .font(.title2.bold().monospacedDigit()).foregroundStyle(tint).frame(width: 90)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 2) {
                        Text(context.state.courseName).font(.headline)
                        Text(placeText(context.state)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                Image(systemName: "graduationcap.fill").foregroundStyle(tint)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(context.state.start, Date.now.addingTimeInterval(1)), countsDown: true)
                    .monospacedDigit().foregroundStyle(tint).frame(width: 48)
            } minimal: {
                Image(systemName: "graduationcap.fill").foregroundStyle(tint)
            }
            .keylineTint(tint)
        }
    }

    private func placeText(_ s: LectureActivityAttributes.ContentState) -> String {
        var parts = [LectureSlot.timeLabel(Calendar.yarmouk.component(.hour, from: s.start), Calendar.yarmouk.component(.minute, from: s.start))]
        if !s.room.isEmpty { parts.append(s.room) }
        if let seat = s.seat { parts.append("مقعد \(seat)") }
        return parts.joined(separator: " · ")
    }
}
