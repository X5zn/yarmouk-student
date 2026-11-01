import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var alarmState = ""

    var body: some View {
        Form {
            Section {
                Toggle("تذكير قبل المحاضرة", isOn: $store.settings.lectureReminders)
                Stepper("قبلها بـ \(store.settings.lectureReminderMinutes) دقيقة", value: $store.settings.lectureReminderMinutes, in: 5...60, step: 5)
                Toggle("منبه حقيقي (بيرن والجوال صامت)", isOn: $store.settings.useAlarms)
                if !alarmState.isEmpty { Text(alarmState).font(.footnote).foregroundStyle(.secondary) }
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
        }
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
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(e.title) · \(store.course(e.courseCode)?.name ?? e.courseCode)").font(.body.weight(.semibold))
                        Text("\(ArabicFormat.shortDate(e.date)) · \(ArabicFormat.time(e.date))").font(.footnote).foregroundStyle(.secondary)
                        if !e.notes.isEmpty { Text(e.notes).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    let d = ArabicFormat.daysLeft(to: e.date)
                    Text(d < 0 ? "خلص" : (d == 0 ? "اليوم" : "\(d) يوم")).font(.headline).foregroundStyle(d <= 3 ? .red : .purple)
                }
            }
            .onDelete { idx in
                let sorted = store.exams.sorted { $0.date < $1.date }
                let ids = idx.map { sorted[$0].id }
                store.exams.removeAll { ids.contains($0.id) }
                store.rescheduleEverything()
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
            if store.deadlines.isEmpty {
                Text(store.moodleLinked ? "ما في واجبات حالياً" : "سجّل دخول الايليرنينغ من «حسابي»").foregroundStyle(.secondary)
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
                    Text(d.name).foregroundStyle(.primary)
                    Text("\(store.course(moodleId: d.courseId)?.name ?? "") · \(ArabicFormat.shortDate(d.due)) \(ArabicFormat.time(d.due))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if !d.submitted { Text(ArabicFormat.relative(d.due)).font(.caption.weight(.semibold)).foregroundStyle(.orange) }
            }
        }
    }
}

// MARK: - Search

struct SearchView: View {
    @EnvironmentObject var store: AppStore
    @State private var query = ""

    var body: some View {
        List {
            let q = query.trimmingCharacters(in: .whitespaces)
            let courses = store.timetable.courses.filter { q.isEmpty || $0.name.contains(q) || $0.code.localizedCaseInsensitiveContains(q) || $0.instructor.contains(q) }
            Section("المواد") {
                ForEach(courses) { c in
                    NavigationLink(value: CourseRoute(code: c.code)) {
                        VStack(alignment: .leading) { Text(c.name); Text(c.code).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
            if !q.isEmpty {
                let files = store.sections.flatMap { cid, secs in secs.flatMap(\.modules).filter { $0.name.contains(q) }.map { (cid, $0) } }
                if !files.isEmpty {
                    Section("ملفات ومحتوى") {
                        ForEach(files, id: \.1.id) { cid, m in
                            Button { Haptics.tap(); Router.shared.open(m.url, title: m.name) } label: {
                                Label(m.name, systemImage: m.symbol)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("بحث")
        .searchable(text: $query, prompt: "مادة، ملف، دكتور…")
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
                VStack(spacing: 8) {
                    Text(verse.first)
                    Text(verse.second)
                }
                .font(.system(.title2, design: .serif).weight(.medium))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .healthCard()

                Text("شو بحر هالبيت؟").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(choices, id: \.self) { c in
                        Button { answer(c) } label: {
                            Text(c).font(.body.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
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
                        Text("\(verse.poet) · بحر \(m.name)").font(.headline)
                        Text(m.feet).font(.subheadline).foregroundStyle(.secondary)
                        Text(m.key).font(.footnote).foregroundStyle(.secondary)
                    }
                    .healthCard()
                    Button("بيت ثاني") { next() }.buttonStyle(.borderedProminent).tint(Brand.green)
                }
                Text("نتيجتك \(score)/\(total)").font(.footnote).foregroundStyle(.secondary)
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
