import Foundation

enum Fmt {
    // Pinned to en_US: accounts are USD-denominated, and a regional locale would
    // render "US$1 234,56" instead of "$1,234.56".
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    static let currencyWhole: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f
    }()

    /// $1,234.56 / -$1,234.56
    static func money(_ v: Double, decimals: Int = 2) -> String {
        let f = decimals == 0 ? currencyWhole : currency
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }

    /// +$1,234.56 with explicit sign for gains
    static func signedMoney(_ v: Double, decimals: Int = 2) -> String {
        let s = money(abs(v), decimals: decimals)
        if v > 0.0001 { return "+\(s)" }
        if v < -0.0001 { return "-\(s)" }
        return s
    }

    static func percent(_ v: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f%%", v)
    }

    static func ratio(_ v: Double) -> String {
        v.isFinite ? String(format: "%.2f", v) : "∞"
    }

    static func rMultiple(_ v: Double) -> String {
        String(format: "%@%.2fR", v >= 0 ? "+" : "", v)
    }

    static func price(_ v: Double) -> String {
        if abs(v) >= 1000 { return String(format: "%.2f", v) }
        if abs(v) >= 10 { return String(format: "%.3f", v) }
        return String(format: "%.5f", v)
    }

    static func volume(_ v: Double) -> String {
        v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.2f", v)
    }

    /// Plain editable number — no trailing zeros, for pre-filling text fields.
    static func plain(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e9 { return String(format: "%.0f", v) }
        var s = String(format: "%.5f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    static let dayKey: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    static let weekdayDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        return f
    }()

    static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    static let shortTimeHM: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy HH:mm"
        return f
    }()

    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    static func duration(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        if s < 86400 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        return "\(s / 86400)d \((s % 86400) / 3600)h"
    }
}

extension Date {
    var dayKey: String { Fmt.dayKey.string(from: self) }
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}
