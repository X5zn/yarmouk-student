import Foundation

struct Verse: Codable, Hashable, Identifiable {
    var first: String
    var second: String
    var poet: String
    var meter: String
    var id: String { first }
}

struct Meter: Hashable {
    var name: String
    var feet: String
    var key: String   // مفتاح البحر (صفي الدين الحلي)
}

enum Poetry {
    static let meters: [Meter] = [
        Meter(name: "الطويل", feet: "فعولن مفاعيلن فعولن مفاعلن", key: "طويلٌ له دون البحور فضائلُ ... فعولن مفاعيلن فعولن مفاعلُ"),
        Meter(name: "البسيط", feet: "مستفعلن فاعلن مستفعلن فعلن", key: "إنّ البسيطَ لديه يُبسَطُ الأملُ ... مستفعلن فعلن مستفعلن فعلُ"),
        Meter(name: "الوافر", feet: "مفاعلتن مفاعلتن فعولن", key: "بحورُ الشعرِ وافرُها جميلُ ... مفاعلتن مفاعلتن فعولُ"),
        Meter(name: "الكامل", feet: "متفاعلن متفاعلن متفاعلن", key: "كمُلَ الجمالُ من البحورِ الكاملُ ... متفاعلن متفاعلن متفاعلُ"),
        Meter(name: "المتقارب", feet: "فعولن فعولن فعولن فعولن", key: "عن المتقاربِ قال الخليلُ ... فعولن فعولن فعولن فعولُ"),
        Meter(name: "الخفيف", feet: "فاعلاتن مستفع لن فاعلاتن", key: "يا خفيفاً خفّتْ به الحركاتُ ... فاعلاتن مستفعلن فاعلاتُ"),
        Meter(name: "المتدارك", feet: "فاعلن فاعلن فاعلن فاعلن (الخبب: فَعِلن)", key: "حركاتُ المُحدَثِ تنتقلُ ... فعِلن فعِلن فعِلن فعِلُ")
    ]

    static func meter(named name: String) -> Meter? { meters.first { $0.name == name } }

    static let verses: [Verse] = [
        Verse(first: "الخيلُ والليلُ والبيداءُ تعرفني", second: "والسيفُ والرمحُ والقرطاسُ والقلمُ", poet: "المتنبي", meter: "البسيط"),
        Verse(first: "على قدرِ أهلِ العزمِ تأتي العزائمُ", second: "وتأتي على قدرِ الكرامِ المكارمُ", poet: "المتنبي", meter: "الطويل"),
        Verse(first: "قفا نبكِ من ذكرى حبيبٍ ومنزلِ", second: "بسِقطِ اللِّوى بين الدَّخولِ فحَوملِ", poet: "امرؤ القيس", meter: "الطويل"),
        Verse(first: "إذا الشعبُ يوماً أرادَ الحياةَ", second: "فلا بدَّ أن يستجيبَ القدرْ", poet: "أبو القاسم الشابي", meter: "المتقارب"),
        Verse(first: "أراكَ عصيَّ الدمعِ شيمتُكَ الصبرُ", second: "أما للهوى نهيٌ عليكَ ولا أمرُ", poet: "أبو فراس الحمداني", meter: "الطويل"),
        Verse(first: "لكلِّ شيءٍ إذا ما تمَّ نقصانُ", second: "فلا يُغَرَّ بطيبِ العيشِ إنسانُ", poet: "أبو البقاء الرندي", meter: "البسيط"),
        Verse(first: "ألا ليتَ الشبابَ يعودُ يوماً", second: "فأخبرَهُ بما فعلَ المشيبُ", poet: "أبو العتاهية", meter: "الوافر"),
        Verse(first: "أنا الذي نظرَ الأعمى إلى أدبي", second: "وأسمعتْ كلماتي مَن بهِ صممُ", poet: "المتنبي", meter: "البسيط"),
        Verse(first: "إذا غامرتَ في شرفٍ مَرومِ", second: "فلا تقنعْ بما دونَ النجومِ", poet: "المتنبي", meter: "الوافر"),
        Verse(first: "قمْ للمعلّمِ وفِّهِ التبجيلا", second: "كادَ المعلّمُ أن يكونَ رسولا", poet: "أحمد شوقي", meter: "الكامل"),
        Verse(first: "هل غادرَ الشعراءُ من متردَّمِ", second: "أم هل عرفتَ الدارَ بعدَ توهُّمِ", poet: "عنترة بن شداد", meter: "الكامل"),
        Verse(first: "بانتْ سعادُ فقلبي اليومَ متبولُ", second: "متيَّمٌ إثرَها لم يُفدَ مكبولُ", poet: "كعب بن زهير", meter: "البسيط"),
        Verse(first: "أعزُّ مكانٍ في الدُّنى سرجُ سابحٍ", second: "وخيرُ جليسٍ في الزمانِ كتابُ", poet: "المتنبي", meter: "الطويل"),
        Verse(first: "دعِ الأيامَ تفعلُ ما تشاءُ", second: "وطِبْ نفساً إذا حكمَ القضاءُ", poet: "الإمام الشافعي", meter: "الوافر"),
        Verse(first: "إذا المرءُ لم يَدنَسْ من اللؤمِ عرضُهُ", second: "فكلُّ رداءٍ يرتديهِ جميلُ", poet: "السموأل", meter: "الطويل"),
        Verse(first: "يا أعدلَ الناسِ إلا في معاملتي", second: "فيكَ الخصامُ وأنتَ الخصمُ والحكمُ", poet: "المتنبي", meter: "البسيط"),
        Verse(first: "أخي جاوزَ الظالمونَ المدى", second: "فحقَّ الجهادُ وحقَّ الفِدا", poet: "علي محمود طه", meter: "المتقارب"),
        Verse(first: "وطني لو شُغِلتُ بالخلدِ عنهُ", second: "نازعتني إليهِ في الخلدِ نفسي", poet: "أحمد شوقي", meter: "الخفيف"),
        Verse(first: "عشْ عزيزاً أو متْ وأنتَ كريمٌ", second: "بينَ طعنِ القنا وخفقِ البنودِ", poet: "المتنبي", meter: "الخفيف"),
        Verse(first: "يا ليلُ الصبُّ متى غدُهُ", second: "أقيامُ الساعةِ موعدُهُ", poet: "الحصري القيرواني", meter: "المتدارك"),
        Verse(first: "ومَن لم يصانعْ في أمورٍ كثيرةٍ", second: "يُضرَّسْ بأنيابٍ ويوطأْ بمَنسِمِ", poet: "زهير بن أبي سلمى", meter: "الطويل"),
        Verse(first: "سلوا قلبي غداةَ سلا وتابا", second: "لعلَّ على الجمالِ لهُ عتابا", poet: "أحمد شوقي", meter: "الوافر")
    ]

    /// Same verse all day, changes at midnight (Amman).
    static func verseOfTheDay(_ date: Date = .now) -> Verse {
        let day = Calendar.yarmouk.ordinality(of: .day, in: .era, for: date) ?? 0
        return verses[day % verses.count]
    }

    /// Four meter choices (the right one + three others), stable for the verse.
    static func choices(for verse: Verse) -> [String] {
        var others = meters.map(\.name).filter { $0 != verse.meter }
        others.shuffle()
        var picked = Array(others.prefix(3)) + [verse.meter]
        picked.shuffle()
        return picked
    }
}
