import SwiftUI

struct AccountView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    @State private var showSIS = false
    @State private var showMoodle = false
    @State private var confirmSignOut = false

    var body: some View {
        List {
            Section { profileHeader }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

            Section {
                statsGrid
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Section("من نظام معلومات الطلبة") {
                NavigationLink(value: PlanRoute()) { row("chart.pie", "الخطة الدراسية", Brand.green) }
                NavigationLink(value: SISPageRoute(key: "records")) { row("list.bullet.rectangle", "السجل الأكاديمي", .blue) }
                NavigationLink(value: SISPageRoute(key: "marks")) { row("chart.bar.doc.horizontal", "العلامات", .orange) }
                NavigationLink(value: SISPageRoute(key: "schedule")) { row("calendar", "الجدول الدراسي", .purple) }
                NavigationLink(value: SISPageRoute(key: "finance")) { row("creditcard", "المالية", .teal) }
                NavigationLink(value: SISPageRoute(key: "info")) { row("person.text.rectangle", "المعلومات الأساسية", .gray) }
            }

            Section {
                Button { Haptics.tap(); router.open("https://sis.yu.edu.jo/ords/", title: "التسجيل") } label: {
                    row("plus.rectangle.on.rectangle", "تسجيل المواد · سحب وإضافة", .indigo)
                }
                Button { Haptics.tap(); router.open("https://elearning.yu.edu.jo/my/", title: "الايليرنينغ") } label: {
                    row("arrow.up.doc", "رفع واجب على الايليرنينغ", .orange)
                }
            } header: {
                Text("إجراءات رسمية")
            } footer: {
                Text("هدول بيفتحوا صفحة الجامعة نفسها جوا التطبيق، عشان ما يصير أي غلط بتسجيلك.")
            }

            Section("الحسابات") {
                Button { Haptics.tap(); if store.moodleLinked { Task { await store.refreshMoodle() } } else { showMoodle = true } } label: {
                    HStack {
                        row("books.vertical", "الايليرنينغ", Brand.green)
                        Spacer()
                        status(store.moodleLinked && !store.moodleNeedsLogin, store.lastMoodleSync)
                    }
                }
                Button { Haptics.tap(); showSIS = true } label: {
                    HStack {
                        row("building.columns", "SIS", .blue)
                        Spacer()
                        status(store.sisLinked, store.profile.updatedAt)
                    }
                }
            }

            Section {
                NavigationLink { SettingsView() } label: { row("gearshape", "الإعدادات والتنبيهات", .gray) }
                NavigationLink(value: PoetryRoute()) { row("text.quote", "بيت اليوم واختبار البحور", Brand.green) }
                NavigationLink { GradeCalculatorView() } label: { row("function", "كم بدي بالفاينل؟", .pink) }
            }

            Section {
                Button(role: .destructive) { confirmSignOut = true } label: { Text("تسجيل الخروج من كل الحسابات") }
            }
        }
        .navigationTitle("حسابي")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showSIS) { SISLoginSheet() }
        .sheet(isPresented: $showMoodle) { MoodleLoginSheet() }
        .confirmationDialog("متأكد؟ رح ينمسح الدخول من هالجوال.", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("تسجيل الخروج", role: .destructive) { Task { await store.signOut() } }
        }
    }

    private var profileHeader: some View {
        let p = store.profile
        return HStack(spacing: 14) {
            Text(store.avatarLetter)
                .font(.title.bold()).foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Brand.green, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(p.fullName).font(.title3.bold())
                Text(p.studentNumber).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Text([p.major, p.college].filter { !$0.isEmpty }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private var statsGrid: some View {
        let p = store.profile
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                stat("المعدل التراكمي", p.gpa.map { String(format: "%.1f", $0) } ?? "—", Brand.green)
                stat("ساعات مجتازة", p.passedHours.map(String.init) ?? "—", .blue)
            }
            GridRow {
                stat("ضايلك", p.remainingHours.map { "\($0) ساعة" } ?? "—", .orange)
                stat("التخرج تقريباً", p.graduationEstimate ?? "—", .purple)
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
        }
        .healthCard(padding: 14)
    }

    private func row(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 29, height: 29)
                .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title).foregroundStyle(.primary)
        }
    }

    private func status(_ ok: Bool, _ date: Date?) -> some View {
        Text(ok ? (date.map { "محدّث \(ArabicFormat.relative($0))" } ?? "متصل") : "سجّل دخول")
            .font(.footnote).foregroundStyle(ok ? Color.secondary : Color.orange)
    }
}

