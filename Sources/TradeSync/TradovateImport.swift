import Foundation

// MARK: - Tradovate report import
//
// Tradovate does not grant API access to prop-firm or evaluation accounts, so
// accounts at firms like Tradeify are journaled from Tradovate's own reports:
//
//  • Orders export (preferred) — every order with B/S, Contract, Product, Status,
//    Type, Fill Time, Avg Fill Price, Filled Qty, Limit Price, Stop Price.
//    Round-trip trades are rebuilt from the fills, and SL/TP come from the stop
//    and limit orders that were working while the position was open.
//  • Performance export — pre-paired fills (buyPrice/sellPrice/pnl/timestamps).
//    Carries P&L but no account column and no stop/target orders.

enum TradovateImportError: LocalizedError {
    case notTradovate
    case noClosedTrades
    case ambiguousAccount([String])

    var errorDescription: String? {
        switch self {
        case .ambiguousAccount(let numbers):
            return "This export contains several accounts (\(numbers.joined(separator: ", "))). Set the Tradovate account number on this account first."
        case .notTradovate:
            return "This doesn't look like a Tradovate Orders or Performance export."
        case .noClosedTrades:
            return "No closed trades found in this export for the selected account."
        }
    }
}

struct TradovateOrder {
    enum Side { case buy, sell }

    let account: String
    let orderId: String
    let side: Side
    let contract: String
    let product: String
    let status: String        // lowercased: filled / canceled / working / rejected / expired
    let type: String          // lowercased: market / limit / stop / stoplimit / trailingstop
    let filledQty: Double
    let avgFillPrice: Double
    let limitPrice: Double?
    let stopPrice: Double?
    let fillTime: Date?
    let placedTime: Date?

    var isFilled: Bool { status.contains("fill") && filledQty > 0 && avgFillPrice > 0 && fillTime != nil }
    var isStopFamily: Bool { type.contains("stop") || type.contains("trail") }
    var isLimit: Bool { type == "limit" || type == "mit" }
    /// Numeric id when available, for stable ordering of same-second fills.
    var sortKey: Int { Int(orderId.filter(\.isNumber)) ?? 0 }
}

enum TradovateExport {
    case orders([TradovateOrder])
    case performance([PerformancePair])

    struct PerformancePair {
        let symbol: String
        let qty: Double
        let buyPrice: Double
        let sellPrice: Double
        let pnl: Double
        let bought: Date
        let sold: Date
    }

    /// Distinct broker account numbers present (Orders exports only).
    var accountNumbers: Set<String> {
        if case .orders(let rows) = self { return Set(rows.map(\.account).filter { !$0.isEmpty }) }
        return []
    }
}

enum TradovateImporter {

    // MARK: Parse

    static func parse(data: Data) throws -> TradovateExport {
        guard var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw TradovateImportError.notTradovate
        }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let headerLine = lines.first else { throw TradovateImportError.notTradovate }

        let header = CSVImporter.splitCSVLine(headerLine, delimiter: ",").map(normalize)
        let rows = lines.dropFirst().map { CSVImporter.splitCSVLine($0, delimiter: ",") }

        func index(_ names: String...) -> Int? {
            for n in names { if let i = header.firstIndex(of: n) { return i } }
            return nil
        }

