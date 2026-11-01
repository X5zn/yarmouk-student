import Foundation

/// Every time in the app is shown as 12-hour with Arabic ص/م: «9:30 ص», «4:30 م – 5:30 م».
/// Pure Foundation so the CI parser tests can run it.
enum ClockFormat {
    /// The digits only: "9:30", "12:30", "4:30".
    static func number(_ hour: Int, _ minute: Int) -> String {
        let h24 = ((hour % 24) + 24) % 24
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return String(format: "%d:%02d", h12, minute)
    }

    /// "ص" before noon, "م" from 12:00 on.
    static func period(_ hour: Int) -> String {
        (((hour % 24) + 24) % 24) < 12 ? "ص" : "م"
    }

    /// "9:30 ص" (a no-break space keeps the suffix with its number).
    static func label(_ hour: Int, _ minute: Int) -> String {
        number(hour, minute) + "\u{00A0}" + period(hour)
    }

    /// "4:30 م – 5:30 م"
    static func range(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> String {
        label(h1, m1) + " – " + label(h2, m2)
    }

    /// SIS times → 24-hour (hour, minute). SIS prints afternoon lectures with no AM/PM
    /// ("04:30" is 16:30, "02:00" is 14:00); university lectures run 7:00 ص – 7:00 م,
    /// so a bare hour below 7 is afternoon. Explicit ص/م or AM/PM always wins.
    /// Accepts "09:30", "9.30", "16:30", "4:30 م", "٠٤:٣٠".
    static func parse(_ raw: String) -> (Int, Int)? {
        let indic: [Character: Character] = ["٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
                                             "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
                                             "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
                                             "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"]
        let s = String(raw.map { indic[$0] ?? $0 })
        guard let r = s.range(of: #"\d{1,2}\s*[:.٫]\s*\d{2}"#, options: .regularExpression) else { return nil }
        let parts = s[r].split(whereSeparator: { $0 == ":" || $0 == "." || $0 == "٫" })
            .map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, var h = parts[0], let m = parts[1], h < 24, m < 60 else { return nil }
        let rest = s.replacingCharacters(in: r, with: " ").uppercased()
        let pm = rest.contains("م") || rest.contains("PM") || rest.contains("مساء")
        let am = rest.contains("ص") || rest.contains("AM") || rest.contains("صباح")
        if pm {
            if h < 12 { h += 12 }
        } else if am {
            if h == 12 { h = 0 }
        } else if h < 7 {
            h += 12
        }
        return (h, m)
    }

    /// A SIS "from"/"to" pair as «4:30 م – 5:30 م»; the raw text if SIS ever prints something unreadable.
    static func range(from: String, to: String) -> String {
        switch (parse(from), parse(to)) {
        case let (a?, b?): return range(a.0, a.1, b.0, b.1)
        case let (a?, nil): return label(a.0, a.1)
        default: return [from, to].filter { !$0.isEmpty }.joined(separator: " – ")
        }
    }
}