/// Any SIS page, shown as native cards (label/value pairs + tables as rows).
struct SISPageView: View {
    let key: String
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    @State private var showSIS = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let page = store.sisPages[key] {
                    if !page.pairs.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(page.pairs.enumerated()), id: \.offset) { idx, pair in
                                if pair.count >= 2 {
                                    HStack(alignment: .top) {
                                        Text(pair[0]).foregroundStyle(.secondary)
                                        Spacer(minLength: 12)
                                        Text(pair[1]).fontWeight(.semibold).multilineTextAlignment(.trailing)
                                    }
                                    .font(.subheadline)
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                                    if idx < page.pairs.count - 1 { Divider().padding(.leading, 16) }
                                }
                            }
                        }
                        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    ForEach(page.tables) { table in
                        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                            tableRowCard(headers: table.headers, row: row)
                        }
                    }
                    if page.pairs.isEmpty && page.tables.isEmpty {
                        Text(page.text).font(.subheadline).healthCard()
                    }
                    Text("آخر تحديث \(ArabicFormat.relative(page.fetchedAt))")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Button { Haptics.tap(); router.open(page.url, title: page.title) } label: {
                        Label("افتح الصفحة الأصلية", systemImage: "safari").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    VStack(spacing: 14) {
                        Image(systemName: "building.columns").font(.largeTitle).foregroundStyle(Brand.green)
                        Text("لسا ما جبنا هاي الصفحة من SIS").font(.headline)
                        Text("سجّل دخول SIS (بيجيك رمز SMS) وبنرتبلك كل صفحاتك هون.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("ربط SIS") { Haptics.tap(); showSIS = true }.buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 30)
                    .healthCard()
                }
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.tap(); showSIS = true } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .sheet(isPresented: $showSIS) { SISLoginSheet() }
    }

    private var title: String {
        ["records": "السجل الأكاديمي", "marks": "العلامات", "schedule": "الجدول الدراسي", "finance": "المالية",
         "info": "المعلومات الأساسية", "plan": "الخطة الدراسية", "home": "SIS"][key] ?? "SIS"
    }

    private func tableRowCard(headers: [String], row: [String]) -> some View {
        let cells = Array(zip(headers.indices, row)).filter { !$0.1.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            if let first = cells.first {
                Text(first.1).font(.body.weight(.semibold))
            }
            ForEach(cells.dropFirst(), id: \.0) { idx, value in
                HStack(alignment: .top) {
                    Text(idx < headers.count ? headers[idx] : "").foregroundStyle(.secondary)
                    Spacer(minLength: 10)
                    Text(value).multilineTextAlignment(.trailing)
                }
                .font(.subheadline)
            }
        }
        .healthCard(padding: 14)
    }
}

struct PlanView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSIS = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                let p = store.profile
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(p.passedHours ?? 0) / \(p.planTotalHours) ساعة").font(.largeTitle.bold())
                    ProgressView(value: Double(p.passedHours ?? 0), total: Double(p.planTotalHours)).tint(Brand.green)
                    HStack {
                        if let ip = p.inProgressHours { Pill(text: "\(ip) ساعة هالفصل", tint: .blue) }
                        if let r = p.remainingHours { Pill(text: "ضايل \(r)", tint: .orange) }
                    }
                    if let g = p.graduationEstimate {
                        Text("إذا أخذت 15 ساعة بالفصل بتتخرج تقريباً \(g)").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let e = p.expectedToGraduate { Text("متوقع تخرجه (SIS): \(e)").font(.footnote).foregroundStyle(.secondary) }
                }
                .healthCard()

                if store.planCategories.isEmpty {
                    Button { Haptics.tap(); showSIS = true } label: {
                        EmptyHint(symbol: "arrow.clockwise", text: "حدّث من SIS عشان تظهر تفاصيل الخطة (إجباري/اختياري)")
                            .healthCard()
                    }
                    .buttonStyle(PressableStyle())
                }
                ForEach(store.planCategories) { cat in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(cat.title).font(.body.weight(.semibold))
                            Spacer()
                            if let c = cat.completed, let r = cat.required { Text("\(c)/\(r)").font(.headline.monospacedDigit()) }
                        }
                        if let c = cat.completed, let r = cat.required, r > 0 {
                            ProgressView(value: Double(min(c, r)), total: Double(r)).tint(c >= r ? .green : Brand.green)
                        }
                    }
                    .healthCard(padding: 14)
                }
                NavigationLink(value: SISPageRoute(key: "plan")) {
                    Label("كل مواد الخطة", systemImage: "list.bullet").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("الخطة الدراسية")
        .sheet(isPresented: $showSIS) { SISLoginSheet() }
    }
}
