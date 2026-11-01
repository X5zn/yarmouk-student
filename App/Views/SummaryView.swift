import SwiftUI
import Charts

struct SummaryView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSIS = false
    @State private var showMoodle = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "دراستي")
                gpaCard
                NavigationLink(value: PlanRoute()) { planCard }.buttonStyle(PressableStyle())
                SectionTitle(title: "المثبّتة")
                NavigationLink(value: ExamsRoute()) { examCard }.buttonStyle(PressableStyle())
                NavigationLink(value: AssignmentsRoute()) { homeworkCard }.buttonStyle(PressableStyle())
                attendanceCard
                SectionTitle(title: "من الايليرنينغ")
                noticesCard
            }
            .padding(16)
            .padding(.bottom, 12)
        }
        .background(Brand.canvas)
        .navigationTitle("الملخص")
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await store.refreshMoodle()
            if store.sisLinked { await store.refreshSIS() }
        }
        .sheet(isPresented: $showSIS) { SISLoginSheet() }
        .sheet(isPresented: $showMoodle) { MoodleLoginSheet() }
    }

    // MARK: GPA

    @ViewBuilder
    private var gpaCard: some View {
        if let rec = store.sis.record, !rec.isEmpty {
            NavigationLink(value: SISPageRoute(key: "records")) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(symbol: "chart.line.uptrend.xyaxis", title: "المعدل التراكمي", tint: Brand.green,
                               trailing: store.sis.updatedAt.map { ArabicFormat.relative($0) })
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(rec.summary.cumulativeGPA.map { String(format: "%.1f", $0) } ?? "—")
                                    .font(.system(size: 40, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                Text("/ 100").font(.plex(.subheadline)).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                if let h = rec.summary.cumulativeHours ?? rec.summary.passedHours {
                                    Pill(text: "\(h) ساعة", tint: Brand.green)
                                }
                                if let honor = rec.summary.honorList, !honor.isEmpty {
                                    Pill(text: "لوحة الشرف", tint: Brand.gold)
                                }
                            }
                        }
                        Spacer()
                        sparkline(rec.terms.filter { !$0.isPlaceholder && $0.termGPA != nil })
                            .frame(width: 120, height: 54)
                    }
                }
                .healthCard()
            }
            .buttonStyle(PressableStyle())
        } else {
            Button { Haptics.tap(); showSIS = true } label: {
                HStack(spacing: 12) {
                    SymbolTile(symbol: "chart.line.uptrend.xyaxis", tint: Brand.green, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("معدلك وساعاتك من SIS").font(.plex(.body, .semibold)).foregroundStyle(.primary)
                        Text("سجّل دخول مرة وحدة وبيظهر معدلك وسجلك هون").font(.plex(.footnote)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.forward").font(.plex(.footnote, .semibold)).foregroundStyle(.tertiary)
                }
                .healthCard()
            }
            .buttonStyle(PressableStyle())
        }
    }

    private func sparkline(_ terms: [AcademicTerm]) -> some View {
        let dom = sparkDomain(terms)
        return Chart(Array(terms.enumerated()), id: \.offset) { i, t in
            AreaMark(x: .value("الفصل", i), yStart: .value("الأدنى", dom.lowerBound), yEnd: .value("المعدل", t.termGPA ?? dom.lowerBound))
                .foregroundStyle(LinearGradient(colors: [Brand.green.opacity(0.25), Brand.green.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("الفصل", i), y: .value("المعدل", t.termGPA ?? 0))
                .foregroundStyle(Brand.accent)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            if i == terms.count - 1 {
                PointMark(x: .value("الفصل", i), y: .value("المعدل", t.termGPA ?? 0)).foregroundStyle(Brand.accent).symbolSize(40)
            }
        }
        .chartYScale(domain: dom)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .clipped()
        .environment(\.layoutDirection, .leftToRight)
    }

    private func sparkDomain(_ terms: [AcademicTerm]) -> ClosedRange<Double> {
        let v = terms.compactMap(\.termGPA)
        let lo = (v.min() ?? 60) - 2, hi = (v.max() ?? 100) + 2
        return lo...max(hi, lo + 1)
    }

    // MARK: Plan

    private var planCard: some View {
        let p = store.profile
        let doneInt = p.passedHours ?? store.sis.record?.summary.cumulativeHours ?? 0
        let done = Double(doneInt), total = Double(max(p.planTotalHours, 1))
        let pct = p.planPercent ?? Int(done / total * 100)
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "chart.pie.fill", title: "الخطة الدراسية", tint: .teal)
            if doneInt == 0 && !store.sisLinked {
                InlineEmpty(symbol: "building.columns", text: "سجّل دخول SIS وبنحسبلك كم ضايلك للتخرج")
            } else {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color.teal.opacity(0.15), lineWidth: 10)
                    Circle().trim(from: 0, to: min(done / total, 1))
                        .stroke(Color.teal, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(pct)٪").font(.system(size: 17, weight: .bold, design: .rounded))
                }
                .frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(doneInt) من \(Int(total)) ساعة").font(.plex(.title3, .bold)).foregroundStyle(.primary)
                    Text("ضايلك \(max(Int(total) - doneInt, 0)) ساعة").font(.plex(.subheadline)).foregroundStyle(.secondary)
                    if let g = p.graduationEstimate { Text("التخرج تقريباً: \(g)").font(.plex(.subheadline)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
            }
            }
        }
        .healthCard()
    }

    // MARK: Exams

    private var examCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "graduationcap.fill", title: "الامتحانات", tint: .purple,
                       trailing: store.upcomingExams.isEmpty ? nil : "\(store.upcomingExams.count)")
            if store.upcomingExams.isEmpty {
                InlineEmpty(symbol: "plus", text: "ضيف امتحاناتك عشان نذكرك قبلها")
            }
            ForEach(store.upcomingExams.prefix(3)) { e in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.plex(.body, .semibold)).foregroundStyle(.primary)
                        Text((store.course(e.courseCode)?.name ?? e.courseCode) + " · " + ArabicFormat.shortDate(e.date))
                            .font(.plex(.footnote)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(max(ArabicFormat.daysLeft(to: e.date), 0))").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.purple)
                        Text("يوم").font(.plex(.caption2)).foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 44)
                }
            }
        }
        .healthCard()
    }

    // MARK: Homework

    private var homeworkCard: some View {
        let pending = store.pendingDeadlines
        let list = Array((pending.isEmpty ? store.deadlines.sorted { $0.due > $1.due } : pending).prefix(4))
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "square.and.pencil", title: "الواجبات", tint: .orange,
                       trailing: pending.isEmpty ? nil : "\(pending.count) مطلوب")
            if list.isEmpty {
                InlineEmpty(symbol: "checkmark", text: store.moodleLinked ? "ما في واجبات هلأ، مرتاح 👌" : "بتظهر هون لما تربط الايليرنينغ")
            }
            ForEach(list) { d in
                HStack(spacing: 10) {
                    Image(systemName: d.submitted ? "checkmark.circle.fill" : "circle")
                        .font(.title3).foregroundStyle(d.submitted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).font(.plex(.body, .medium)).foregroundStyle(.primary).lineLimit(1)
                        Text(store.course(moodleId: d.courseId)?.name ?? ArabicFormat.shortDate(d.due))
                            .font(.plex(.footnote)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Text(d.submitted ? "مسلّم" : ArabicFormat.relative(d.due)).font(.plex(.caption, .semibold))
                        .foregroundStyle(d.submitted ? .green : .orange)
                }
            }
        }
        .healthCard()
    }

    // MARK: Attendance

    private var attendanceCard: some View {
        let rows: [CourseInfo] = store.timetable.courses.filter { c in store.timetable.slots.contains { $0.courseCode == c.code } }
        let anyMarks = !store.attendance.isEmpty
        let maxLimit: Int = max(rows.map { store.absenceLimit(for: $0.code) }.max() ?? 7, 1)
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "person.badge.clock.fill", title: "الغياب", tint: .red, chevron: false)
            if !anyMarks || rows.isEmpty {
                InlineEmpty(symbol: "hand.raised", text: "علّم «حضرت/غبت» من صفحة المادة، وهون بتشوف وين وصلت من الحد")
            } else {
                ForEach(rows) { c in
                    let used = store.absences(for: c.code), limit = store.absenceLimit(for: c.code)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(c.name).font(.plex(.subheadline, .medium)).lineLimit(1)
                            Spacer()
                            Text("\(used)/\(limit)").font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(used >= limit ? .red : .secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(c.color.opacity(0.12))
                                Capsule().fill(used >= limit - 1 ? Color.red : c.color)
                                    .frame(width: max(geo.size.width * CGFloat(min(used, maxLimit)) / CGFloat(maxLimit), used > 0 ? 8 : 0))
                            }
                        }
                        .frame(height: 8)
                    }
                }
                Text("الحد محسوب على \(Int(store.settings.absenceLimitPercent))٪ من المحاضرات (من الإعدادات)")
                    .font(.plex(.caption)).foregroundStyle(.secondary)
            }
        }
        .healthCard()
    }

    // MARK: Notices

    @ViewBuilder
    private var noticesCard: some View {
        if !store.moodleLinked {
            MoodleConnectCard(message: "إشعارات الدكاترة والواجبات الجديدة بتوصلك هون أول بأول.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "bell.badge.fill", title: "آخر الإشعارات", tint: .blue,
                           trailing: store.lastMoodleSync.map { ArabicFormat.relative($0) }, chevron: false)
                if store.notices.isEmpty { InlineEmpty(symbol: "bell.slash", text: "ما في إشعارات جديدة") }
                ForEach(Array(store.notices.prefix(5).enumerated()), id: \.element.id) { i, n in
                    if i > 0 { Divider() }
                    Button { Haptics.tap(); Router.shared.open(n.url, title: "الايليرنينغ") } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(n.read ? Color.clear : Color.blue).frame(width: 8, height: 8).padding(.top, 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(n.subject).font(.plex(.subheadline, n.read ? .regular : .semibold))
                                    .foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                                Text(ArabicFormat.relative(n.date)).font(.plex(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle(scale: 0.99))
                }
            }
            .healthCard()
        }
    }
}
