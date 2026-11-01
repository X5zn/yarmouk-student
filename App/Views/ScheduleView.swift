import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject var store: AppStore
    @State private var selected = Int(DemoMode.value("-day") ?? "") ?? ScheduleView.defaultDay()
    @State private var mode = DemoMode.flag("-week") ? 1 : 0
    @State private var showSIS = false
    @Namespace private var pill
    private let days = [7, 1, 2, 3, 4, 5]   // السبت → الخميس
    static let short = [7: "سبت", 1: "أحد", 2: "اثنين", 3: "ثلاثاء", 4: "أربعاء", 5: "خميس"]

    static func defaultDay() -> Int {
        let wd = Calendar.yarmouk.component(.weekday, from: .now)
        return wd == 6 ? 7 : wd     // Friday → Saturday
    }

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    todayCard(now: ctx.date)
                    Picker("العرض", selection: $mode) {
                        Text("يومي").tag(0)
                        Text("الأسبوع").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: mode)

                    if mode == 0 {
                        dayStrip
                        dayList(now: ctx.date)
                            .id(selected)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)), removal: .opacity))
                    } else {
                        weekGrid
                            .transition(.opacity)
                    }
                    sourceFooter
                }
                .padding(16)
                .padding(.bottom, 12)
                .animation(.snappy(duration: 0.3), value: selected)
                .animation(.snappy(duration: 0.3), value: mode)
            }
        }
        .background(Brand.canvas)
        .navigationTitle("الجدول")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { if store.sisLinked { await store.refreshSIS() } }
        .sheet(isPresented: $showSIS) { SISLoginSheet() }
    }

    // MARK: Today

    private func todayCard(now: Date) -> some View {
        let today = store.timetable.slots(on: now)
        let next = store.timetable.nextLecture(after: now)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ArabicFormat.shortDate(now))
                        .font(.plex(.subheadline, .medium)).opacity(0.85)
                    Text(countText(today.count))
                        .font(.plex(.title3, .bold))
                }
                Spacer()
                Image(systemName: today.isEmpty ? "sun.max.fill" : "calendar.badge.clock")
                    .font(.system(size: 28, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
            }
            if let next, let course = store.course(next.slot.courseCode) {
                let live = next.interval.contains(now)
                HStack(spacing: 10) {
                    Circle().fill(live ? Color.red : Brand.gold).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(live ? "هلأ: \(course.name)" : "الجاية: \(course.name)").font(.plex(.subheadline, .semibold)).lineLimit(1)
                        Text(nextLine(next.slot, next.interval, now: now)).font(.plex(.caption)).opacity(0.85)
                    }
                    Spacer()
                    Button {
                        Haptics.success()
                        LiveActivityManager.shared.start(slot: next.slot, interval: next.interval, course: course)
                    } label: {
                        Image(systemName: "timer").font(.system(size: 15, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.2), in: Circle())
                    }
                    .accessibilityLabel("شغّل العداد على الجزيرة")
                }
                .padding(10)
                .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(LinearGradient(colors: [Brand.green, Brand.greenDark], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func nextLine(_ slot: LectureSlot, _ iv: DateInterval, now: Date) -> String {
        var parts: [String] = []
        if iv.contains(now) {
            parts.append("بتخلص \(slot.endLabel)")
        } else {
            let mins = Int(iv.start.timeIntervalSince(now) / 60)
            if Calendar.yarmouk.isDate(iv.start, inSameDayAs: now) {
                parts.append(mins < 60 ? "بعد \(max(mins, 1)) دقيقة" : "الساعة \(slot.startLabel)")
            } else {
                parts.append("\(ArabicFormat.dayName(slot.weekday)) \(slot.startLabel)")
            }
        }
        if slot.isOnline { parts.append("Teams") } else if !slot.room.isEmpty { parts.append(slot.room) }
        return parts.joined(separator: " · ")
    }

    // MARK: Day strip

    private var dayStrip: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { d in
                let isSel = d == selected
                let isToday = d == Calendar.yarmouk.component(.weekday, from: .now)
                let count = store.timetable.slots(onWeekday: d).count
                Button { selected = d } label: {
                    VStack(spacing: 5) {
                        Text(Self.short[d] ?? "")
                            .font(.plex(.footnote, isSel || isToday ? .bold : .medium))
                        HStack(spacing: 2) {
                            ForEach(0..<min(count, 4), id: \.self) { _ in
                                Circle().fill(isSel ? Color.white : Brand.green).frame(width: 4, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .foregroundStyle(isSel ? .white : (isToday ? Brand.green : .primary))
                    .background {
                        if isSel {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.green)
                                .matchedGeometryEffect(id: "pill", in: pill)
                        } else {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Brand.card)
                        }
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.94))
                .accessibilityLabel(ArabicFormat.dayName(d) + "، \(count) محاضرات")
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: Day list

    @ViewBuilder
    private func dayList(now: Date) -> some View {
        let slots = store.timetable.slots(onWeekday: selected)
        if slots.isEmpty {
            StateCard(symbol: selected == 7 ? "cup.and.saucer.fill" : "sun.max.fill", tint: Brand.gold,
                      title: "يوم \(ArabicFormat.dayName(selected)) فاضي",
                      message: "ما عندك محاضرات بهاليوم. استغله براحتك 🌿")
        } else {
            let isToday = selected == Calendar.yarmouk.component(.weekday, from: now)
            VStack(spacing: 10) {
                ForEach(Array(slots.enumerated()), id: \.element.id) { idx, slot in
                    if idx > 0 {
                        let gap = gapMinutes(slots[idx - 1], slot)
                        if gap >= 30 { BreakRow(minutes: gap) }
                    }
                    if let course = store.course(slot.courseCode) {
                        let iv = store.timetable.interval(of: slot, on: now)
                        let state = lectureState(iv, now: now, isToday: isToday)
                        NavigationLink(value: CourseRoute(code: course.code)) {
                            LectureCard(slot: slot, course: course, state: state)
                        }
                        .buttonStyle(PressableStyle(scale: 0.98))
                    }
                }
            }
        }
    }

    private func lectureState(_ iv: DateInterval, now: Date, isToday: Bool) -> LectureCard.Phase {
        guard isToday else { return .future }
        if iv.contains(now) { return .live(progress: now.timeIntervalSince(iv.start) / max(iv.duration, 1)) }
        return iv.end < now ? .past : .future
    }

    private func countText(_ n: Int) -> String {
        if n == 0 { return "ما عندك محاضرات اليوم" }
        if n == 1 { return "عندك محاضرة وحدة اليوم" }
        if n == 2 { return "عندك محاضرتين اليوم" }
        return "عندك \(n) محاضرات اليوم"
    }

    private func gapMinutes(_ a: LectureSlot, _ b: LectureSlot) -> Int {
        (b.startHour * 60 + b.startMinute) - (a.startHour * 60 + a.startMinute + a.durationMinutes)
    }

    // MARK: Week

    private var weekGrid: some View {
        VStack(spacing: 10) {
            ForEach(days, id: \.self) { d in
                let slots = store.timetable.slots(onWeekday: d)
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 2) {
                        Text(Self.short[d] ?? "").font(.plex(.subheadline, .bold))
                        Text("\(slots.count)").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .frame(width: 52)
                    .padding(.vertical, 6)
                    .foregroundStyle(d == Calendar.yarmouk.component(.weekday, from: .now) ? Brand.green : .primary)
                    if slots.isEmpty {
                        Text("فاضي").font(.plex(.footnote)).foregroundStyle(.tertiary).padding(.vertical, 10)
                        Spacer()
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(slots) { s in
                                if let c = store.course(s.courseCode) {
                                    NavigationLink(value: CourseRoute(code: c.code)) {
                                        HStack(spacing: 8) {
                                            RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: 3, height: 26)
                                            VStack(alignment: .leading, spacing: 0) {
                                                Text(c.name).font(.plex(.footnote, .semibold)).foregroundStyle(.primary).lineLimit(1)
                                                Text(s.startLabel + (s.isOnline ? " · Teams" : (s.room.isEmpty ? "" : " · " + s.room)))
                                                    .font(.plex(.caption2)).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 8).padding(.vertical, 5)
                                        .background(c.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                    .buttonStyle(PressableStyle(scale: 0.98))
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(Brand.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    // MARK: Source

    @ViewBuilder
    private var sourceFooter: some View {
        if store.sis.registered?.isEmpty == false {
            UpdatedFooter(source: "SIS (موادي المسجلة)", date: store.sis.updatedAt)
        } else {
            Button { Haptics.tap(); showSIS = true } label: {
                HStack(spacing: 12) {
                    SymbolTile(symbol: "arrow.triangle.2.circlepath", tint: Brand.green, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("خلّي الجدول من SIS").font(.plex(.subheadline, .semibold)).foregroundStyle(.primary)
                        Text("القاعات والأوقات والدكاترة بتنسحب من موادك المسجلة").font(.plex(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.forward").font(.plex(.footnote, .semibold)).foregroundStyle(.tertiary)
                }
                .healthCard(padding: 14)
            }
            .buttonStyle(PressableStyle())
        }
    }
}

// MARK: - Pieces

struct LectureCard: View {
    enum Phase: Equatable { case past, live(progress: Double), future }
    let slot: LectureSlot
    let course: CourseInfo
    let state: Phase

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(slot.startLabel).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.primary)
                Text(slot.endLabel).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            }
            .frame(width: 50, alignment: .trailing)
            .padding(.top, 2)
            RoundedRectangle(cornerRadius: 2.5).fill(course.color.gradient).frame(width: 5)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(course.name).font(.plex(.body, .semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if case .live = state { Pill(text: "هلأ", tint: .red) }
                }
                HStack(spacing: 6) {
                    if slot.isOnline { tag("video.fill", "Teams") }
                    else if !slot.room.isEmpty { tag("mappin.and.ellipse", slot.room) }
                    if let seat = slot.seat { tag("chair.fill", "مقعد \(seat)") }
                    tag("number", course.code)
                }
                if !course.instructor.isEmpty {
                    Label(course.instructor, systemImage: "person.fill").font(.plex(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
                if case .live(let p) = state {
                    ProgressView(value: min(max(p, 0), 1)).tint(course.color)
                }
            }
            Image(systemName: "chevron.forward").font(.plex(.footnote, .semibold)).foregroundStyle(.tertiary).padding(.top, 4)
        }
        .padding(14)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if case .live = state {
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(course.color.opacity(0.6), lineWidth: 1.5)
            }
        }
        .opacity(state == .past ? 0.55 : 1)
    }

    private func tag(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.plex(.caption, .medium))
            .lineLimit(1)
            .foregroundStyle(course.color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(course.color.opacity(0.1), in: Capsule())
    }
}

struct BreakRow: View {
    let minutes: Int
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            Label(text, systemImage: "cup.and.saucer").font(.plex(.caption, .medium)).foregroundStyle(.secondary).fixedSize()
            Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
        }
        .padding(.horizontal, 8)
    }
    private var text: String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "استراحة \(m) دقيقة" }
        let hs = h == 1 ? "ساعة" : (h == 2 ? "ساعتين" : "\(h) ساعات")
        return m == 0 ? "استراحة \(hs)" : "استراحة \(hs) و\(m) دقيقة"
    }
}
