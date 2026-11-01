import SwiftUI
import Charts

// Native screens for the SIS pages. They always show the saved data instantly;
// refreshing reuses the saved SIS session and only asks for a login when SIS itself expired it.

// MARK: - Router target

struct SISPageView: View {
    let key: String
    var body: some View {
        switch key {
        case "records": AcademicRecordView()
        case "info": StudentInfoView()
        case "registered", "schedule": RegisteredCoursesView()
        case "marks": MarksView()
        default: SISGenericPageView(key: key)
        }
    }
}

// MARK: - Shared pieces

/// Pull-to-refresh + toolbar refresh + one login sheet when SIS really needs it.
struct SISRefreshable: ViewModifier {
    @EnvironmentObject var store: AppStore
    @State private var showLogin = false

    func body(content: Content) -> some View {
        content
            .refreshable { await refresh() }
            .safeAreaInset(edge: .top, spacing: 0) {
                if store.sisNeedsLogin && store.sisLinked {
                    Button { Haptics.tap(); showLogin = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath").font(.plex(.subheadline, .semibold))
                            Text("جلسة SIS خلصت، المعروض من آخر تحديث").font(.plex(.footnote, .medium))
                            Spacer(minLength: 6)
                            Text("تحديث").font(.plex(.footnote, .semibold))
                        }
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16).padding(.top, 6)
                    }
                    .buttonStyle(PressableStyle())
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.sisRefreshing {
                        ProgressView()
                    } else {
                        Button { Haptics.tap(); Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("تحديث")
                    }
                }
            }
            .sheet(isPresented: $showLogin) { SISLoginSheet() }
            .animation(.snappy, value: store.sisNeedsLogin)
    }

    private func refresh() async {
        guard store.sisLinked, SISSync.savedSession != nil else { showLogin = true; return }
        if await store.refreshSIS() { Haptics.success() } else { store.sisNeedsLogin = true }
    }
}

extension View {
    func sisRefreshable() -> some View { modifier(SISRefreshable()) }
}

/// Shown when a page has never been fetched.
struct SISEmptyState: View {
    var symbol: String
    var title: String
    var message: String
    @EnvironmentObject var store: AppStore
    @State private var showLogin = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Brand.green)
                .frame(width: 66, height: 66)
                .background(Brand.green.opacity(0.12), in: Circle())
            Text(title).font(.plex(.headline))
            Text(message).font(.plex(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                if store.sisLinked && SISSync.savedSession != nil { Task { if !(await store.refreshSIS()) { showLogin = true } } }
                else { showLogin = true }
            } label: {
                Text(store.sisLinked ? "حدّث هلأ" : "سجّل دخول SIS")
                    .font(.plex(.headline)).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent).tint(Brand.green)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .sheet(isPresented: $showLogin) { SISLoginSheet() }
    }
}

struct SISFooter: View {
    var date: Date?
    var body: some View {
        if let date {
            Text("آخر تحديث من SIS \(ArabicFormat.relative(date))")
                .font(.plex(.caption)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }
}

private func gpaText(_ d: Double?) -> String { d.map { String(format: "%.1f", $0) } ?? "—" }
private func intText(_ i: Int?) -> String { i.map { String($0) } ?? "—" }

// MARK: - السجل الأكاديمي

struct AcademicRecordView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let record = store.sis.record, !record.isEmpty {
                    RecordHero(record: record)
                    let real = record.terms.filter { !$0.isPlaceholder }
                    if real.count >= 2 { GPATrendCard(terms: real) }
                    SectionTitle(title: "الفصول")
                    ForEach(Array(record.terms.reversed())) { term in
                        let prev = previous(of: term, in: record.terms)
                        if term.isPlaceholder { PlaceholderTermRow(term: term) } else { TermCard(term: term, previous: prev) }
                    }
                    SISFooter(date: store.sis.updatedAt)
                } else {
                    SISEmptyState(symbol: "list.bullet.rectangle.portrait", title: "سجلك الأكاديمي",
                                  message: "معدلك وكل فصل بكرت لحاله، أول ما نحدّث من SIS.")
                }
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("السجل الأكاديمي")
        .navigationBarTitleDisplayMode(.large)
        .sisRefreshable()
    }

