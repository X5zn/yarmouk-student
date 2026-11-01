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
                NavigationLink(value: SISPageRoute(key: "registered")) { row("calendar", "موادي هالفصل", .purple) }
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
                Button {
                    Haptics.tap()
                    if store.sisLinked && SISSync.savedSession != nil && !store.sisNeedsLogin {
                        Task { if !(await store.refreshSIS()) { showSIS = true } }
                    } else { showSIS = true }
                } label: {
                    HStack {
                        row("building.columns", "SIS", .blue)
                        Spacer()
                        if store.sisRefreshing { ProgressView() }
                        else { status(store.sisLinked && !store.sisNeedsLogin, store.sis.updatedAt ?? store.profile.updatedAt) }
                    }
                }
            }

            Section {
                NavigationLink { SettingsView() } label: { row("gearshape", "الإعدادات والتنبيهات", .gray) }
                NavigationLink(value: PoetryRoute()) { row("text.quote", "بيت اليوم واختبار البحور", Brand.green) }
                NavigationLink { GradeCalculatorView() } label: { row("function", "كم بدي بالفاينل؟", .pink) }
            }

            Section {
                NavigationLink { DeveloperExportView() } label: { row("paperplane", "ارسل صفحة للمطور", .indigo) }
            } footer: {
                Text("لو صفحة من SIS طلعت مش مرتبة")
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
                if let plan = store.sisPages["plan"], !plan.tables.isEmpty {
                    NavigationLink(value: SISPageRoute(key: "plan")) {
                        Label("كل مواد الخطة", systemImage: "list.bullet").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("الخطة الدراسية")
        .sheet(isPresented: $showSIS) { SISLoginSheet() }
    }
}