        // Orders export
        if let sideIdx = index("b/s"), let contractIdx = index("contract"),
           let statusIdx = index("status"),
           let priceIdx = index("avg fill price", "avgprice") {
            let accountIdx = index("account")
            let idIdx = index("order id", "orderid")
            let productIdx = index("product")
            let typeIdx = index("type")
            let filledIdx = index("filled qty", "filledqty")
            let limitIdx = index("limit price")
            let stopIdx = index("stop price")
            let fillTimeIdx = index("fill time")
            let placedIdx = index("timestamp")

            var orders: [TradovateOrder] = []
            for f in rows {
                func v(_ i: Int?) -> String {
                    guard let i, i < f.count else { return "" }
                    return f[i].trimmingCharacters(in: CharacterSet(charactersIn: " \"\t"))
                }
                let sideRaw = v(sideIdx).lowercased()
                let side: TradovateOrder.Side
                if sideRaw.hasPrefix("b") { side = .buy }
                else if sideRaw.hasPrefix("s") { side = .sell }
                else { continue }
                let contract = v(contractIdx).uppercased()
                guard !contract.isEmpty else { continue }

                let product = v(productIdx).uppercased()
                orders.append(TradovateOrder(
                    account: v(accountIdx),
                    orderId: v(idIdx),
                    side: side,
                    contract: contract,
                    product: product.isEmpty ? Contracts.rootSymbol(of: contract) : product,
                    status: v(statusIdx).lowercased(),
                    type: v(typeIdx).lowercased().replacingOccurrences(of: " ", with: ""),
                    filledQty: number(v(filledIdx)) ?? 0,
                    avgFillPrice: price(v(priceIdx)) ?? 0,
                    limitPrice: price(v(limitIdx)).flatMap { $0 > 0 ? $0 : nil },
                    stopPrice: price(v(stopIdx)).flatMap { $0 > 0 ? $0 : nil },
                    fillTime: date(v(fillTimeIdx)),
                    placedTime: date(v(placedIdx))
                ))
            }
            guard !orders.isEmpty else { throw TradovateImportError.notTradovate }
            return .orders(orders)
        }

        // Performance export
        if let buyIdx = index("buyprice"), let sellIdx = index("sellprice"),
           let boughtIdx = index("boughttimestamp"), let soldIdx = index("soldtimestamp") {
            let symbolIdx = index("symbol")
            let qtyIdx = index("qty")
            let pnlIdx = index("pnl")
            var pairs: [TradovateExport.PerformancePair] = []
            for f in rows {
                func v(_ i: Int?) -> String {
                    guard let i, i < f.count else { return "" }
                    return f[i].trimmingCharacters(in: CharacterSet(charactersIn: " \"\t"))
                }
                guard let buy = price(v(buyIdx)), let sell = price(v(sellIdx)),
                      let bought = date(v(boughtIdx)), let sold = date(v(soldIdx)) else { continue }
                pairs.append(.init(symbol: v(symbolIdx).uppercased(),
                                   qty: number(v(qtyIdx)) ?? 1,
                                   buyPrice: buy, sellPrice: sell,
                                   pnl: money(v(pnlIdx)) ?? 0,
                                   bought: bought, sold: sold))
            }
            guard !pairs.isEmpty else { throw TradovateImportError.notTradovate }
            return .performance(pairs)
        }