    private func previous(of term: AcademicTerm, in terms: [AcademicTerm]) -> AcademicTerm? {
        guard let i = terms.firstIndex(of: term) else { return nil }
        return terms[..<i].last { !$0.isPlaceholder }
    }
}

private struct RecordHero: View {
    let record: AcademicRecord
    var body: some View {
        let s = record.summary
        let honors = record.terms.filter(\.honorList).count
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("المعدل التراكمي").font(.plex(.subheadline, .semibold)).foregroundStyle(.white.opacity(0.85))
                Spacer()
                if honors > 0 {
                    Label(honors == 1 ? "لوحة الشرف" : "لوحة الشرف ×\(honors)", systemImage: "star.fill")
                        .font(.plex(.caption, .bold))
                        .foregroundStyle(Brand.gold)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.95), in: Capsule())
                }
            }
            Text(verbatim: gpaText(s.cumulativeGPA))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            HStack(spacing: 0) {
                heroStat("ساعات مجتازة", intText(s.passedHours))
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 34)
                heroStat("ساعات تراكمية", intText(s.cumulativeHours))
                Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 34)
                heroStat("مجموع العلامات", intText(s.totalMarks))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Brand.green, Brand.greenDark], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .shadow(color: Brand.green.opacity(0.25), radius: 16, y: 8)
    }

    private func heroStat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(verbatim: value).font(.plex(.title3, .bold)).monospacedDigit().foregroundStyle(.white)
            Text(title).font(.plex(.caption)).foregroundStyle(.white.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GPATrendCard: View {
    let terms: [AcademicTerm]
    var body: some View {
        let values = terms.flatMap { [$0.termGPA, $0.cumulativeGPA].compactMap { $0 } }
        let lo = (values.min() ?? 60) - 3, hi = min((values.max() ?? 100) + 3, 100)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                Text("معدلك عبر الفصول")
            }
            .font(.plex(.subheadline, .semibold)).foregroundStyle(Brand.green)
            Chart {
                ForEach(terms) { t in
                    if let g = t.termGPA {
                        LineMark(x: .value("الفصل", t.term), y: .value("المعدل", g), series: .value("النوع", "الفصلي"))
                            .foregroundStyle(by: .value("النوع", "الفصلي"))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("الفصل", t.term), y: .value("المعدل", g))
                            .foregroundStyle(by: .value("النوع", "الفصلي"))
                            .symbolSize(30)
                    }
                    if let c = t.cumulativeGPA {
                        LineMark(x: .value("الفصل", t.term), y: .value("المعدل", c), series: .value("النوع", "التراكمي"))
                            .foregroundStyle(by: .value("النوع", "التراكمي"))
                            .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [5, 4]))
                            .interpolationMethod(.catmullRom)
                    }
                }
            }
            .chartForegroundStyleScale(["الفصلي": Brand.green, "التراكمي": Brand.gold])
            .chartYScale(domain: lo...hi)
            .chartLegend(position: .bottom, alignment: .center)
            .frame(height: 170)
            .environment(\.layoutDirection, .leftToRight)
        }
        .healthCard()
    }
}

