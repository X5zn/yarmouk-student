import SwiftUI
import QuickLook

// MARK: - Opening files / links from e-learning

@MainActor
final class FileOpener: ObservableObject {
    @Published var preview: URL?
    @Published var error: String?
    @Published var busyKey: String?

    func openFile(key: String, url: URL, title: String) {
        guard busyKey == nil else { return }
        Haptics.tap()
        if let c = FileStore.shared.cached(key) { preview = c; return }
        busyKey = key
        Task {
            defer { busyKey = nil }
            do {
                preview = try await FileStore.shared.fetch(key: key, url: url)
                Haptics.success()
            } catch FileFetchError.notFile {
                Router.shared.open(url.absoluteString, title: title)
            } catch FileFetchError.login {
                Haptics.warning()
                self.error = FileFetchError.login.errorDescription
            } catch {
                Haptics.warning()
                self.error = "ما قدرنا ننزّل الملف هلأ. تأكد من النت وجرّب كمان مرة."
            }
        }
    }

    func openLink(key: String, url: URL, title: String) {
        guard busyKey == nil else { return }
        Haptics.tap()
        busyKey = key
        Task {
            let target = await LinkResolver.resolve(url)
            busyKey = nil
            if LinkResolver.isTeams(target) {
                let ok = await UIApplication.shared.open(target, options: [.universalLinksOnly: true])
                if !ok { Router.shared.open(target.absoluteString, title: title) }
            } else {
                Router.shared.open(target.absoluteString, title: title)
            }
        }
    }
}

struct FileOpenerModifier: ViewModifier {
    @ObservedObject var opener: FileOpener
    func body(content: Content) -> some View {
        content
            .quickLookPreview($opener.preview)
            .alert("ما زبط", isPresented: Binding(get: { opener.error != nil }, set: { if !$0 { opener.error = nil } })) {
                Button("تمام", role: .cancel) {}
            } message: { Text(opener.error ?? "") }
    }
}

extension View {
    func fileOpener(_ o: FileOpener) -> some View { modifier(FileOpenerModifier(opener: o)) }
}

// MARK: - Course page

struct CourseDetailView: View {
    let code: String
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router
    @StateObject private var opener = FileOpener()
    @State private var state: Phase = .idle

    enum Phase { case idle, loading, loaded, needsLogin, failed }

    var course: CourseInfo? { store.course(code) }

