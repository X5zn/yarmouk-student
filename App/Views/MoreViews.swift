import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var alarmState = ""
    @State private var cacheText = ""

    var body: some View {
        Form {
            Section {
                Toggle("تذكير قبل المحاضرة", isOn: $store.settings.lectureReminders)
                Stepper("قبلها بـ \(store.settings.lectureReminderMinutes) دقيقة", value: $store.settings.lectureReminderMinutes, in: 5...60, step: 5)
                Toggle("منبه حقيقي (بيرن والجوال صامت)", isOn: $store.settings.useAlarms)
                if !alarmState.isEmpty { Text(alarmState).font(.plex(.footnote)).foregroundStyle(.secondary) }
            } header: { Text("المحاضرات") } footer: {
                Text("المنبه بيستخدم منبهات الآيفون (iOS 26 وأحدث). إذا ما اشتغل على نسختك بنرجع للإشعارات العادية.")
            }
            Section("الإشعارات") {
                Toggle("جدول اليوم الصبح", isOn: $store.settings.morningSummary)
                Toggle("«حضرت؟» بعد كل محاضرة", isOn: $store.settings.attendancePrompts)
                Toggle("تذكير الواجبات (قبل بيوم وبساعة)", isOn: $store.settings.homeworkReminders)
                Toggle("العد التنازلي للامتحانات", isOn: $store.settings.examReminders)
                Toggle("ملخص الأسبوع (الخميس بالليل)", isOn: $store.settings.weeklySummary)
                Toggle("عداد المحاضرة على الجزيرة", isOn: $store.settings.liveActivity)
            }
            Section {
                Toggle("«يلا اطلع» ووصلت الجامعة", isOn: $store.settings.geofence)
            } header: { Text("الموقع") } footer: {
                Text("لما توصل الجامعة بنفرجيك محاضرتك الجاية، وإذا لسا مش بالجامعة قبل أول محاضرة بـ40 دقيقة بنقلك يلا اطلع. بدها إذن الموقع «دائماً».")
            }
            Section {
                Stepper("الحد المسموح للغياب \(Int(store.settings.absenceLimitPercent))٪", value: $store.settings.absenceLimitPercent, in: 5...30, step: 1)
                Stepper("أسابيع الفصل \(store.settings.weeksInSemester)", value: $store.settings.weeksInSemester, in: 10...18)
            } header: { Text("الغياب") } footer: {
                Text("تأكد من النسبة من تعليمات الجامعة أو الدكتور، وعدّلها هون.")
            }
            Section {
                HStack {
                    Label("ملفات المواد المحفوظة", systemImage: "internaldrive")
                    Spacer()
                    Text(cacheText).foregroundStyle(.secondary).monospacedDigit()
                }
                Button(role: .destructive) {
                    Haptics.warning(); FileStore.shared.clear(); cacheText = FileStore.shared.cacheSizeText
                } label: { Label("امسح الملفات المحفوظة", systemImage: "trash") }
            } header: { Text("التخزين") } footer: {
                Text("الملفات اللي فتحتها من الايليرنينغ بتنحفظ عشان تفتح بدون نت. بتنزل من جديد لما تفتحها.")
            }
            Section {
                HStack {
                    Image("YULogo").resizable().scaledToFit().frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("جامعة اليرموك").font(.plex(.body, .semibold))
                        Text("النسخة \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.plex(.caption)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear { cacheText = FileStore.shared.cacheSizeText }
        .navigationTitle("الإعدادات")
        .onChange(of: store.settings) { old, new in
            Haptics.select()
            if new.useAlarms && !old.useAlarms {
                Task {
                    let ok = await AlarmScheduler.shared.requestAccess()
                    alarmState = ok ? "المنبهات شغالة ✅" : "الآيفون ما سمح بالمنبهات، رجعنا للإشعارات"
                    if !ok { store.settings.useAlarms = false }
                    store.rescheduleEverything()
                }
            } else if !new.useAlarms && old.useAlarms {
                Task { await AlarmScheduler.shared.cancelAll() }
                store.rescheduleEverything()
            } else {
                store.rescheduleEverything()
            }
        }
    }
}

// MARK: - Final grade calculator (Yarmouk marks out of 100)

struct GradeCalculatorView: View {
    @State private var soFar: Double = 30
    @State private var outOf: Double = 50
    @State private var target: Double = 70

    var needed: Double {
        let remaining = 100 - outOf
        guard remaining > 0 else { return 0 }
        return max(target - soFar, 0) / remaining * 100
    }

    var body: some View {
        Form {
            Section("لحد هلأ") {
                Stepper("علاماتك: \(Int(soFar))", value: $soFar, in: 0...outOf)
                Stepper("من أصل: \(Int(outOf))", value: $outOf, in: 10...90, step: 5)
            }
            Section("بدك تطلع بـ") {
                Stepper("\(Int(target)) من 100", value: $target, in: 35...100)
            }
            Section {
                VStack(spacing: 6) {
                    Text(needed > 100 ? "صعبة 😅" : "\(Int(needed.rounded(.up)))٪")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(needed > 100 ? .red : Brand.green)
                    Text("من علامة الفاينل (\(Int(100 - outOf)) علامة)").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("كم بدي بالفاينل؟")
        .sensoryFeedback(.selection, trigger: target)
    }
}

// MARK: - Exams

struct ExamsView: View {
    @EnvironmentObject var store: AppStore
    @State private var adding = false

    var body: some View {
        List {
            ForEach(store.exams.sorted { $0.date < $1.date }) { e in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 2).fill(store.course(e.courseCode)?.color ?? .purple).frame(width: 4, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(e.title) · \(store.course(e.courseCode)?.name ?? e.courseCode)").font(.plex(.body, .semibold))
                        Text("\(ArabicFormat.shortDate(e.date)) · \(ArabicFormat.time(e.date))").font(.plex(.footnote)).foregroundStyle(.secondary)
                        if !e.notes.isEmpty { Text(e.notes).font(.plex(.footnote)).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    let d = ArabicFormat.daysLeft(to: e.date)
                    Text(d < 0 ? "خلص" : (d == 0 ? "اليوم" : "\(d) يوم")).font(.plex(.headline)).foregroundStyle(d <= 3 ? .red : .purple)
                }
            }
            .onDelete { idx in
                let sorted = store.exams.sorted { $0.date < $1.date }
                let ids = idx.map { sorted[$0].id }
                store.exams.removeAll { ids.contains($0.id) }
                store.rescheduleEverything()
            }
        }
        .overlay {
            if store.exams.isEmpty {
                VStack(spacing: 14) {
                    ScreenState(symbol: "graduationcap", title: "ما في امتحانات مضافة", message: "ضيف مواعيد امتحاناتك وبنذكرك قبلها بأسبوع، ويوم، وساعة.")
                    Button { Haptics.tap(); adding = true } label: {
                        Label("ضيف امتحان", systemImage: "plus").font(.plex(.body, .semibold)).padding(.horizontal, 18).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.green).buttonBorderShape(.capsule)
                }
            }
        }
        .navigationTitle("الامتحانات")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.tap(); adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) { AddExamSheet() }
    }
}

struct AddExamSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = "AR422"
    @State private var title = "الامتحان النصفي"
    @State private var date = Date.now.addingTimeInterval(86400 * 7)
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("المادة", selection: $code) {
                    ForEach(store.timetable.courses) { Text($0.name).tag($0.code) }
                }
                TextField("نوع الامتحان", text: $title)
                DatePicker("الموعد", selection: $date)
                TextField("ملاحظات (المادة المطلوبة…)", text: $notes, axis: .vertical)
            }
            .navigationTitle("امتحان جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        Haptics.success()
                        store.exams.append(Exam(courseCode: code, title: title, date: date, notes: notes))
                        store.rescheduleEverything()
                        dismiss()
                    }
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

// MARK: - Assignments

struct AssignmentsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router

    var body: some View {
        List {
            let pending = store.pendingDeadlines
            if !pending.isEmpty {
                Section("مطلوب") { ForEach(pending) { row($0) } }
            }
            let done = store.deadlines.filter(\.submitted).sorted { $0.due > $1.due }
            if !done.isEmpty {
                Section("مسلّم") { ForEach(done) { row($0) } }
            }
        }
        .overlay {
            if store.deadlines.isEmpty {
                if store.moodleLinked {
                    ScreenState(symbol: "checkmark.seal", title: "ما عليك واجبات", message: "أول ما الدكتور ينزّل واجب أو كويز بيظهر هون وبنبعتلك إشعار.")
                } else {
                    MoodleConnectCard(message: "الواجبات والكويزات ومواعيد تسليمها بتظهر هون لحالها.").padding(20)
                }
            }
        }
        .navigationTitle("الواجبات")
        .refreshable { await store.refreshMoodle() }
    }

    private func row(_ d: Deadline) -> some View {
        Button { Haptics.tap(); router.open(d.url, title: d.name) } label: {
            HStack {
                Image(systemName: d.submitted ? "checkmark.circle.fill" : "clock.badge.exclamationmark")
                    .foregroundStyle(d.submitted ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(.plex(.body, .medium)).foregroundStyle(.primary)
                    Text("\(store.course(moodleId: d.courseId)?.name ?? "") · \(ArabicFormat.shortDate(d.due)) \(ArabicFormat.time(d.due))")
                        .font(.plex(.footnote)).foregroundStyle(.secondary)
                }
                Spacer()
                if !d.submitted { Text(ArabicFormat.relative(d.due)).font(.plex(.caption, .semibold)).foregroundStyle(.orange) }
            }
        }
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var opener = FileOpener()
    @State private var query = ""

    var body: some View {
        List {
            let q = query.trimmingCharacters(in: .whitespaces)
            let courses = store.timetable.courses.filter { q.isEmpty || $0.name.contains(q) || $0.code.localizedCaseInsensitiveContains(q) || $0.instructor.contains(q) }
            Section("المواد") {
                ForEach(courses) { c in
                    NavigationLink(value: CourseRoute(code: c.code)) {
                        HStack(spacing: 12) {
                            SymbolTile(symbol: "book.closed.fill", tint: c.color, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.name).font(.plex(.body, .medium))
                                Text(c.instructor.isEmpty ? c.code : "\(c.code) · \(c.instructor)").font(.plex(.footnote)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !q.isEmpty {
                let files = store.sections.flatMap { cid, secs in secs.flatMap(\.modules).filter { $0.name.contains(q) }.map { (cid, $0) } }
                if !files.isEmpty {
                    Section("ملفات ومحتوى") {
                        ForEach(files, id: \.1.id) { cid, m in
                            Button {
                                guard let s = m.url, let u = URL(string: s) else { return }
                                if m.kind == "resource" { opener.openFile(key: "cm" + m.id, url: u, title: m.name) }
                                else if m.kind == "url" { opener.openLink(key: m.id, url: u, title: m.name) }
                                else { Haptics.tap(); Router.shared.open(s, title: m.name) }
                            } label: {
                                HStack(spacing: 12) {
                                    let k = store.fileKinds[m.id] ?? .generic
                                    SymbolTile(symbol: m.kind == "resource" ? k.symbol : m.symbol, tint: m.kind == "resource" ? k.tint : Brand.green, size: 30)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(m.name).font(.plex(.body)).foregroundStyle(.primary).lineLimit(2)
                                        Text(store.course(moodleId: cid)?.name ?? m.kindLabel).font(.plex(.caption)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if opener.busyKey == m.id || opener.busyKey == "cm" + m.id { ProgressView().controlSize(.small) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            let q = query.trimmingCharacters(in: .whitespaces)
            if !q.isEmpty && !store.timetable.courses.contains(where: { $0.name.contains(q) || $0.code.localizedCaseInsensitiveContains(q) || $0.instructor.contains(q) })
                && !store.sections.values.contains(where: { $0.contains { $0.modules.contains { $0.name.contains(q) } } }) {
                ScreenState(symbol: "magnifyingglass", title: "ما لقينا «\(q)»", message: "جرّب اسم مادة، دكتور، أو اسم ملف.")
            }
        }
        .navigationTitle("بحث")
        .searchable(text: $query, prompt: "مادة، ملف، دكتور…")
        .fileOpener(opener)
    }
}

// MARK: - Poetry (بيت اليوم + بحر quiz)

struct PoetryView: View {
    @State private var verse = Poetry.verseOfTheDay()
    @State private var choices: [String] = []
    @State private var picked: String?
    @State private var score = 0
    @State private var total = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    Image(systemName: "quote.opening").font(.system(size: 22, weight: .bold)).foregroundStyle(Brand.gold)
                    VStack(spacing: 10) {
                        Text(verse.first)
                        Text(verse.second)
                    }
                    .font(.custom("Amiri-Regular", size: 25, relativeTo: .title2))
                    .lineSpacing(6)
                    .multilineTextAlignment(.center)
                    .id(verse.first)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    Text(verse.poet).font(.plex(.footnote, .medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .healthCard()
                .animation(.snappy, value: verse.first)

                Text("شو بحر هالبيت؟").font(.plex(.headline))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(choices, id: \.self) { c in
                        Button { answer(c) } label: {
                            Text(c).font(.plex(.body, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                                .foregroundStyle(color(for: c) == .clear ? Color.primary : Color.white)
                                .background(color(for: c) == .clear ? Brand.card : color(for: c),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(picked != nil)
                    }
                }
                if picked != nil, let m = Poetry.meter(named: verse.meter) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(verse.poet) · بحر \(m.name)").font(.plex(.headline))
                        Text(m.feet).font(.plex(.subheadline)).foregroundStyle(.secondary)
                        Text(m.key).font(.plex(.footnote)).foregroundStyle(.secondary)
                    }
                    .healthCard()
                    Button { next() } label: {
                        Label("بيت ثاني", systemImage: "arrow.clockwise").font(.plex(.body, .semibold)).padding(.horizontal, 14).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.green).buttonBorderShape(.capsule)
                }
                Text("نتيجتك \(score)/\(total)").font(.plex(.footnote)).foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("بيت اليوم")
        .onAppear { if choices.isEmpty { choices = Poetry.choices(for: verse) } }
    }

    private func color(for c: String) -> Color {
        guard let picked else { return .clear }
        if c == verse.meter { return .green }
        if c == picked { return .red }
        return .clear
    }

    private func answer(_ c: String) {
        picked = c
        total += 1
        if c == verse.meter { score += 1; Haptics.success() } else { Haptics.warning() }
    }

    private func next() {
        Haptics.tap()
        verse = Poetry.verses.filter { $0 != verse }.randomElement() ?? verse
        choices = Poetry.choices(for: verse)
        picked = nil
    }
}