private struct TermCard: View {
    let term: AcademicTerm
    let previous: AcademicTerm?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(term.semesterName).font(.plex(.headline))
                    Text(verbatim: "\(term.academicYear) · \(term.term)").font(.plex(.footnote)).foregroundStyle(.secondary)
                }
                Spacer()
                if term.honorList {
                    Label("لوحة الشرف", systemImage: "star.fill")
                        .font(.plex(.caption, .bold))
                        .foregroundStyle(Brand.gold)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Brand.gold.opacity(0.14), in: Capsule())
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: gpaText(term.termGPA))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Brand.green)
                Text("المعدل الفصلي").font(.plex(.footnote)).foregroundStyle(.secondary)
                Spacer()
                if let d = delta {
                    HStack(spacing: 3) {
                        Image(systemName: d >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(verbatim: String(format: "%+.1f", d))
                    }
                    .font(.plex(.caption, .bold))
                    .foregroundStyle(d >= 0 ? Color.green : Color.red)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((d >= 0 ? Color.green : Color.red).opacity(0.12), in: Capsule())
                    .accessibilityLabel("تغيّر التراكمي")
                }
            }
            Divider()
            HStack(spacing: 0) {
                metric("التراكمي", gpaText(term.cumulativeGPA))
                metric("ساعات الفصل", intText(term.termHours))
                metric("مجموع الساعات", intText(term.studiedHoursTotal))
            }
        }
        .healthCard()
    }

    /// Change of the cumulative GPA compared with the previous term.
    private var delta: Double? {
        guard let now = term.cumulativeGPA, let before = previous?.cumulativeGPA else { return nil }
        let d = (now - before) * 10
        return d.rounded() / 10
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.plex(.caption)).foregroundStyle(.secondary)
            Text(verbatim: value).font(.plex(.body, .semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PlaceholderTermRow: View {
    let term: AcademicTerm
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("مواد استدراكية").font(.plex(.subheadline, .semibold))
                Text(verbatim: "\(term.term)" + (term.studiedHoursTotal.map { " · \($0) ساعات" } ?? ""))
                    .font(.plex(.caption)).foregroundStyle(.secondary)
            }
            Spacer()
            Text("ما بتدخل بالمعدل").font(.plex(.caption)).foregroundStyle(.secondary)
        }
        .healthCard(padding: 14)
    }
}

// MARK: - المعلومات الأساسية (Settings style)

struct StudentInfoView: View {
    @EnvironmentObject var store: AppStore
    @State private var revealID = false

