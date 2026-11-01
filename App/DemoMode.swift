import SwiftUI

/// Launch with `-demo -screen <name>` (simulator only) to render every screen with sample data,
/// so CI can take screenshots. Never active on his phone (no launch arguments there).
enum DemoMode {
    static let args = ProcessInfo.processInfo.arguments
    static var isOn: Bool { args.contains("-demo") }
    static func flag(_ f: String) -> Bool { args.contains(f) }
    static func value(_ key: String) -> String? {
        guard let i = args.firstIndex(of: key), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var screen: String { value("-screen") ?? "home" }

    static let discussions: [ForumDiscussion] = [
        ForumDiscussion(id: "1", subject: "تأجيل محاضرة يوم الثلاثاء", author: "د. سمية الشوابكة", date: "الأحد، 1 تشرين الثاني", url: "https://elearning.yu.edu.jo"),
        ForumDiscussion(id: "2", subject: "موعد الامتحان الأول والمادة المطلوبة", author: "د. سمية الشوابكة", date: "الخميس، 29 تشرين الأول", url: "https://elearning.yu.edu.jo"),
        ForumDiscussion(id: "3", subject: "رابط المحاضرة المسجلة", author: "د. سمية الشوابكة", date: "الثلاثاء، 27 تشرين الأول", url: "https://elearning.yu.edu.jo")
    ]

    static let posts: [ForumPost] = [
        ForumPost(id: "1", author: "د. سمية الشوابكة", date: "الأحد، 1 تشرين الثاني 2026، 9:12 ص", subject: "تأجيل محاضرة يوم الثلاثاء",
                  text: "طلبتي الأعزاء،\nتؤجل محاضرة يوم الثلاثاء إلى يوم الخميس في نفس الموعد والقاعة. يرجى قراءة قصيدة «أنشودة المطر» قبل المحاضرة.\nمع التحية.",
                  attachments: [ForumAttachment(name: "أنشودة المطر.pdf", url: "https://elearning.yu.edu.jo/pluginfile.php/1/a.pdf")])
    ]

    static let assign = AssignInfo(
        intro: "اكتب تحليلاً لقصيدة من الشعر الحر لا يقل عن 600 كلمة، يتناول البنية الإيقاعية والصورة الشعرية.",
        dates: [["فتح", "الأحد، 1 تشرين الثاني 2026"], ["الاستحقاق", "الخميس، 12 تشرين الثاني 2026، 11:59 م"]],
        status: [["حالة التسليم", "لم يتم التسليم"], ["حالة التقييم", "غير مقيّم"], ["الوقت المتبقي", "10 أيام و 4 ساعات"]],
        files: [FolderFile(name: "تعليمات الواجب.docx", url: "https://elearning.yu.edu.jo/pluginfile.php/1/b.docx")])

    static let folderFiles: [FolderFile] = [
        FolderFile(name: "المحاضرة الأولى - مدخل.pdf", url: "https://elearning.yu.edu.jo/pluginfile.php/1/1.pdf"),
        FolderFile(name: "المحاضرة الثانية - الرواد.pptx", url: "https://elearning.yu.edu.jo/pluginfile.php/1/2.pptx"),
        FolderFile(name: "ملخص الوحدة الأولى.docx", url: "https://elearning.yu.edu.jo/pluginfile.php/1/3.docx")
    ]

    static let demoForum = MoodleModule(id: "9001", name: "الإعلانات", kind: "forum", url: "https://elearning.yu.edu.jo/mod/forum/view.php?id=9001")
    static let demoAssign = MoodleModule(id: "9010", name: "تحليل قصيدة من الشعر الحر", kind: "assign", url: "https://elearning.yu.edu.jo/mod/assign/view.php?id=9010")
    static let demoFolder = MoodleModule(id: "9006", name: "محاضرات الوحدة الأولى", kind: "folder", url: "https://elearning.yu.edu.jo/mod/folder/view.php?id=9006")

    @MainActor
    static func install(store: AppStore, router: Router) {
        let cal = Calendar.yarmouk
        let now = Date.now
        store.onboarded = screen != "onboarding"
        if flag("-empty") {
            store.timetable = Timetable.seed
            store.sis = SISData()
            store.moodleLinked = flag("-loading")
            store.sisLinked = false
            store.sections = [:]
            store.deadlines = []; store.notices = []; store.exams = []; store.attendance = []; store.notes = []
            store.profile = StudentProfile(planTotalHours: 132)
            store.lastMoodleSync = nil
            store.planCategories = []
        } else {
            store.profile = StudentProfile(fullName: "طالب تجريبي محمد", firstName: "طالب", studentNumber: "2024000000",
                                           major: "اللغة العربية وآدابها", college: "الآداب", email: "student@yu.edu.jo",
                                           gpa: 84.2, passedHours: 72, inProgressHours: 15, planTotalHours: 132, planPercent: 55)
            store.moodleLinked = true
            store.sisLinked = true
            store.moodleCourses = Timetable.seed.courses.compactMap { c in c.moodleId.map { MoodleCourse(id: $0, fullName: c.name, shortName: c.code, progress: nil) } }
            let reg: [RegisteredCourse] = [
                RegisteredCourse(code: "AR 422", name: "الشعر العربي الحديث", section: "1", hours: 3, from: "09:30", to: "10:30", days: [1, 3, 5], room: "اد 253", mode: "وجاهي", instructor: "د. سمية الشوابكة", cancelled: false),
                RegisteredCourse(code: "HUM 128", name: "المدخل إلى علم الاجتماع", section: "4", hours: 3, from: "10:30", to: "11:30", days: [1, 3], room: "كن 101", mode: "مدمج", instructor: "د. محمد الحراحشة", cancelled: false),
                RegisteredCourse(code: "AR 241", name: "العروض والإيقاع الشعري", section: "2", hours: 3, from: "12:30", to: "01:30", days: [1, 3, 5], room: "اد 118", mode: "وجاهي", instructor: "د. عمر العامري", cancelled: false),
                RegisteredCourse(code: "SCI 108", name: "مهارات حاسوب", section: "7", hours: 3, from: "04:30", to: "05:30", days: [1, 3], room: "", mode: "إلكتروني", instructor: "د. عبير البطاينه", cancelled: false),
                RegisteredCourse(code: "SA 100", name: "الأخلاقيات والعمل التطوعي", section: "1", hours: 0, from: "02:00", to: "03:00", days: [2], room: "قاعة المؤتمرات", mode: "وجاهي", instructor: "", cancelled: false)
            ]
            let terms: [AcademicTerm] = [
                AcademicTerm(term: "2024/1", termGPA: 81.3, cumulativeGPA: 81.3, termHours: 15, studiedHoursTotal: 15, honorList: false),
                AcademicTerm(term: "2024/2", termGPA: 85.6, cumulativeGPA: 83.4, termHours: 18, studiedHoursTotal: 33, honorList: true),
                AcademicTerm(term: "2024/3", termGPA: 88.0, cumulativeGPA: 84.0, termHours: 6, studiedHoursTotal: 39, honorList: false),
                AcademicTerm(term: "2025/1", termGPA: 83.1, cumulativeGPA: 83.8, termHours: 15, studiedHoursTotal: 54, honorList: false),
                AcademicTerm(term: "2025/2", termGPA: 86.2, cumulativeGPA: 84.4, termHours: 15, studiedHoursTotal: 69, honorList: true),
                AcademicTerm(term: "2025/3", termGPA: 80.0, cumulativeGPA: 84.2, termHours: 3, studiedHoursTotal: 72, honorList: false)
            ]
            let info = StudentInfo(name: "طالب تجريبي محمد", degree: "بكالوريوس / عادي", department: "كلية الآداب / قسم اللغة العربية وآدابها",
                                   groups: [InfoGroup(title: "المعلومات الشخصية", rows: [InfoRow(label: "الاسم بالعربية", value: "طالب تجريبي محمد"), InfoRow(label: "الاسم بالانجليزية", value: "TEST STUDENT"), InfoRow(label: "الرقم الوطني", value: "9990000000"), InfoRow(label: "الجنس", value: "ذكر")]),
                                            InfoGroup(title: "الدراسة", rows: [InfoRow(label: "الكلية", value: "الآداب"), InfoRow(label: "التخصص", value: "اللغة العربية وآدابها"), InfoRow(label: "الحالة الاكاديمية", value: "يدرس"), InfoRow(label: "متوقع تخرجه؟", value: "لا")])])
            let marks = MarksPage(term: "الفصل الأول 2026/2027", courses: [
                CourseMarks(code: "AR 422", name: "الشعر العربي الحديث", cells: [MarkCell(label: "الامتحان الأول", value: "24"), MarkCell(label: "المشاركة", value: "9")], main: nil),
                CourseMarks(code: "HUM 128", name: "المدخل إلى علم الاجتماع", cells: [MarkCell(label: "الامتحان الأول", value: "27")], main: nil),
                CourseMarks(code: "AR 241", name: "العروض والإيقاع الشعري", cells: [MarkCell(label: "الامتحان الأول", value: "22")], main: nil)
            ], emptyMessage: "")
            store.sis = SISData(record: AcademicRecord(summary: AcademicSummary(cumulativeGPA: 84.2, cumulativeHours: 72, totalMarks: 6062, passedHours: 72, honorList: "لوحة الشرف"), terms: terms),
                                info: info, registered: reg, marks: marks, otherPages: [:], updatedAt: now.addingTimeInterval(-60 * 14))
            store.syncTimetable(with: reg)
            // e-learning content for AR422
            let ar = 2347
            store.sections[ar] = [
                MoodleSection(id: "s0", number: 0, title: "عام", modules: [
                    demoForum,
                    MoodleModule(id: "9002", name: "موعد المحاضرة: أحد وثلاثاء وخميس 9:30 ص بقاعة اد 253", kind: "label", url: nil),
                    MoodleModule(id: "9003", name: "خطة المادة - الفصل الأول", kind: "resource", url: "https://elearning.yu.edu.jo/mod/resource/view.php?id=9003"),
                    MoodleModule(id: "9004", name: "المحاضرة على Teams", kind: "url", url: "https://elearning.yu.edu.jo/mod/url/view.php?id=9004")
                ]),
                MoodleSection(id: "s1", number: 1, title: "الوحدة الأولى: رواد الشعر الحديث", modules: [
                    MoodleModule(id: "9005", name: "مختارات من شعر السياب", kind: "resource", url: "https://elearning.yu.edu.jo/mod/resource/view.php?id=9005"),
                    demoFolder,
                    MoodleModule(id: "9007", name: "عرض: الشعر الحر وخصائصه", kind: "resource", url: "https://elearning.yu.edu.jo/mod/resource/view.php?id=9007"),
                    demoAssign
                ]),
                MoodleSection(id: "s2", number: 2, title: "الوحدة الثانية: الصورة الشعرية", modules: [
                    MoodleModule(id: "9008", name: "جدول القراءات المطلوبة", kind: "resource", url: "https://elearning.yu.edu.jo/mod/resource/view.php?id=9008"),
                    MoodleModule(id: "9009", name: "تسجيل المحاضرة الثالثة", kind: "url", url: "https://elearning.yu.edu.jo/mod/url/view.php?id=9009")
                ])
            ]
            store.fileKinds = ["9003": .pdf, "9005": .pdf, "9007": .powerpoint, "9008": .spreadsheet]
            store.deadlines = [
                Deadline(id: 1, name: "تحليل قصيدة من الشعر الحر", courseId: 2347, due: now.addingTimeInterval(86400 * 3 + 3600 * 5), url: "https://elearning.yu.edu.jo", kind: "assign", submitted: false, firstSeen: now),
                Deadline(id: 2, name: "تمرين التقطيع العروضي", courseId: 2476, due: now.addingTimeInterval(86400 * 6), url: "https://elearning.yu.edu.jo", kind: "assign", submitted: false, firstSeen: now),
                Deadline(id: 3, name: "كويز إكسل", courseId: 3760, due: now.addingTimeInterval(-86400 * 2), url: "https://elearning.yu.edu.jo", kind: "quiz", submitted: true, firstSeen: now)
            ]
            store.notices = [
                MoodleNotice(id: 1, subject: "إعلان جديد: تأجيل محاضرة يوم الثلاثاء", text: "", url: nil, date: now.addingTimeInterval(-3600 * 2), read: false),
                MoodleNotice(id: 2, subject: "تم فتح واجب: تحليل قصيدة من الشعر الحر", text: "", url: nil, date: now.addingTimeInterval(-3600 * 26), read: false),
                MoodleNotice(id: 3, subject: "تم رصد علامة كويز إكسل", text: "", url: nil, date: now.addingTimeInterval(-3600 * 72), read: true)
            ]
            if let mid = cal.date(byAdding: .day, value: 21, to: now) {
                store.exams = [Exam(courseCode: "AR422", title: "الامتحان النصفي", date: mid, notes: "الوحدة الأولى والثانية"),
                               Exam(courseCode: "AR241", title: "الامتحان الأول", date: mid.addingTimeInterval(86400 * 2))]
            }
            store.attendance = [
                AttendanceMark(courseCode: "AR422", date: now.addingTimeInterval(-86400 * 2), attended: true),
                AttendanceMark(courseCode: "AR422", date: now.addingTimeInterval(-86400 * 4), attended: false),
                AttendanceMark(courseCode: "HUM128", date: now.addingTimeInterval(-86400 * 2), attended: false),
                AttendanceMark(courseCode: "HUM128", date: now.addingTimeInterval(-86400 * 4), attended: false),
                AttendanceMark(courseCode: "AR241", date: now.addingTimeInterval(-86400 * 2), attended: true)
            ]
            store.notes = [
                CourseNote(courseCode: "AR422", kind: .text, text: "السياب ونازك الملائكة رواد الشعر الحر، والقصيدة بتعتمد التفعيلة مش البيت.", date: now.addingTimeInterval(-86400 * 2)),
                CourseNote(courseCode: "AR422", kind: .text, text: "الامتحان من أول 70 صفحة.", date: now.addingTimeInterval(-86400 * 4))
            ]
            store.lastMoodleSync = now.addingTimeInterval(-60 * 6)
        }

        // Screen
        let s = screen
        switch s {
        case "schedule", "schedule_week": router.tab = .schedule
        case "summary": router.tab = .summary
        case "account", "settings": router.tab = .account
        case "search": router.tab = .search
        default: router.tab = .home
        }
        var path = NavigationPath()
        switch s {
        case "course": path.append(CourseRoute(code: "AR422"))
        case "course_teams": path.append(CourseRoute(code: "SCI108"))
        case "records": path.append(SISPageRoute(key: "records"))
        case "info": path.append(SISPageRoute(key: "info"))
        case "marks": path.append(SISPageRoute(key: "marks"))
        case "registered": path.append(SISPageRoute(key: "registered"))
        case "assignments": path.append(AssignmentsRoute())
        case "exams": path.append(ExamsRoute())
        case "plan": path.append(PlanRoute())
        case "poetry": path.append(PoetryRoute())
        case "forum", "discussion", "assignment", "folder", "settings_push", "grades_calc", "export":
            path.append(DemoRoute(name: s))
        default: break
        }
        router.homePath = path
        if s == "notes" { router.notesFor = "AR422" }
        if s == "settings" { router.homePath = NavigationPath(); router.tab = .home; router.homePath.append(DemoRoute(name: "settings_push")) }
    }
}

struct DemoRoute: Hashable { let name: String }

struct DemoScreen: View {
    let name: String
    var body: some View {
        switch name {
        case "forum": ForumView(module: DemoMode.demoForum, tint: Brand.green)
        case "discussion": DiscussionView(discussion: DemoMode.discussions[0], tint: Brand.green)
        case "assignment": AssignmentView(module: DemoMode.demoAssign, tint: Brand.green)
        case "folder": FolderView(module: DemoMode.demoFolder)
        case "grades_calc": GradeCalculatorView()
        case "export": DeveloperExportView()
        default: SettingsView()
        }
    }
}
