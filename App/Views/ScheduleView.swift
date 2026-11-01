import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var store: AppStore
    @State private var selected = Calendar.yarmouk.component(.weekday, from: .now)
    private let days = [7, 1, 2, 3, 4, 5]   // السبت → الخميس
    static let short = [7: "سبت", 1: "أحد", 2: "اثنين", 3: "ثلاثاء", 4: "أربعاء", 5: "خميس"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                dayStrip
                let slots = store.timetable.slots(onWeekday: selected)
                if slots.isEmpty {
                    EmptyHint(symbol: "sun.max", text: "ما في محاضرات يوم \(ArabicFormat.dayName(selected))")
                        .healthCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(slots.enumerated()), id: \.element.id) { idx, slot in
                            if let course = store.course(slot.courseCode) {
                                NavigationLink(value: CourseRoute(code: course.code)) { row(slot, course) }
                                    .buttonStyle(PressableStyle(scale: 0.99))
                                if idx < slots.count - 1 { Divider().padding(.leading, 84) }
                            }
                        }
                    }
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                if let next = store.timetable.nextLecture(), let course = store.course(next.slot.courseCode) {
                    SectionTitle(title: "العداد")
                    Button {
                        Haptics.success()
                        LiveActivityManager.shared.start(slot: next.slot, interval: next.interval, course: course)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "timer").font(.title3).foregroundStyle(Brand.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("شغّل العداد على الجزيرة").font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text("\(course.name) · \(next.slot.startLabel)").font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .healthCard()
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("الجدول")
        .navigationBarTitleDisplayMode(.large)
    }

    private var dayStrip: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { d in
                let isSel = d == selected
                let count = store.timetable.slots(onWeekday: d).count
                Button { selected = d } label: {
                    VStack(spacing: 4) {
                        Text(Self.short[d] ?? "")
                            .font(.footnote.weight(.semibold))
                        Circle().fill(count > 0 ? (isSel ? Color.white : Brand.green) : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .foregroundStyle(isSel ? .white : .primary)
                    .background(isSel ? Brand.green : Brand.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.94))
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func row(_ slot: LectureSlot, _ course: CourseInfo) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(slot.startLabel).font(.headline).foregroundStyle(.primary)
                Text(slot.endLabel).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 52, alignment: .trailing)
            RoundedRectangle(cornerRadius: 2).fill(course.color).frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if slot.isOnline { Label("Teams", systemImage: "video") }
                    else if !slot.room.isEmpty { Label(slot.room, systemImage: "mappin") }
                    if let seat = slot.seat { Text("· مقعد \(seat)") }
                }
                .font(.footnote).foregroundStyle(.secondary)
                if !course.instructor.isEmpty { Text(course.instructor).font(.footnote).foregroundStyle(.secondary) }
            }
            Spacer()
            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