    var body: some View {
        Group {
            if let info = store.sis.info, !info.isEmpty {
                List {
                    Section {
                        VStack(spacing: 10) {
                            Text(String(info.name.prefix(1)))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(width: 84, height: 84)
                                .background(LinearGradient(colors: [Brand.green, Brand.greenDark], startPoint: .top, endPoint: .bottom), in: Circle())
                            Text(info.name).font(.plex(.title3, .bold)).multilineTextAlignment(.center)
                            if !store.profile.studentNumber.isEmpty {
                                Text(verbatim: store.profile.studentNumber).font(.plex(.subheadline)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            HStack(spacing: 6) {
                                if !info.degree.isEmpty { Pill(text: info.degree, tint: Brand.green) }
                                if let s = info.value("الحالة الاكاديمية") ?? info.value("الحالة الأكاديمية") { Pill(text: s, tint: .blue) }
                            }
                            if !info.department.isEmpty {
                                Text(info.department).font(.plex(.footnote)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.clear)

                    ForEach(info.groups) { group in
                        Section(group.title) {
                            ForEach(group.rows) { row in
                                infoRow(row)
                            }
                        }
                    }

                    Section {
                        EmptyView()
                    } footer: {
                        SISFooter(date: store.sis.updatedAt)
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ScrollView {
                    SISEmptyState(symbol: "person.text.rectangle", title: "معلوماتك الأساسية",
                                  message: "اسمك وتخصصك وكليتك وحالتك الأكاديمية، مرتبة زي الإعدادات.")
                        .padding(16)
                }
                .background(Brand.canvas)
            }
        }
        .navigationTitle("المعلومات الأساسية")
        .navigationBarTitleDisplayMode(.inline)
        .sisRefreshable()
    }

    @ViewBuilder
    private func infoRow(_ row: InfoRow) -> some View {
        let isID = row.label.contains("الرقم الوطني")
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(shortLabel(row.label)).foregroundStyle(.primary)
            Spacer(minLength: 12)
            if isID && !revealID {
                Text(verbatim: String(repeating: "•", count: max(row.value.count - 4, 0)) + row.value.suffix(4))
                    .foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(verbatim: row.value)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .environment(\.layoutDirection, row.value.range(of: "[A-Za-z]", options: .regularExpression) != nil ? .leftToRight : .rightToLeft)
            }
        }
        .font(.plex(.body))
        .contentShape(Rectangle())
        .onTapGesture { if isID { Haptics.select(); withAnimation { revealID.toggle() } } }
        .contextMenu {
            Button { UIPasteboard.general.string = row.value; Haptics.success() } label: { Label("نسخ", systemImage: "doc.on.doc") }
        }
    }

    private func shortLabel(_ l: String) -> String {
        l == "مسار اللغة في خطة متطلبات الجامعة الاختيارية" ? "مسار اللغة (متطلبات الجامعة)" : l
    }
}

// MARK: - موادي هالفصل (registered courses)

struct RegisteredCoursesView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let courses = store.sis.registered, !courses.isEmpty {
                    summary(courses)
                    ForEach(courses.sorted(by: { ($0.from, $0.code) < ($1.from, $1.code) })) { c in
                        RegisteredCourseCard(course: c, tint: store.course(c.compactCode)?.color ?? Brand.green)
                    }
                    SISFooter(date: store.sis.updatedAt)
                } else {
                    SISEmptyState(symbol: "calendar", title: "موادك المسجلة",
                                  message: "كل مادة بكرت: الوقت، الأيام، القاعة والدكتور.")
                }
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("موادي هالفصل")
        .navigationBarTitleDisplayMode(.large)
        .sisRefreshable()
    }

    private func summary(_ courses: [RegisteredCourse]) -> some View {
        let hours = courses.compactMap(\.hours).reduce(0, +)
        let used = Set(courses.flatMap(\.days))
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "\(hours)").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(Brand.green)
                Text("ساعة معتمدة").font(.plex(.subheadline)).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: "\(courses.count) مواد").font(.plex(.subheadline, .semibold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { d in
                    Text(RegisteredCourse.shortDayNames[d])
                        .font(.plex(.caption, .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .foregroundStyle(used.contains(d) ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
                        .background(used.contains(d) ? Brand.green : Color(uiColor: .tertiarySystemFill),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .healthCard()
    }
}

private struct RegisteredCourseCard: View {
    let course: RegisteredCourse
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(tint).frame(width: 5)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: course.code)
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(tint.opacity(0.12), in: Capsule())
                        .environment(\.layoutDirection, .leftToRight)
                    if !course.section.isEmpty {
                        Text(verbatim: "شعبة \(course.section)").font(.plex(.caption)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let h = course.hours {
                        Text(verbatim: h == 0 ? "بدون ساعات" : "\(h) س").font(.plex(.caption, .semibold)).foregroundStyle(.secondary)
                    }
                }
                Text(course.name).font(.plex(.headline))
                HStack(spacing: 14) {
                    Label { Text(verbatim: "\(course.from) – \(course.to)").monospacedDigit() } icon: { Image(systemName: "clock") }
                    if !course.room.isEmpty {
                        Label { Text(verbatim: displayRoom) } icon: { Image(systemName: course.mode.contains("إلكتروني") ? "video" : "mappin.and.ellipse") }
                    }
                }
                .font(.plex(.subheadline)).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ForEach(course.days, id: \.self) { d in
                        Text(RegisteredCourse.shortDayNames[d])
                            .font(.plex(.caption2, .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(tint)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                    if !course.mode.isEmpty {
                        Label(course.mode, systemImage: modeSymbol).font(.plex(.caption)).foregroundStyle(.secondary)
                    }
                }
                if !course.instructor.isEmpty && course.instructor != "غير محدد" {
                    Label(course.instructor, systemImage: "person").font(.plex(.footnote)).foregroundStyle(.secondary)
                }
                if course.cancelled {
                    Label("الشعبة ملغاة", systemImage: "exclamationmark.triangle.fill").font(.plex(.footnote, .semibold)).foregroundStyle(.red)
                }
            }
        }
        .healthCard(padding: 14)
    }

    private var displayRoom: String { course.room == "0 Oline" || course.room.lowercased().contains("online") || course.room.contains("Oline") ? "أونلاين" : course.room }
    private var modeSymbol: String {
        if course.mode.contains("إلكتروني") { return "laptopcomputer" }
        if course.mode.contains("مدمج") { return "rectangle.on.rectangle" }
        return "person.2"
    }
}

// MARK: - العلامات

struct MarksView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let marks = store.sis.marks, !marks.courses.isEmpty {
                    if !marks.term.isEmpty {
                        Text(marks.term).font(.plex(.subheadline, .semibold)).foregroundStyle(.secondary).padding(.horizontal, 4)
                    }
                    ForEach(marks.courses) { c in MarkCard(course: c, tint: store.course(c.code.replacingOccurrences(of: " ", with: ""))?.color ?? Brand.green) }
                } else if store.sis.marks != nil {
                    VStack(spacing: 12) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 28, weight: .semibold)).foregroundStyle(.orange)
                            .frame(width: 62, height: 62).background(.orange.opacity(0.12), in: Circle())
                        Text("لسا ما نزلت علامات هالفصل").font(.plex(.headline))
                        Text(store.sis.marks?.emptyMessage.isEmpty == false ? store.sis.marks!.emptyMessage : "أول ما الدكاترة ينزلوا العلامات على SIS بتطلع هون مرتبة.")
                            .font(.plex(.subheadline)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(24).frame(maxWidth: .infinity)
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    SISEmptyState(symbol: "chart.bar.doc.horizontal", title: "علاماتك",
                                  message: "علامات كل مادة بكرت لحالها، أول ما نحدّث من SIS.")
                }

                if let r = store.sis.record, !r.terms.isEmpty {
                    NavigationLink(value: SISPageRoute(key: "records")) {
                        HStack(spacing: 12) {
                            Image(systemName: "list.bullet.rectangle.portrait").foregroundStyle(.white)
                                .frame(width: 34, height: 34).background(.blue, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("معدلاتك بالفصول السابقة").font(.plex(.subheadline, .semibold)).foregroundStyle(.primary)
                                Text(verbatim: "التراكمي \(gpaText(r.summary.cumulativeGPA))").font(.plex(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.forward").font(.plex(.footnote, .semibold)).foregroundStyle(.tertiary)
                        }
                        .healthCard(padding: 14)
                    }
                    .buttonStyle(PressableStyle())
                }
                SISFooter(date: store.sis.updatedAt)
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("العلامات")
        .navigationBarTitleDisplayMode(.large)
        .sisRefreshable()
    }
}

private struct MarkCard: View {
    let course: CourseMarks
    let tint: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if !course.code.isEmpty {
                        Text(verbatim: course.code).font(.caption.weight(.bold).monospaced()).foregroundStyle(tint)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Text(course.name.isEmpty ? course.code : course.name).font(.plex(.headline))
                }
                Spacer()
                if let m = course.main {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: m.value).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(tint)
                        Text(m.label).font(.plex(.caption2)).foregroundStyle(.secondary)
                    }
                }
            }
            let rest = course.cells.filter { $0 != course.main }
            if !rest.isEmpty {
                Divider()
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                    ForEach(rest, id: \.self) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.label).font(.plex(.caption)).foregroundStyle(.secondary).lineLimit(2)
                            Text(verbatim: c.value).font(.plex(.subheadline, .semibold))
                        }
                    }
                }
            }
        }
        .healthCard()
    }
}

