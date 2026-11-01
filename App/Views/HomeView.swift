import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 12) {
                    summaryCard
                        .padding(.top, -64)
                    if store.moodleNeedsLogin { reconnectBanner }
                    SectionTitle(title: "المثبّتة")
                    NavigationLink(value: AssignmentsRoute()) { assignmentsCard }.buttonStyle(PressableStyle())
                    NavigationLink(value: ExamsRoute()) { examsCard }.buttonStyle(PressableStyle())
                    absencesCard
                    SectionTitle(title: "موادي")
                    coursesList
                    NavigationLink(value: PoetryRoute()) { verseCard }.buttonStyle(PressableStyle())
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Brand.canvas)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await store.refreshMoodle()
            await store.refreshSIS()
        }
    }

    // MARK: Header (Reflect style)

    private var header: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Button { Haptics.tap(); router.tab = .account } label: {
                    Text(store.avatarLetter)
                        .font(.plex(.headline)).foregroundStyle(Brand.green)
                        .frame(width: 40, height: 40)
                        .background(.white, in: Circle())
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.greeting).font(.plex(.headline)).foregroundStyle(.white)
                    Text(store.profile.major).font(.plex(.footnote)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Image("YULogo")
                    .resizable().scaledToFit()
                    .padding(6)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
                    .accessibilityLabel("جامعة اليرموك")
                Button { Haptics.tap(); router.open("https://elearning.yu.edu.jo/message/output/popup/notifications.php", title: "الإشعارات") } label: {
                    Image(systemName: "bell")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.white.opacity(0.15), in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if store.notices.contains(where: { !$0.read }) {
                                Circle().fill(Brand.gold).frame(width: 9, height: 9).offset(x: -8, y: 8)
                            }
                        }
                }
            }
            VStack(spacing: 2) {
                Text("\(store.todaysSlots.count)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(store.todaysSlots.isEmpty ? "ما في محاضرات اليوم" : "محاضرات اليوم")
                    .font(.plex(.subheadline)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(.bottom, 74)
        }
        .padding(.horizontal, 20)
        .padding(.top, 62)
        .frame(maxWidth: .infinity)
        .background(Brand.green)
    }

    // MARK: Summary card + quick actions

    private var summaryCard: some View {
        VStack(spacing: 16) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let next = store.timetable.nextLecture(after: context.date), let course = store.course(next.slot.courseCode) {
                    Button { Haptics.tap(); router.homePath.append(CourseRoute(code: course.code)) } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3).fill(course.color).frame(width: 5, height: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(next.interval.start <= context.date ? "المحاضرة الحالية" : "المحاضرة الجاية")
                                    .font(.plex(.caption)).foregroundStyle(.secondary)
                                Text(course.name).font(.plex(.headline)).foregroundStyle(.primary)
                                Text(detail(next.slot)).font(.plex(.subheadline)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(next.slot.startLabel).font(.plex(.title3, .bold)).foregroundStyle(.primary)
                                Text(countdown(to: next.interval.start, now: context.date))
                                    .font(.plex(.caption, .semibold)).foregroundStyle(Brand.green)
                            }
                        }
                    }
                    .buttonStyle(PressableStyle())
                } else {
                    InlineEmpty(symbol: "moon.stars", text: "ما في محاضرات قريبة")
                }
            }
            Divider()
            HStack(spacing: 4) {
                QuickAction(symbol: "calendar", title: "الجدول") { router.tab = .schedule }
                QuickAction(symbol: "chart.bar.doc.horizontal", title: "العلامات") {
                    router.homePath.append(SISPageRoute(key: "marks"))
                }
                QuickAction(symbol: "list.bullet.rectangle.portrait", title: "معدلي") {
                    router.homePath.append(SISPageRoute(key: "records"))
                }
                QuickAction(symbol: "books.vertical", title: "الايليرنينغ") { router.open("https://elearning.yu.edu.jo/my/", title: "الايليرنينغ") }
            }
        }
        .padding(18)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }

    private func detail(_ slot: LectureSlot) -> String {
        var parts: [String] = []
        if slot.isOnline { parts.append("Teams") } else if !slot.room.isEmpty { parts.append(slot.room) }
        if let seat = slot.seat { parts.append("مقعد \(seat)") }
        if let c = store.course(slot.courseCode), !c.instructor.isEmpty { parts.append(c.instructor) }
        return parts.joined(separator: " · ")
    }

    private func countdown(to date: Date, now: Date) -> String {
        let mins = Int(date.timeIntervalSince(now) / 60)
        if mins <= 0 { return "هلأ" }
        if mins < 60 { return "بعد \(mins) د" }
        let h = mins / 60, m = mins % 60
        if h < 24 { return m == 0 ? "بعد \(h) س" : "بعد \(h) س \(m) د" }
        return ArabicFormat.dayName(Calendar.yarmouk.component(.weekday, from: date))
    }

    private var reconnectBanner: some View {
        Button { Haptics.tap(); Task { await store.refreshMoodle() } } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("جلسة الايليرنينغ خلصت، اضغط لنجددها").font(.plex(.subheadline, .semibold))
                Spacer()
            }
            .foregroundStyle(.orange)
            .healthCard(padding: 14)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Pinned (Health style)

    private var assignmentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "square.and.pencil", title: "الواجبات", tint: .orange,
                       trailing: store.lastMoodleSync.map { ArabicFormat.relative($0) })
            if let d = store.pendingDeadlines.first {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.pendingDeadlines.count)").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("مطلوب").font(.plex(.subheadline)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                Text("\(d.name) · \(store.course(moodleId: d.courseId)?.name ?? "") · \(ArabicFormat.relative(d.due))")
                    .font(.plex(.subheadline)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.submittedCount)").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("مسلّم · ما عليك إشي هلأ").font(.plex(.subheadline)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
        }
        .healthCard()
    }

    private var examsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "graduationcap", title: "الامتحانات", tint: .purple)
            if let e = store.upcomingExams.first {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(max(ArabicFormat.daysLeft(to: e.date), 0))").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("يوم").font(.plex(.subheadline)).foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                Text("\(store.course(e.courseCode)?.name ?? e.courseCode) · \(e.title) \(ArabicFormat.shortDate(e.date))")
                    .font(.plex(.subheadline)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                InlineEmpty(symbol: "plus", text: "ما في امتحانات مسجلة، ضيفها من هون")
            }
        }
        .healthCard()
    }

    private var absencesCard: some View {
        let worst: AbsenceStat? = worstAbsence()
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "person.badge.clock", title: "الغيابات", tint: .red)
            if let w = worst, w.used > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(w.used)/\(w.limit)").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(w.name).font(.plex(.subheadline)).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(min(w.used, w.limit)), total: Double(w.limit))
                    .tint(w.used >= w.limit - 1 ? Color.red : Color.orange)
            } else {
                InlineEmpty(symbol: "hand.thumbsup", text: "ولا غياب لحد هلأ. بعد كل محاضرة بنسألك «حضرت؟»")
            }
        }
        .healthCard()
    }

    private struct AbsenceStat { let name: String; let used: Int; let limit: Int }

    private func worstAbsence() -> AbsenceStat? {
        var best: AbsenceStat?
        var bestRatio = -1.0
        for c in store.timetable.courses {
            let hasSlots = store.timetable.slots.contains { $0.courseCode == c.code }
            if !hasSlots { continue }
            let used = store.absences(for: c.code)
            let limit = store.absenceLimit(for: c.code)
            let ratio = Double(used) / Double(max(limit, 1))
            if ratio > bestRatio {
                bestRatio = ratio
                best = AbsenceStat(name: c.name, used: used, limit: limit)
            }
        }
        return best
    }

    private var coursesList: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.timetable.courses.enumerated()), id: \.element.id) { idx, course in
                NavigationLink(value: CourseRoute(code: course.code)) {
                    HStack(spacing: 12) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(course.color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.name).font(.plex(.body)).foregroundStyle(.primary)
                            Text(course.code + (course.instructor.isEmpty ? "" : " · \(course.instructor)"))
                                .font(.plex(.footnote)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let pending = store.pendingDeadlines.filter { $0.courseId == course.moodleId }.count
                        if pending > 0 { Pill(text: "\(pending) واجب", tint: .orange) }
                        Image(systemName: "chevron.forward").font(.plex(.footnote, .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle(scale: 0.99))
                if idx < store.timetable.courses.count - 1 { Divider().padding(.leading, 60) }
            }
        }
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var verseCard: some View {
        let v = Poetry.verseOfTheDay()
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "text.quote", title: "بيت اليوم", tint: Brand.green, trailing: v.poet)
            VStack(spacing: 4) {
                Text(v.first)
                Text(v.second)
            }
            .font(.custom("Amiri-Regular", size: 21, relativeTo: .title3))
            .lineSpacing(4)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            Text("شو بحره؟ اضغط وجرّب").font(.plex(.footnote)).foregroundStyle(.secondary)
        }
        .healthCard()
    }
}
