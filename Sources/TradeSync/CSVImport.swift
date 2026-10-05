import Foundation

// MARK: - CSV import
//
// Accepts two shapes:
//  1. TradeSync generic template:
//     symbol,direction,volume,entry_time,entry_price,exit_time,exit_price,pnl,commission,swap
//  2. MetaTrader 5 report exports where columns are auto-detected by header name
//     (Symbol, Type, Volume, Open Time/Price, Close Time/Price, Profit, Commission, Swap).

enum CSVImportError: LocalizedError {
    case empty
    case noHeader
    case missingColumns([String])
    case noRows

    var errorDescription: String? {
        switch self {
        case .empty: return "The file is empty."
        case .noHeader: return "Could not find a header row."
        case .missingColumns(let cols):
            return "Missing required columns: \(cols.joined(separator: ", ")). Expected at minimum: symbol, direction/type, entry time, exit time, and P&L."
        case .noRows: return "No trade rows could be parsed from the file."
        }
    }
}

struct CSVImporter {

    static func parse(data: Data, accountLabel: String) throws -> [Trade] {
        guard var text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16) else { throw CSVImportError.empty }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
                   .replacingOccurrences(of: "\r", with: "\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard !lines.isEmpty else { throw CSVImportError.empty }

        let delimiter: Character = lines[0].contains(";") && !lines[0].contains(",") ? ";" : ","
        let header = splitCSVLine(lines[0], delimiter: delimiter).map {
            $0.lowercased().trimmingCharacters(in: .whitespaces)
        }

        func col(_ candidates: [String]) -> Int? {
            for c in candidates {
                if let i = header.firstIndex(where: { $0 == c || $0.replacingOccurrences(of: " ", with: "_") == c }) {
                    return i
                }
            }
            return nil
        }

        let symbolIdx = col(["symbol", "instrument", "ticker"])
        let dirIdx = col(["direction", "type", "side"])
        let volIdx = col(["volume", "size", "quantity", "qty", "lots"])
        let entryTimeIdx = col(["entry_time", "open_time", "opentime", "time", "entry date", "open date"])
        let entryPriceIdx = col(["entry_price", "open_price", "price", "entry"])
        let exitTimeIdx = col(["exit_time", "close_time", "closetime", "exit date", "close date"])
        let exitPriceIdx = col(["exit_price", "close_price", "exit", "s/l price", "close"])
        let pnlIdx = col(["pnl", "profit", "net_pnl", "p&l", "p/l", "netpl"])
        let commIdx = col(["commission", "fees", "fee"])
        let swapIdx = col(["swap", "rollover"])
        let slIdx = col(["stop_loss", "sl", "s/l", "stop"])
        let tpIdx = col(["take_profit", "tp", "t/p", "target"])

        var missing: [String] = []
        if symbolIdx == nil { missing.append("symbol") }
        if dirIdx == nil { missing.append("direction/type") }
        if entryTimeIdx == nil { missing.append("entry/open time") }
        if pnlIdx == nil { missing.append("pnl/profit") }
        guard missing.isEmpty else { throw CSVImportError.missingColumns(missing) }

        var trades: [Trade] = []
        for raw in lines.dropFirst() {
            let f = splitCSVLine(raw, delimiter: delimiter)
            func str(_ i: Int?) -> String {
                guard let i, i < f.count else { return "" }
                return f[i].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
            func num(_ i: Int?) -> Double? {
                let s = str(i).replacingOccurrences(of: " ", with: "")
                              .replacingOccurrences(of: ",", with: "")
                return Double(s)
            }

            let symbol = str(symbolIdx).uppercased()
            guard !symbol.isEmpty else { continue }

            let dirRaw = str(dirIdx).lowercased()
            let direction: TradeDirection
            if dirRaw.contains("buy") || dirRaw.contains("long") { direction = .long }
            else if dirRaw.contains("sell") || dirRaw.contains("short") { direction = .short }
            else { continue }

            guard let entryTime = parseDate(str(entryTimeIdx)) else { continue }
            let exitTime = parseDate(str(exitTimeIdx)) ?? entryTime
            guard let pnl = num(pnlIdx) else { continue }

            let commission = num(commIdx) ?? 0
            let swap = num(swapIdx) ?? 0
            let volume = num(volIdx) ?? 1
            let entryPrice = num(entryPriceIdx) ?? 0
            let exitPrice = num(exitPriceIdx) ?? 0

            // Content fingerprint keeps re-imports idempotent.
            let fingerprint = "csv-\(symbol)-\(direction.rawValue)-\(Int(entryTime.timeIntervalSince1970))-\(Int(exitTime.timeIntervalSince1970))-\(String(format: "%.2f", pnl))"

            trades.append(Trade(
                symbol: symbol,
                assetClass: MetaApiService.classify(symbol: symbol),
                direction: direction,
                entryTime: entryTime,
                exitTime: exitTime,
                entryPrice: entryPrice,
                exitPrice: exitPrice,
                volume: volume,
                grossPnL: pnl,
                commission: commission > 0 ? -commission : commission,
                swap: swap,
                stopLoss: num(slIdx),
                takeProfit: num(tpIdx),
                source: .csv,
                accountLabel: accountLabel,
                externalId: fingerprint
            ))
        }
        guard !trades.isEmpty else { throw CSVImportError.noRows }
        return trades.sorted { $0.exitTime < $1.exitTime }
    }

    // Handles quoted fields with embedded delimiters.
    static func splitCSVLine(_ line: String, delimiter: Character) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" { inQuotes.toggle(); continue }
            if ch == delimiter && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }

    static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy.MM.dd HH:mm:ss",
        "yyyy.MM.dd HH:mm",
        "yyyy-MM-dd'T'HH:mm:ss",
        "MM/dd/yyyy HH:mm:ss",
        "MM/dd/yyyy HH:mm",
        "dd.MM.yyyy HH:mm:ss",
        "dd.MM.yyyy HH:mm",
        "yyyy-MM-dd"
    ]

    static func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        if let d = MetaApiService.parseDate(s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in dateFormats {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    static var templateCSV: String {
        """
        symbol,direction,volume,entry_time,entry_price,exit_time,exit_price,pnl,commission,swap,stop_loss,take_profit
        EURUSD,buy,1.0,2026-07-01 09:30:00,1.08500,2026-07-01 10:15:00,1.08650,150.00,-7.00,0,1.08400,1.08800
        NQ,sell,2,2026-07-01 14:00:00,21500.00,2026-07-01 14:45:00,21460.00,1600.00,-8.40,0,21530.00,21400.00
        """
    }
}