// MARK: - Other SIS pages (e.g. المالية): rows, never a text dump

struct SISGenericPageView: View {
    let key: String
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let page = store.sis.otherPages[key] ?? store.sisPages[key], !(page.pairs.isEmpty && page.tables.isEmpty) {
                    let pairs = page.pairs.filter { $0.count >= 2 && !$0[1].isEmpty }
                    if !pairs.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(pairs.enumerated()), id: \.offset) { idx, pair in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(pair[0]).foregroundStyle(.secondary)
                                    Spacer(minLength: 12)
                                    Text(verbatim: pair[1]).fontWeight(.semibold).multilineTextAlignment(.trailing)
                                }
                                .font(.plex(.subheadline))
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                if idx < pairs.count - 1 { Divider().padding(.leading, 16) }
                            }
                        }
                        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    ForEach(page.tables) { table in
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                            tableRowCard(headers: table.headers, row: row)
                        }
                    }
                    SISFooter(date: page.fetchedAt)
                } else if store.sisLinked && store.sis.updatedAt != nil {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 28, weight: .semibold)).foregroundStyle(Brand.green)
                            .frame(width: 62, height: 62).background(Brand.green.opacity(0.12), in: Circle())
                        Text("هاي الصفحة لسا بنرتبها").font(.plex(.headline))
                        Text("بتقدر تفتحها من الجامعة جوا التطبيق هلأ.").font(.plex(.subheadline)).foregroundStyle(.secondary)
                        Button { Haptics.tap(); router.open("https://sis.yu.edu.jo/ords/", title: title) } label: {
                            Text("افتح صفحة الجامعة").font(.plex(.headline)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered).tint(Brand.green)
                    }
                    .padding(24).frame(maxWidth: .infinity)
                    .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                } else {
                    SISEmptyState(symbol: "building.columns", title: title, message: "بنجيبها من SIS ونرتبها هون.")
                }
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .sisRefreshable()
    }

    private var title: String {
        ["finance": "المالية", "plan": "مواد الخطة", "home": "SIS"][key] ?? "SIS"
    }

    private func tableRowCard(headers: [String], row: [String]) -> some View {
        let cells = Array(zip(headers.indices, row)).filter { !$0.1.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            if let first = cells.first { Text(verbatim: first.1).font(.plex(.body, .semibold)) }
            ForEach(cells.dropFirst(), id: \.0) { idx, value in
                HStack(alignment: .top) {
                    Text(idx < headers.count ? headers[idx] : "").foregroundStyle(.secondary)
                    Spacer(minLength: 10)
                    Text(verbatim: value).multilineTextAlignment(.trailing)
                }
                .font(.plex(.subheadline))
            }
        }
        .healthCard(padding: 14)
    }
}

// MARK: - «ارسل صفحة للمطور»

struct DeveloperExportView: View {
    @State private var files = SISDebugStore.files()

    var body: some View {
        List {
            Section {
                if files.isEmpty {
                    Text("لسا ما في صفحات محفوظة. حدّث SIS أول.").foregroundStyle(.secondary)
                }
                ForEach(files) { f in
                    ShareLink(item: f.url, subject: Text(f.title), message: Text("صفحة \(f.title) من SIS")) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.richtext")
                                .foregroundStyle(.white)
                                .frame(width: 29, height: 29)
                                .background(.indigo, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.title).foregroundStyle(.primary)
                                Text(ArabicFormat.relative(f.date)).font(.plex(.caption)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up").foregroundStyle(Brand.green)
                        }
                    }
                }
            } footer: {
                Text("إذا صفحة طلعت مش مرتبة، ابعتها على الواتساب وبنصلحها بالضبط. الاسم والرقم الوطني والرقم الجامعي مخفيين بالملف.")
            }
        }
        .navigationTitle("ارسل صفحة للمطور")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { files = SISDebugStore.files() }
    }
}