    var body: some View {
        ScrollView {
            if let course {
                VStack(alignment: .leading, spacing: 14) {
                    CourseHero(course: course, slots: store.timetable.slots.filter { $0.courseCode == code })
                    actions(course)
                    CourseAttendanceCard(code: code)
                    let dl = store.deadlines.filter { $0.courseId == course.moodleId && course.moodleId != nil }
                    if !dl.isEmpty { deadlinesCard(dl) }
                    let ex = store.upcomingExams.filter { $0.courseCode == code }
                    if !ex.isEmpty { examsCard(ex) }
                    SectionTitle(title: "محتوى المادة")
                    content(course)
                }
                .padding(16)
                .padding(.bottom, 20)
            } else {
                ScreenState(symbol: "book.closed", title: "المادة مش موجودة", message: "ممكن انحذفت من موادك المسجلة. حدّث من SIS.")
                    .padding(.top, 80)
            }
        }
        .background(Brand.canvas)
        .navigationTitle(course?.name ?? code)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let u = course?.moodleURL {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { router.web = WebLink(url: u, title: course?.name ?? "") } label: { Label("افتح صفحة المادة", systemImage: "safari") }
                        Button { Task { await reload(force: true) } } label: { Label("حدّث المحتوى", systemImage: "arrow.clockwise") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .refreshable { await reload(force: true) }
        .task { await reload(force: false) }
        .fileOpener(opener)
        .animation(.snappy, value: state)
    }

    private func reload(force: Bool) async {
        guard let id = course?.moodleId else { return }
        guard store.moodleLinked || DemoMode.isOn else { state = .needsLogin; return }
        if DemoMode.isOn { state = DemoMode.flag("-loading") ? .loading : (store.moodleLinked ? .loaded : .needsLogin); return }
        if store.sections[id] == nil { state = .loading }
        else if !force { state = .loaded }
        let r = await store.loadSections(courseId: id)
        switch r {
        case .ok: state = .loaded
        case .needsLogin: state = store.sections[id] == nil ? .needsLogin : .loaded
        case .failed: state = store.sections[id] == nil ? .failed : .loaded
        }
        if r == .ok && force { Haptics.success() }
    }

    // MARK: actions

    private var modules: [MoodleModule] {
        guard let id = course?.moodleId else { return [] }
        return (store.sections[id] ?? []).flatMap(\.modules)
    }
    private var teamsModule: MoodleModule? {
        modules.first { $0.kind == "url" && ($0.name.localizedCaseInsensitiveContains("teams") || $0.name.contains("تيمز")) }
    }
    private var forumModule: MoodleModule? { modules.first { $0.kind == "forum" } }

    private func actions(_ c: CourseInfo) -> some View {
        HStack(spacing: 4) {
            if let f = forumModule {
                NavigationLink { ForumView(module: f, tint: c.color) } label: { actionLabel("megaphone.fill", "الإعلانات") }
                    .buttonStyle(PressableStyle(scale: 0.92))
            } else {
                QuickAction(symbol: "megaphone.fill", title: "الإعلانات") {
                    if let u = c.moodleURL { router.web = WebLink(url: u, title: c.name) }
                }
            }
            QuickAction(symbol: "mic.fill", title: "ملاحظاتي") { router.openNotes(for: code) }
            if let t = teamsModule, let u = t.url.flatMap({ URL(string: $0) }) {
                QuickAction(symbol: "video.fill", title: "Teams") { opener.openLink(key: t.id, url: u, title: t.name) }
            }
            QuickAction(symbol: "safari.fill", title: "الموقع") {
                if let u = c.moodleURL { router.web = WebLink(url: u, title: c.name) }
            }
        }
        .padding(.vertical, 14)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func actionLabel(_ symbol: String, _ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 54, height: 54)
                .background(Color(uiColor: .systemGray6), in: Circle())
            Text(title).font(.plex(.caption)).foregroundStyle(.primary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: deadlines / exams

    private func deadlinesCard(_ list: [Deadline]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "square.and.pencil", title: "الواجبات", tint: .orange, chevron: false)
            ForEach(list.sorted { $0.due < $1.due }) { d in
                Button { Haptics.tap(); router.open(d.url, title: d.name) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: d.submitted ? "checkmark.circle.fill" : "clock.fill")
                            .font(.title3).foregroundStyle(d.submitted ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.plex(.body, .medium)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            Text("آخر موعد \(ArabicFormat.shortDate(d.due)) · \(ArabicFormat.time(d.due))").font(.plex(.footnote)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Pill(text: d.submitted ? "مسلّم" : ArabicFormat.relative(d.due), tint: d.submitted ? .green : .orange)
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.99))
            }
        }
        .healthCard()
    }

    private func examsCard(_ list: [Exam]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "graduationcap.fill", title: "الامتحانات", tint: .purple, chevron: false)
            ForEach(list) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.plex(.body, .semibold))
                        Text(ArabicFormat.shortDate(e.date) + (e.notes.isEmpty ? "" : " · \(e.notes)"))
                            .font(.plex(.footnote)).foregroundStyle(.secondary).lineLimit(3)
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text("\(max(ArabicFormat.daysLeft(to: e.date), 0))").font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(.purple)
                        Text("يوم").font(.plex(.caption2)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .healthCard()
    }

    // MARK: content

    @ViewBuilder
    private func content(_ c: CourseInfo) -> some View {
        if c.moodleId == nil {
            StateCard(symbol: "link.badge.plus", tint: c.color, title: "المادة مش ظاهرة على الايليرنينغ",
                      message: "لما الدكتور يفتح صفحة المادة بتظهر ملفاتها هون لحالها.")
        } else if let secs = store.sections[c.moodleId!], !secs.isEmpty {
            ForEach(secs) { sec in
                SectionCard(section: sec, tint: c.color, opener: opener)
            }
            UpdatedFooter(source: "الايليرنينغ", date: store.lastMoodleSync)
        } else {
            switch state {
            case .needsLogin:
                MoodleConnectCard(message: "سجّل دخول الايليرنينغ مرة وحدة، وبتظهر هون ملفات المادة وروابطها وواجباتها.")
            case .failed:
                StateCard(symbol: "wifi.exclamationmark", tint: .orange, title: "ما قدرنا نجيب المحتوى",
                          message: "تأكد من النت وجرّب كمان مرة.", actionTitle: "جرّب مرة ثانية") { Task { await reload(force: true) } }
            case .loaded:
                StateCard(symbol: "tray", tint: c.color, title: "ما في محتوى لسا",
                          message: "الدكتور ما نزّل ملفات أو روابط لهاي المادة. أول ما ينزّل بتظهر هون.")
            default:
                SkeletonList(rows: 4)
            }
        }
    }
}

// MARK: - Hero

struct CourseHero: View {
    let course: CourseInfo
    let slots: [LectureSlot]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(verbatim: course.code)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.2), in: Capsule())
                Spacer()
                if course.creditHours > 0 {
                    Text("\(course.creditHours) ساعات").font(.plex(.footnote, .medium)).opacity(0.9)
                }
            }
            Text(course.name).font(.plex(.title2, .bold)).fixedSize(horizontal: false, vertical: true)
            if !course.instructor.isEmpty {
                Label(course.instructor, systemImage: "person.fill").font(.plex(.subheadline, .medium)).opacity(0.92)
            }
            if let first = slots.sorted(by: { $0.weekday < $1.weekday }).first {
                let days = slots.map(\.weekday).sorted { ($0 % 7) < ($1 % 7) }.map { ArabicFormat.dayName($0) }
                // One row when it fits; otherwise days on their own row, then time and room.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        chip("calendar", days.joined(separator: " · "))
                        chip("clock", first.rangeLabel)
                        placeChip(first)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        chip("calendar", days.joined(separator: " · "))
                        HStack(spacing: 6) {
                            chip("clock", first.rangeLabel)
                            placeChip(first)
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [course.color, course.color.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder private func placeChip(_ slot: LectureSlot) -> some View {
        if slot.isOnline { chip("video.fill", "Teams") }
        else if !slot.room.isEmpty { chip("mappin", slot.room) }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.plex(.caption, .medium))
            .lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(.white.opacity(0.18), in: Capsule())
    }
}

// MARK: - Attendance

struct CourseAttendanceCard: View {
    let code: String
    @EnvironmentObject var store: AppStore

    var body: some View {
        let used = store.absences(for: code), limit = store.absenceLimit(for: code)
        let danger = used >= limit
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(symbol: "person.badge.clock.fill", title: "الحضور والغياب", tint: .red, chevron: false)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(used)").font(.system(size: 32, weight: .bold, design: .rounded)).contentTransition(.numericText())
                Text("غياب من \(limit) مسموح").font(.plex(.subheadline)).foregroundStyle(.secondary)
                Spacer()
                if let r = store.attendanceRate(for: code) { Pill(text: "حضور \(Int(r * 100))٪", tint: .green) }
            }
            ProgressView(value: Double(min(used, limit)), total: Double(max(limit, 1)))
                .tint(used >= limit - 1 ? Color.red : Color.orange)
            Text(danger ? "وصلت الحد! انتبه من الحرمان." : "بتقدر تغيب \(max(limit - used, 0)) كمان بأمان (تقريباً).")
                .font(.plex(.footnote)).foregroundStyle(danger ? .red : .secondary)
            HStack(spacing: 10) {
                Button { Haptics.success(); withAnimation(.snappy) { store.markAttendance(code: code, attended: true) } } label: {
                    Label("حضرت اليوم", systemImage: "checkmark").font(.plex(.subheadline, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.bordered).tint(.green).buttonBorderShape(.capsule)
                Button { Haptics.warning(); withAnimation(.snappy) { store.markAttendance(code: code, attended: false) } } label: {
                    Label("غبت اليوم", systemImage: "xmark").font(.plex(.subheadline, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.bordered).tint(.red).buttonBorderShape(.capsule)
            }
        }
        .healthCard()
    }
}

// MARK: - A section of the course

struct SectionCard: View {
    let section: MoodleSection
    let tint: Color
    @ObservedObject var opener: FileOpener
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.plex(.footnote, .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            ForEach(Array(section.modules.enumerated()), id: \.element.id) { idx, m in
                if idx > 0 { Divider().padding(.leading, 62) }
                ModuleRow(module: m, tint: tint, opener: opener, kind: store.fileKinds[m.id])
            }
        }
        .padding(.bottom, 4)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ModuleRow: View {
    let module: MoodleModule
    let tint: Color
    @ObservedObject var opener: FileOpener
    var kind: MoodleFileKind?

    private var isTeams: Bool { module.name.localizedCaseInsensitiveContains("teams") || module.name.contains("تيمز") }

    private var tile: (String, Color) {
        switch module.kind {
        case "resource": let k = kind ?? .generic; return (k.symbol, k.tint)
        case "url": return isTeams ? ("video.fill", Color(red: 0.31, green: 0.33, blue: 0.75)) : ("link", .blue)
        case "folder": return ("folder.fill", .cyan)
        case "assign": return ("square.and.pencil", .orange)
        case "quiz": return ("checklist", .pink)
        case "forum": return ("megaphone.fill", tint)
        case "page": return ("doc.plaintext.fill", .indigo)
        default: return ("square.grid.2x2.fill", .gray)
        }
    }

    private var subtitle: String {
        switch module.kind {
        case "resource": return (kind ?? .generic).label
        case "url": return isTeams ? "محاضرة على Teams" : "رابط"
        default: return module.kindLabel
        }
    }

    var body: some View {
        if module.kind == "label" {
            if !module.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundStyle(tint.opacity(0.8)).padding(.top, 2)
                    Text(module.name).font(.plex(.subheadline)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
        } else if ["forum", "folder", "assign"].contains(module.kind) {
            NavigationLink { destination } label: { row(chevron: true) }
                .buttonStyle(PressableStyle(scale: 0.99))
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        } else {
            Button(action: tap) { row(chevron: module.kind != "resource") }
                .buttonStyle(PressableStyle(scale: 0.99))
                .disabled(module.url == nil)
        }
    }

    @ViewBuilder private var destination: some View {
        switch module.kind {
        case "forum": ForumView(module: module, tint: tint)
        case "folder": FolderView(module: module)
        default: AssignmentView(module: module, tint: tint)
        }
    }

    private func tap() {
        guard let s = module.url, let u = URL(string: s) else { return }
        switch module.kind {
        case "resource": opener.openFile(key: "cm" + module.id, url: u, title: module.name)
        case "url": opener.openLink(key: module.id, url: u, title: module.name)
        default: Haptics.tap(); Router.shared.open(s, title: module.name)
        }
    }

    private func row(chevron: Bool) -> some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: tile.0, tint: tile.1, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.name).font(.plex(.body, .medium)).foregroundStyle(.primary)
                    .multilineTextAlignment(.leading).lineLimit(3)
                Text(subtitle).font(.plex(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if opener.busyKey == module.id || opener.busyKey == "cm" + module.id {
                ProgressView().controlSize(.small)
            } else if module.kind == "resource" {
                Image(systemName: FileStore.shared.cached("cm" + module.id) != nil ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 18)).foregroundStyle(FileStore.shared.cached("cm" + module.id) != nil ? Color.green : tint)
            } else if chevron {
                Image(systemName: "chevron.forward").font(.plex(.footnote, .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

// MARK: - Announcements (forum)

struct ForumView: View {
    let module: MoodleModule
    let tint: Color
    @State private var items: [ForumDiscussion] = []
    @State private var phase: CourseDetailView.Phase = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch phase {
                case .loading, .idle: SkeletonList(rows: 3)
                case .needsLogin: MoodleConnectCard(message: "سجّل دخول الايليرنينغ عشان تظهر الإعلانات.")
                case .failed:
                    StateCard(symbol: "wifi.exclamationmark", tint: .orange, title: "ما قدرنا نجيب الإعلانات",
                              message: "جرّب كمان مرة.", actionTitle: "جرّب مرة ثانية") { Task { await load() } }
                case .loaded:
                    if items.isEmpty {
                        StateCard(symbol: "megaphone", tint: tint, title: "ما في إعلانات لهلأ",
                                  message: "أول ما الدكتور ينزّل إعلان بيظهر هون، وبنبعتلك إشعار.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, d in
                                if i > 0 { Divider().padding(.leading, 62) }
                                NavigationLink { DiscussionView(discussion: d, tint: tint) } label: {
                                    HStack(spacing: 12) {
                                        SymbolTile(symbol: "megaphone.fill", tint: tint, size: 34)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(d.subject).font(.plex(.body, .semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                            Text([d.author, d.date].filter { !$0.isEmpty }.joined(separator: " · "))
                                                .font(.plex(.caption)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.forward").font(.plex(.footnote, .semibold)).foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressableStyle(scale: 0.99))
                            }
                        }
                        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }
            .padding(16)
            .animation(.snappy, value: phase)
        }
        .background(Brand.canvas)
        .navigationTitle("الإعلانات")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { if phase != .loaded { await load() } }
    }

    private func load() async {
        if DemoMode.isOn { items = DemoMode.discussions; phase = .loaded; return }
        guard let s = module.url, let u = URL(string: s) else { phase = .failed; return }
        do {
            items = try await HTMLReader.read(u, script: MoodleScripts.forum, as: [ForumDiscussion].self)
            phase = .loaded
        } catch FileFetchError.login { phase = .needsLogin }
        catch { phase = .failed }
    }
}

struct DiscussionView: View {
    let discussion: ForumDiscussion
    let tint: Color
    @StateObject private var opener = FileOpener()
    @State private var posts: [ForumPost] = []
    @State private var phase: CourseDetailView.Phase = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(discussion.subject).font(.plex(.title3, .bold)).padding(.horizontal, 4)
                switch phase {
                case .loading, .idle: SkeletonList(rows: 2)
                case .needsLogin: MoodleConnectCard(message: "سجّل دخول الايليرنينغ عشان تقرأ الإعلان.")
                case .failed:
                    StateCard(symbol: "wifi.exclamationmark", tint: .orange, title: "ما قدرنا نفتح الإعلان",
                              message: "جرّب كمان مرة.", actionTitle: "جرّب مرة ثانية") { Task { await load() } }
                case .loaded:
                    if posts.isEmpty {
                        StateCard(symbol: "doc.text.magnifyingglass", tint: tint, title: "الإعلان فاضي",
                                  message: "بتقدر تفتحه بالموقع.", actionTitle: "افتحه") { Router.shared.open(discussion.url, title: discussion.subject) }
                    }
                    ForEach(posts) { p in postCard(p) }
                }
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("إعلان")
        .navigationBarTitleDisplayMode(.inline)
        .task { if phase != .loaded { await load() } }
        .fileOpener(opener)
    }

    private func postCard(_ p: ForumPost) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(String(p.author.prefix(1)))
                    .font(.plex(.headline)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(tint.gradient, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.author.isEmpty ? "الدكتور" : p.author).font(.plex(.subheadline, .semibold))
                    if !p.date.isEmpty { Text(p.date).font(.plex(.caption)).foregroundStyle(.secondary) }
                }
            }
            Text(p.text).font(.plex(.body)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            ForEach(p.attachments) { a in
                Button {
                    if let u = URL(string: a.url) { opener.openFile(key: a.url, url: u, title: a.name) }
                } label: {
                    HStack(spacing: 10) {
                        let k = MoodleFileKind(fileName: a.name)
                        SymbolTile(symbol: k.symbol, tint: k.tint, size: 30)
                        Text(a.name.displayFileName).font(.plex(.subheadline, .medium)).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        if opener.busyKey == a.url { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.down.circle").foregroundStyle(tint) }
                    }
                    .padding(10)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle(scale: 0.98))
            }
        }
        .healthCard()
    }

    private func load() async {
        if DemoMode.isOn { posts = DemoMode.posts; phase = .loaded; return }
        guard let u = URL(string: discussion.url) else { phase = .failed; return }
        do {
            posts = try await HTMLReader.read(u, script: MoodleScripts.discussion, as: [ForumPost].self)
            phase = .loaded
        } catch FileFetchError.login { phase = .needsLogin }
        catch { phase = .failed }
    }
}

// MARK: - Folder

struct FolderView: View {
    let module: MoodleModule
    @StateObject private var opener = FileOpener()
    @State private var files: [FolderFile] = []
    @State private var phase: CourseDetailView.Phase = .loading

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch phase {
                case .loading, .idle: SkeletonList(rows: 4)
                case .needsLogin: MoodleConnectCard(message: "سجّل دخول الايليرنينغ عشان تظهر الملفات.")
                case .failed:
                    StateCard(symbol: "wifi.exclamationmark", tint: .orange, title: "ما قدرنا نفتح المجلد",
                              message: "جرّب كمان مرة.", actionTitle: "جرّب مرة ثانية") { Task { await load() } }
                case .loaded:
                    if files.isEmpty {
                        StateCard(symbol: "folder", tint: .cyan, title: "المجلد فاضي", message: "ما في ملفات جوا هالمجلد لهلأ.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(files.enumerated()), id: \.element.id) { i, f in
                                if i > 0 { Divider().padding(.leading, 62) }
                                Button { if let u = URL(string: f.url) { opener.openFile(key: f.url, url: u, title: f.name) } } label: {
                                    HStack(spacing: 12) {
                                        let k = MoodleFileKind(fileName: f.name)
                                        SymbolTile(symbol: k.symbol, tint: k.tint, size: 34)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(f.name.displayFileName).font(.plex(.body, .medium)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                                            Text(k.label).font(.plex(.caption)).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if opener.busyKey == f.url { ProgressView().controlSize(.small) }
                                        else { Image(systemName: "arrow.down.circle").foregroundStyle(Brand.accent) }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 11)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressableStyle(scale: 0.99))
                            }
                        }
                        .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                }
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle(module.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if phase != .loaded { await load() } }
        .refreshable { await load() }
        .fileOpener(opener)
    }

    private func load() async {
        if DemoMode.isOn { files = DemoMode.folderFiles; phase = .loaded; return }
        guard let s = module.url, let u = URL(string: s) else { phase = .failed; return }
        do {
            files = try await HTMLReader.read(u, script: MoodleScripts.folder, as: [FolderFile].self)
            phase = .loaded
        } catch FileFetchError.login { phase = .needsLogin }
        catch { phase = .failed }
    }
}

// MARK: - Assignment

struct AssignmentView: View {
    let module: MoodleModule
    let tint: Color
    @StateObject private var opener = FileOpener()
    @State private var info: AssignInfo?
    @State private var phase: CourseDetailView.Phase = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    SymbolTile(symbol: module.kind == "quiz" ? "checklist" : "square.and.pencil", tint: .orange, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.name).font(.plex(.title3, .bold))
                        Text(module.kindLabel).font(.plex(.subheadline)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
                switch phase {
                case .loading, .idle: SkeletonList(rows: 3)
                case .needsLogin: MoodleConnectCard(message: "سجّل دخول الايليرنينغ عشان تظهر تفاصيل الواجب.")
                case .failed:
                    StateCard(symbol: "wifi.exclamationmark", tint: .orange, title: "ما قدرنا نجيب التفاصيل",
                              message: "بتقدر تفتحه بالموقع مباشرة.", actionTitle: "افتح الواجب") { openSite() }
                case .loaded:
                    if let info { details(info) }
                }
                Button { openSite() } label: {
                    Label("افتح للتسليم", systemImage: "arrow.up.doc.fill")
                        .font(.plex(.body, .semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent).tint(Brand.green).buttonBorderShape(.capsule)
            }
            .padding(16)
        }
        .background(Brand.canvas)
        .navigationTitle("الواجب")
        .navigationBarTitleDisplayMode(.inline)
        .task { if phase != .loaded { await load() } }
        .fileOpener(opener)
    }

    private func openSite() { Haptics.tap(); Router.shared.open(module.url, title: module.name) }

    @ViewBuilder private func details(_ i: AssignInfo) -> some View {
        let rows = (i.dates + i.status).filter { $0.count >= 2 }
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, r in
                    if idx > 0 { Divider().padding(.leading, 16) }
                    HStack(alignment: .top) {
                        Text(r[0]).font(.plex(.subheadline)).foregroundStyle(.secondary)
                        Spacer(minLength: 12)
                        Text(r[1]).font(.plex(.subheadline, .medium)).multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 11)
                }
            }
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        if !i.intro.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                CardHeader(symbol: "text.alignright", title: "المطلوب", tint: tint, chevron: false)
                Text(i.intro).font(.plex(.body)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .healthCard()
        }
        ForEach(i.files) { f in
            Button { if let u = URL(string: f.url) { opener.openFile(key: f.url, url: u, title: f.name) } } label: {
                HStack(spacing: 10) {
                    let k = MoodleFileKind(fileName: f.name)
                    SymbolTile(symbol: k.symbol, tint: k.tint, size: 32)
                    Text(f.name.displayFileName).font(.plex(.subheadline, .medium)).foregroundStyle(.primary).lineLimit(1)
                    Spacer()
                    if opener.busyKey == f.url { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down.circle").foregroundStyle(tint) }
                }
                .healthCard(padding: 12)
            }
            .buttonStyle(PressableStyle(scale: 0.98))
        }
        if rows.isEmpty && i.intro.isEmpty && i.files.isEmpty {
            StateCard(symbol: "doc.text", tint: tint, title: "التفاصيل بالموقع", message: "افتح الواجب لتشوف المطلوب وتسلّم.")
        }
    }

    private func load() async {
        if DemoMode.isOn { info = DemoMode.assign; phase = .loaded; return }
        guard let s = module.url, let u = URL(string: s) else { phase = .failed; return }
        do {
            info = try await HTMLReader.read(u, script: MoodleScripts.assign, as: AssignInfo.self)
            phase = .loaded
        } catch FileFetchError.login { phase = .needsLogin }
        catch { phase = .failed }
    }
}
