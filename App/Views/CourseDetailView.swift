import SwiftUI

struct CourseDetailView: View {
    let code: String
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    @State private var loading = false

    var course: CourseInfo? { store.course(code) }

    var body: some View {
        ScrollView {
            if let course {
                VStack(alignment: .leading, spacing: 12) {
                    header(course)
                    actions(course)
                    attendance(course)
                    let dl = store.deadlines.filter { $0.courseId == course.moodleId }
                    if !dl.isEmpty { deadlines(dl) }
                    let ex = store.upcomingExams.filter { $0.courseCode == code }
                    if !ex.isEmpty { exams(ex) }
                    SectionTitle(title: "محتوى المادة")
                    content(course)
                }
                .padding(16)
            }
        }
        .background(Brand.canvas)
        .navigationTitle(course?.name ?? code)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let id = course?.moodleId, store.moodleLinked else { return }
            loading = store.sections[id] == nil
            await store.loadSections(courseId: id)
            loading = false
        }
    }

    private func header(_ c: CourseInfo) -> some View {
        let slots = store.timetable.slots.filter { $0.courseCode == code }
        return VStack(alignment: .leading, spacing: 8) {
            Text(c.code).font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            Text(c.name).font(.title.bold()).foregroundStyle(.white)
            if !c.instructor.isEmpty { Text(c.instructor).font(.body).foregroundStyle(.white.opacity(0.9)) }
            if let first = slots.first {
                let days = slots.map { ArabicFormat.dayName($0.weekday) }.joined(separator: " · ")
                Text("\(days) · \(first.startLabel)–\(first.endLabel)\(first.isOnline ? " · Teams" : (first.room.isEmpty ? "" : " · \(first.room)"))\(first.seat.map { " · مقعد \($0)" } ?? "")")
                    .font(.footnote).foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.color.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func actions(_ c: CourseInfo) -> some View {
        HStack(spacing: 4) {
            QuickAction(symbol: "books.vertical", title: "صفحة المادة") {
                if let u = c.moodleURL { router.web = WebLink(url: u, title: c.name) }
            }
            QuickAction(symbol: "mic", title: "شو اخدتوا؟") { router.openNotes(for: code) }
            if let teams = teamsModule {
                QuickAction(symbol: "video", title: "Teams") { router.open(teams.url, title: "Teams") }
            }
            QuickAction(symbol: "megaphone", title: "الإعلانات") {
                if let f = forumModule { router.open(f.url, title: "الإعلانات") }
                else if let u = c.moodleURL { router.web = WebLink(url: u, title: c.name) }
            }
        }
        .padding(.vertical, 14)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var modules: [MoodleModule] {
        guard let id = course?.moodleId else { return [] }
        return (store.sections[id] ?? []).flatMap(\.modules)
    }
    private var teamsModule: MoodleModule? {
        modules.first { $0.kind == "url" && ($0.name.localizedCaseInsensitiveContains("teams") || $0.name.contains("تيمز")) }
    }
    private var forumModule: MoodleModule? { modules.first { $0.kind == "forum" } }

    private func attendance(_ c: CourseInfo) -> some View {
        let used = store.absences(for: code), limit = store.absenceLimit(for: code)
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "person.badge.clock", title: "الحضور والغياب", tint: .red)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(used)").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("غياب من \(limit) مسموح").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let r = store.attendanceRate(for: code) { Pill(text: "حضور \(Int(r * 100))٪", tint: .green) }
            }
            ProgressView(value: Double(min(used, limit)), total: Double(max(limit, 1))).tint(used >= limit - 1 ? .red : .orange)
            Text(used >= limit ? "وصلت الحد! انتبه من الحرمان." : "بتقدر تغيب \(max(limit - used, 0)) كمان بأمان (تقريباً).")
                .font(.footnote).foregroundStyle(used >= limit ? .red : .secondary)
            HStack {
                Button { Haptics.success(); store.markAttendance(code: code, attended: true) } label: {
                    Label("حضرت اليوم", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.green)
                Button { Haptics.warning(); store.markAttendance(code: code, attended: false) } label: {
                    Label("غبت اليوم", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(.red)
            }
        }
        .healthCard()
    }

    private func deadlines(_ list: [Deadline]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "square.and.pencil", title: "الواجبات", tint: .orange)
            ForEach(list.sorted { $0.due > $1.due }) { d in
                Button { Haptics.tap(); router.open(d.url, title: d.name) } label: {
                    HStack {
                        Image(systemName: d.submitted ? "checkmark.circle.fill" : "clock").foregroundStyle(d.submitted ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.body).foregroundStyle(.primary)
                            Text("آخر موعد \(ArabicFormat.shortDate(d.due)) \(ArabicFormat.time(d.due))").font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(d.submitted ? "مسلّم" : "سلّم").font(.caption.weight(.semibold)).foregroundStyle(d.submitted ? .green : Brand.green)
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.99))
            }
        }
        .healthCard()
    }

    private func exams(_ list: [Exam]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(symbol: "graduationcap", title: "الامتحانات", tint: .purple)
            ForEach(list) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.body.weight(.semibold))
                        Text(ArabicFormat.shortDate(e.date) + (e.notes.isEmpty ? "" : " · \(e.notes)")).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("بعد \(max(ArabicFormat.daysLeft(to: e.date), 0)) يوم").font(.subheadline.weight(.semibold)).foregroundStyle(.purple)
                }
            }
        }
        .healthCard()
    }

    @ViewBuilder
    private func content(_ c: CourseInfo) -> some View {
        if let id = c.moodleId, let secs = store.sections[id], !secs.isEmpty {
            ForEach(secs) { sec in
                VStack(alignment: .leading, spacing: 0) {
                    Text(sec.title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
                    ForEach(Array(sec.modules.filter { $0.kind != "label" }.enumerated()), id: \.element.id) { idx, m in
                        if idx > 0 { Divider().padding(.leading, 52) }
                        Button { Haptics.tap(); router.open(m.url, title: m.name) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: m.symbol).font(.body).foregroundStyle(c.color).frame(width: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(m.name).font(.body).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                    if !m.kindLabel.isEmpty { Text(m.kindLabel).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle(scale: 0.99))
                        .disabled(m.url == nil)
                    }
                }
                .padding(.bottom, 6)
                .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        } else if loading {
            HStack { ProgressView(); Text("عم نجيب المحتوى…").foregroundStyle(.secondary) }.healthCard()
        } else if !store.moodleLinked {
            EmptyHint(symbol: "person.crop.circle.badge.exclamationmark", text: "سجّل دخول الايليرنينغ من «حسابي» عشان تظهر الملفات هون").healthCard()
        } else {
            EmptyHint(symbol: "tray", text: "ما في محتوى منزّل لهاي المادة لسا").healthCard()
        }
    }
}
