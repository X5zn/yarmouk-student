import SwiftUI
import Charts

struct SummaryView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "المثبّتة")
                NavigationLink(value: ExamsRoute()) { examCard }.buttonStyle(PressableStyle())
                NavigationLink(value: AssignmentsRoute()) { homeworkCard }.buttonStyle(PressableStyle())
                attendanceCard
                NavigationLink(value: PlanRoute()) { planCard }.buttonStyle(PressableStyle())
                SectionTitle(title: "من الايليرنينغ")
                noticesCard
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("الملخص")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await store.refreshMoodle() }
    }

    private var examCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "graduationcap.fill", title: "الامتحانات", tint: .purple)
            if store.upcomingExams.isEmpty {
                EmptyHint(symbol: "plus.circle", text: "ضيف امتحاناتك عشان نذكرك ونعدّلك")
            }
            ForEach(store.upcomingExams.prefix(3)) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(e.title) · \(store.course(e.courseCode)?.name ?? e.courseCode)").font(.body.weight(.semibold)).foregroundStyle(.primary)
                        Text(ArabicFormat.shortDate(e.date) + (e.notes.isEmpty ? "" : " · \(e.notes)")).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(max(ArabicFormat.daysLeft(to: e.date), 0))").font(.title2.bold()).foregroundStyle(.purple)
                        Text("يوم").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .healthCard()
    }

    private var homeworkCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "square.and.pencil", title: "الواجبات", tint: .orange)
            let list = store.deadlines.sorted { $0.due > $1.due }.prefix(4)
            if list.isEmpty { EmptyHint(symbol: "tray", text: "ما في واجبات على الايليرنينغ") }
            ForEach(Array(list)) { d in
                HStack(spacing: 10) {
                    Image(systemName: d.submitted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(d.submitted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.name).font(.body).foregroundStyle(.primary).lineLimit(1)
                        Text("\(store.course(moodleId: d.courseId)?.name ?? "") · \(ArabicFormat.shortDate(d.due))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(d.submitted ? "مسلّم" : ArabicFormat.relative(d.due)).font(.caption.weight(.semibold))
                        .foregroundStyle(d.submitted ? .green : .orange)
                }
            }
        }
        .healthCard()
    }

    private var attendanceCard: some View {
        let rows: [CourseInfo] = store.timetable.courses.filter { c in store.timetable.slots.contains { $0.courseCode == c.code } }
        let limits: [Int] = rows.map { store.absenceLimit(for: $0.code) }
        let maxLimit: Int = max(limits.max() ?? 7, 1)
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "person.badge.clock.fill", title: "الحضور", tint: .red)
            Chart(rows) { c in
                BarMark(x: .value("غياب", store.absences(for: c.code)), y: .value("المادة", c.name))
                    .foregroundStyle(c.color)
                    .annotation(position: .trailing) {
                        Text("\(store.absences(for: c.code))/\(store.absenceLimit(for: c.code))").font(.caption2).foregroundStyle(.secondary)
                    }
            }
            .chartXScale(domain: 0...maxLimit)
            .chartXAxis(.hidden)
            .frame(height: CGFloat(rows.count) * 34)
            Text("الحد المسموح محسوب على \(Int(store.settings.absenceLimitPercent))٪ من المحاضرات (بتقدر تغيّره من الإعدادات)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .healthCard()
    }

    private var planCard: some View {
        let p = store.profile
        let done = Double(p.passedHours ?? 0), total = Double(p.planTotalHours)
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "chart.pie.fill", title: "الخطة الدراسية", tint: Brand.green,
                       trailing: p.updatedAt.map { ArabicFormat.relative($0) })
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Brand.green.opacity(0.15), lineWidth: 10)
                    Circle().trim(from: 0, to: total > 0 ? done / total : 0)
                        .stroke(Brand.green, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(percentText(p, done: done, total: total)).font(.headline)
                }
                .frame(width: 74, height: 74)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(done)) من \(Int(total)) ساعة").font(.title3.bold()).foregroundStyle(.primary)
                    if let r = p.remainingHours { Text("ضايلك \(r) ساعة").font(.subheadline).foregroundStyle(.secondary) }
                    if let g = p.graduationEstimate { Text("التخرج تقريباً: \(g)").font(.subheadline).foregroundStyle(.secondary) }
                }
            }
        }
        .healthCard()
    }

    private func percentText(_ p: StudentProfile, done: Double, total: Double) -> String {
        let pct: Int = p.planPercent ?? (total > 0 ? Int(done / total * 100) : 0)
        return "\(pct)٪"
    }

    private var noticesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "megaphone.fill", title: "آخر الإشعارات", tint: .blue)
            if store.notices.isEmpty { EmptyHint(symbol: "bell.slash", text: "ما في إشعارات") }
            ForEach(store.notices.prefix(5)) { n in
                Button { Haptics.tap(); Router.shared.open(n.url, title: "الايليرنينغ") } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(n.subject).font(.subheadline.weight(n.read ? .regular : .semibold)).foregroundStyle(.primary).lineLimit(2)
                        Text(ArabicFormat.relative(n.date)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(PressableStyle(scale: 0.99))
            }
        }
        .healthCard()
    }
}
