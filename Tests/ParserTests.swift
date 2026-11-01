import Foundation

// Parser tests with made-up data in the exact shape SIS prints (run in CI before the build).
var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("✓ \(what)") } else { print("✗ \(what) (line \(line))"); failures += 1 }
}

let recordLines = """
المعدل التراكمي
78.4
مجموع الساعات التراكمية
54
مجموع العلامات التراكمية
4233
مجموع الساعات التي نجح بها الطالب
54
الوضع على لائحة الشرف
2023/0
2023/0
المعدل التراكمي :0 المعدل الفصلي :0
عدد ساعات الفصل 0
مجموع الساعات التي درسها الطالب (6)
2023/1
2023/1
المعدل التراكمي :75.5 المعدل الفصلي :75.5
عدد ساعات الفصل 15
مجموع الساعات التي درسها الطالب (21)
2023/2
2023/2
المعدل التراكمي :79.1 المعدل الفصلي :82.7
عدد ساعات الفصل 15
مجموع الساعات التي درسها الطالب (36) | الوضع على لوحة الشرف: (نعم)
2023/3
2023/3
المعدل التراكمي :78.4 المعدل الفصلي :76.2
عدد ساعات الفصل 6
مجموع الساعات التي درسها الطالب (42)
""".components(separatedBy: "\n")

let r = AcademicRecordParser.parse(lines: recordLines)
check(r.summary.cumulativeGPA == 78.4, "summary GPA")
check(r.summary.cumulativeHours == 54, "summary hours")
check(r.summary.totalMarks == 4233, "summary marks")
check(r.summary.passedHours == 54, "passed hours")
check(r.terms.map(\.term) == ["2023/0", "2023/1", "2023/2", "2023/3"], "terms in order")
check(r.terms[2].termGPA == 82.7 && r.terms[2].cumulativeGPA == 79.1, "term GPAs")
check(r.terms[2].termHours == 15 && r.terms[2].studiedHoursTotal == 36, "term hours")
check(r.terms[2].honorList && !r.terms[1].honorList, "honor list badge")
check(r.terms[0].isPlaceholder && !r.terms[1].isPlaceholder, "remedial term")
check(r.terms[3].semesterName == "الفصل الصيفي" && r.terms[1].academicYear == "2023/2024", "names")

// Same page as one collapsed line, with header/footer around it (what v1 saw).
let blob = "Skip to Main Content نظام معلومات الطلبة " + recordLines.joined(separator: " ") + " جامعة اليرموك - مركز الحاسب والمعلومات"
let r2 = AcademicRecordParser.parse(text: blob)
check(r2 == r, "one-line blob parses the same")

let infoLines = """
اسم تجريبي للطالب
بكالوريوس / عادي
كلية الآداب / قسم اللغة العربية وآدابها
المعلومات الرئيسية
أوقات التسجيل
الاسم بالعربية
اسم تجريبي للطالب
الاسم بالانجليزية
TEST STUDENT NAME
الرقم الوطني
1234567890
الجنس
ذكر
الكلية
الآداب
التخصص
اللغة العربية وآدابها
التخصص الفرعي
التخصص الدقيق
الحالة الاكاديمية
يدرس
متوقع تخرجه؟
لا
""".components(separatedBy: "\n")
let info = StudentInfoParser.parse(pairs: [], lines: infoLines)
check(info.name == "اسم تجريبي للطالب", "info name")
check(info.degree == "بكالوريوس / عادي", "info degree")
check(info.value("التخصص") == "اللغة العربية وآدابها", "major")
check(info.value("التخصص الفرعي") == nil, "empty value is not the next label")
check(info.value("متوقع تخرجه؟") == "لا", "expected graduation")
check(info.groups.first?.title == "المعلومات الشخصية", "groups")

let pairInfo = StudentInfoParser.parse(pairs: [["الكلية", "الآداب", "المعلومات الرئيسية"], ["رقم الهاتف", "07", "المعلومات الرئيسية"]], lines: [])
check(pairInfo.value("الكلية") == "الآداب" && pairInfo.value("رقم الهاتف") == "07", "DOM pairs")

let table = SISExtract.Table(title: "", id: "t", headers: ["رمز المساق","اسم المساق","الشعبة","عدد الساعات","من","الى","خارج الخطة","السبت","الاحد","الإثنين","الثلاثاء","الاربعاء","الخميس","الجمعة","القاعة","الشعبة ملغاة","طريقة تدريس المساق","المدرس","الاسقاط الذاتي للمساق","ساعات المكتب",""],
    rows: [["AR 101","مادة تجريبية","1","3","09:30","10:30","لا"," ","¤"," ","¤"," ","¤"," ","اد 100","لا","وجاهي","دكتور تجريبي","انسحاب","",""],
           ["","","","3","","","","","","","","","","","","","","","","",""]])
let reg = RegisteredCoursesParser.parse(tables: [table])
check(reg.count == 1, "total row skipped")
check(reg.first?.days == [1, 3, 5], "days from ¤ marks")
check(reg.first?.room == "اد 100" && reg.first?.hours == 3 && reg.first?.from == "09:30", "course fields")

let marksTable = SISExtract.Table(title: "", id: "m", headers: ["رمز المساق", "اسم المساق", "الامتحان الأول", "العلامة النهائية"],
                                  rows: [["AR 101", "مادة تجريبية", "25", "88"]])
let marks = MarksParser.parse(tables: [marksTable], lines: ["الاول 2026"])
check(marks.courses.first?.main?.value == "88" && marks.courses.first?.cells.count == 2, "marks")
check(MarksParser.parse(tables: [], lines: ["لا يوجد بيانات"]).emptyMessage == "لا يوجد بيانات", "empty marks message")

check(SISHomeParser.planPercent(lines: ["نسبة إنجازك من الخطة الدراسية", "%", "47"]) == 47, "plan percent")
let masked = SISMask.mask("<b>اسم تجريبي</b> 1234567890 ?session=999", secrets: ["اسم تجريبي للطالب"])
check(!masked.contains("1234567890") && !masked.contains("تجريبي") && masked.contains("session=0"), "masking")

// Times: SIS prints afternoon lectures without AM/PM; the app shows 12-hour with ص/م.
func p(_ s: String) -> String { ClockFormat.parse(s).map { "\($0.0):\($0.1)" } ?? "nil" }
check(p("09:30") == "9:30" && p("10:30") == "10:30" && p("12:30") == "12:30", "morning/noon times")
check(p("04:30") == "16:30" && p("05:30") == "17:30" && p("02:00") == "14:0" && p("01:30") == "13:30", "afternoon times without AM/PM")
check(p("16:30") == "16:30" && p("4:30 م") == "16:30" && p("٠٩:٣٠") == "9:30" && p("12:00 ص") == "0:0" && p("x") == "nil", "explicit and Arabic-digit times")
check(ClockFormat.label(9, 30) == "9:30\u{00A0}ص" && ClockFormat.label(16, 30) == "4:30\u{00A0}م" && ClockFormat.label(12, 30) == "12:30\u{00A0}م", "labels with ص/م")
check(ClockFormat.range(from: "04:30", to: "05:30") == "4:30\u{00A0}م – 5:30\u{00A0}م", "registered course range")

if failures > 0 { print("\(failures) failed"); exit(1) }
print("all parser tests passed")