        throw TradovateImportError.notTradovate
    }

    // MARK: Build trades

    /// Rebuilds closed trades for one account. Pass `accountNumber: nil` to take
    /// every row (only sensible when the file holds a single account).
    static func trades(from export: TradovateExport, accountNumber: String?,
                       account: TradingAccount) -> [Trade] {
        switch export {
        case .orders(let all):
            let rows = accountNumber.map { n in all.filter { $0.account.caseInsensitiveCompare(n) == .orderedSame } } ?? all
            let byContract = Dictionary(grouping: rows, by: \.contract)
            return byContract.values.flatMap { buildFromOrders($0, account: account) }
                .sorted { $0.exitTime < $1.exitTime }
        case .performance(let pairs):
            return buildFromPerformance(pairs, account: account)
        }
    }

    private struct Leg { let price: Double; let qty: Double; let time: Date; let order: TradovateOrder }

    private static func buildFromOrders(_ orders: [TradovateOrder], account: TradingAccount) -> [Trade] {
        // One filled row per order id.
        var seen = Set<String>()
        let fills = orders.filter(\.isFilled)
            .sorted { ($0.fillTime!, $0.sortKey) < ($1.fillTime!, $1.sortKey) }
            .filter { $0.orderId.isEmpty || seen.insert($0.orderId).inserted }

        var trades: [Trade] = []
        var position = 0.0
        var entries: [Leg] = []
        var exits: [Leg] = []

        func finish() {
            guard let first = entries.first, let last = exits.last else { return }
            let isLong = first.order.side == .buy
            if let t = makeTrade(isLong: isLong, entries: entries, exits: exits,
                                 allOrders: orders, account: account, anchor: first.order, closing: last.order) {
                trades.append(t)
            }
            entries = []
            exits = []
        }

        for f in fills {
            let signed = f.side == .buy ? f.filledQty : -f.filledQty
            let time = f.fillTime!
            if position == 0 {
                entries = [Leg(price: f.avgFillPrice, qty: f.filledQty, time: time, order: f)]
                exits = []
                position = signed
            } else if (position > 0) == (signed > 0) {
                entries.append(Leg(price: f.avgFillPrice, qty: f.filledQty, time: time, order: f))
                position += signed
            } else {
                let closing = min(abs(signed), abs(position))
                exits.append(Leg(price: f.avgFillPrice, qty: closing, time: time, order: f))
                position += signed > 0 ? closing : -closing
                if abs(position) < 1e-9 {
                    position = 0
                    finish()
                    // Reversal: the remainder of this fill opens the opposite position.
                    let leftover = abs(signed) - closing
                    if leftover > 1e-9 {
                        entries = [Leg(price: f.avgFillPrice, qty: leftover, time: time, order: f)]
                        position = signed > 0 ? leftover : -leftover
                    }
                }
            }
        }
        return trades
    }

    private static func makeTrade(isLong: Bool, entries: [Leg], exits: [Leg], allOrders: [TradovateOrder],
                                  account: TradingAccount, anchor: TradovateOrder, closing: TradovateOrder) -> Trade? {
        let entryQty = entries.reduce(0) { $0 + $1.qty }
        let exitQty = exits.reduce(0) { $0 + $1.qty }
        guard entryQty > 0, abs(entryQty - exitQty) < 1e-6 else { return nil }

        let entryValue = entries.reduce(0) { $0 + $1.price * $1.qty }
        let exitValue = exits.reduce(0) { $0 + $1.price * $1.qty }
        let root = anchor.product
        let pointValue = Contracts.pointValue(for: root) ?? Contracts.pointValue(for: anchor.contract) ?? 1
        let direction: Double = isLong ? 1 : -1
        let gross = ((exitValue - entryValue) * direction * pointValue * 100).rounded() / 100
        let commission = -account.commissionPerContractSide * (entryQty + exitQty)

        let entryTime = entries.first!.time
        let exitTime = exits.last!.time
        let exitSide: TradovateOrder.Side = isLong ? .sell : .buy

        // Protective orders working during the trade: the first stop placed is
        // the planned stop; the first opposite-side limit is the planned target.
        let windowStart = entryTime.addingTimeInterval(-5)
        let windowEnd = exitTime.addingTimeInterval(1)
        let protective = allOrders.filter { o in
            o.contract == anchor.contract && o.side == exitSide &&
            (o.placedTime ?? o.fillTime).map { $0 >= windowStart && $0 <= windowEnd } == true
        }.sorted { ($0.placedTime ?? $0.fillTime ?? .distantPast) < ($1.placedTime ?? $1.fillTime ?? .distantPast) }

        var stop = protective.first { $0.isStopFamily && $0.stopPrice != nil }?.stopPrice
        var target = protective.first { $0.isLimit && $0.limitPrice != nil }?.limitPrice
        if stop == nil, closing.isStopFamily { stop = closing.stopPrice ?? closing.avgFillPrice }
        if target == nil, closing.isLimit { target = closing.limitPrice ?? closing.avgFillPrice }

        let accountKey = anchor.account.isEmpty ? account.id.uuidString : anchor.account
        let anchorKey = anchor.orderId.isEmpty ? String(Int(entryTime.timeIntervalSince1970)) : anchor.orderId

        return Trade(
            symbol: root,
            assetClass: .futures,
            direction: isLong ? .long : .short,
            entryTime: entryTime,
            exitTime: exitTime,
            entryPrice: entryValue / entryQty,
            exitPrice: exitValue / exitQty,
            volume: entryQty,
            grossPnL: gross,
            commission: commission,
            stopLoss: stop,
            takeProfit: target,
            source: .tradovate,
            accountLabel: anchor.account,
            externalId: "tdv-\(accountKey)-\(anchorKey)",
            accountId: account.id
        )
    }

    /// Performance rows are single-contract fill pairs; overlapping pairs in the
    /// same symbol and direction belong to one trade.
    private static func buildFromPerformance(_ pairs: [TradovateExport.PerformancePair],
                                             account: TradingAccount) -> [Trade] {
        struct Group { var isLong: Bool; var symbol: String; var pairs: [TradovateExport.PerformancePair]; var lastExit: Date }
        let sorted = pairs.sorted { min($0.bought, $0.sold) < min($1.bought, $1.sold) }
        var groups: [Group] = []
        for p in sorted {
            let isLong = p.bought <= p.sold
            let entry = min(p.bought, p.sold)
            let exit = max(p.bought, p.sold)
            if let i = groups.lastIndex(where: { $0.symbol == p.symbol && $0.isLong == isLong && entry <= $0.lastExit }) {
                groups[i].pairs.append(p)
                groups[i].lastExit = max(groups[i].lastExit, exit)
            } else {
                groups.append(Group(isLong: isLong, symbol: p.symbol, pairs: [p], lastExit: exit))
            }
        }
        return groups.map { g in
            let qty = g.pairs.reduce(0) { $0 + $1.qty }
            let entryPx = g.pairs.reduce(0) { $0 + (g.isLong ? $1.buyPrice : $1.sellPrice) * $1.qty } / qty
            let exitPx = g.pairs.reduce(0) { $0 + (g.isLong ? $1.sellPrice : $1.buyPrice) * $1.qty } / qty
            let entry = g.pairs.map { min($0.bought, $0.sold) }.min()!
            let exit = g.pairs.map { max($0.bought, $0.sold) }.max()!
            let root = Contracts.rootSymbol(of: g.symbol)
            return Trade(
                symbol: root,
                assetClass: .futures,
                direction: g.isLong ? .long : .short,
                entryTime: entry,
                exitTime: exit,
                entryPrice: entryPx,
                exitPrice: exitPx,
                volume: qty,
                grossPnL: g.pairs.reduce(0) { $0 + $1.pnl },
                commission: -account.commissionPerContractSide * qty * 2,
                source: .tradovate,
                accountLabel: account.brokerAccountNumber,
                externalId: "tdvp-\(account.id.uuidString)-\(g.symbol)-\(Int(entry.timeIntervalSince1970))",
                accountId: account.id
            )
        }.sorted { $0.exitTime < $1.exitTime }
    }

    // MARK: Field parsing

    private static func normalize(_ h: String) -> String {
        h.trimmingCharacters(in: CharacterSet(charactersIn: " \"\t\u{FEFF}")).lowercased()
    }

    static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces))
    }

    /// Plain decimals, plus Treasury-style 32nds ("110'16.5" → 110 + 16.5/32).
    static func price(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let tick = t.firstIndex(of: "'") {
            guard let whole = Double(t[..<tick]),
                  let frac = Double(t[t.index(after: tick)...]) else { return nil }
            return whole + frac / 32
        }
        return Double(t)
    }

    /// "$1,250.00", "-$75.50", "$(75.50)" → signed dollars.
    static func money(_ s: String) -> Double? {
        var t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var negative = false
        if t.hasPrefix("(") || t.contains("$(") { negative = true }
        if t.hasPrefix("-") { negative = true }
        t = t.filter { $0.isNumber || $0 == "." }
        guard let v = Double(t) else { return nil }
        return negative ? -v : v
    }

    private static let dateFormatters: [DateFormatter] = [
        "MM/dd/yyyy HH:mm:ss", "MM/dd/yyyy HH:mm:ss.SSS", "M/d/yyyy H:mm:ss", "M/d/yyyy H:mm",
        "MM/dd/yyyy hh:mm:ss a", "M/d/yyyy h:mm:ss a", "MM/dd/yy HH:mm:ss", "M/d/yy H:mm:ss", "M/d/yy H:mm",
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss.SSS"
    ].map { fmt in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current   // Tradovate exports in the user's local time zone
        f.dateFormat = fmt
        return f
    }

    static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let d = MetaApiService.parseDate(t) { return d }
        for f in dateFormatters { if let d = f.date(from: t) { return d } }
        return nil
    }
}