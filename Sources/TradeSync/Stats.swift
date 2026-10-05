import Foundation

// MARK: - Day aggregation

struct DayStats: Identifiable {
    var id: String { dayKey }
    let dayKey: String
    let date: Date
    let trades: [Trade]
    let netPnL: Double
    let cumulativePnL: Double     // running total up to & including this day
    var tradeCount: Int { trades.count }
    var winCount: Int { trades.filter { $0.result == .win }.count }
    var volume: Double { trades.reduce(0) { $0 + $1.volume } }
    var winRate: Double { trades.isEmpty ? 0 : Double(winCount) / Double(trades.count) * 100 }
}

// MARK: - Edge Score (Zella Score methodology)
// 6 components, each scored 0-100, weighted:
//   Profit Factor 25%, Avg Win/Loss 20%, Max Drawdown 20%,
//   Win % 15%, Recovery Factor 10%, Consistency 10%

struct EdgeScore {
    let winRateScore: Double
    let profitFactorScore: Double
    let avgWinLossScore: Double
    let maxDrawdownScore: Double
    let recoveryFactorScore: Double
    let consistencyScore: Double

    var total: Double {
        profitFactorScore * 0.25
        + avgWinLossScore * 0.20
        + maxDrawdownScore * 0.20
        + winRateScore * 0.15
        + recoveryFactorScore * 0.10
        + consistencyScore * 0.10
    }

    var axes: [(label: String, value: Double)] {
        [("Win %", winRateScore),
         ("Profit Factor", profitFactorScore),
         ("Avg Win/Loss", avgWinLossScore),
         ("Recovery", recoveryFactorScore),
         ("Consistency", consistencyScore),
         ("Drawdown", maxDrawdownScore)]
    }
}

// MARK: - Stats engine

struct Stats {
    let trades: [Trade]           // sorted by exitTime ascending
    let days: [DayStats]          // sorted by date ascending

    // Headline
    let netPnL: Double
    let grossProfit: Double       // sum of winners (net)
    let grossLoss: Double         // abs sum of losers (net)
    let totalFees: Double
    let winCount: Int
    let lossCount: Int
    let breakevenCount: Int
    let tradeWinRate: Double      // %
    let dayWinRate: Double        // %
    let profitFactor: Double
    let avgWin: Double
    let avgLoss: Double           // positive magnitude
    let avgWinLossRatio: Double
    let expectancy: Double
    let largestWin: Double
    let largestLoss: Double
    let avgTradePnL: Double
    let maxDrawdown: Double       // positive $ magnitude
    let maxDrawdownPct: Double    // % of peak
    let maxDrawdownDate: Date?
    let recoveryFactor: Double
    let currentDayStreak: Int     // + winning days in a row, - losing
    let currentTradeStreak: Int
    let bestDayStreak: Int        // longest run of winning days ever
    let bestTradeStreak: Int
    let avgHoldWinners: TimeInterval
    let avgHoldLosers: TimeInterval
    let edge: EdgeScore

    var totalTrades: Int { trades.count }
    var winningDays: Int { days.filter { $0.netPnL > 0.0001 }.count }
    var losingDays: Int { days.filter { $0.netPnL < -0.0001 }.count }

    init(trades rawTrades: [Trade]) {
        let sorted = rawTrades.sorted { $0.exitTime < $1.exitTime }
        self.trades = sorted

        // ---- daily buckets
        var byDay: [String: [Trade]] = [:]
        for t in sorted { byDay[t.exitTime.dayKey, default: []].append(t) }
        let orderedKeys = byDay.keys.sorted()
        var running: Double = 0
        var dayList: [DayStats] = []
        for key in orderedKeys {
            let dayTrades = byDay[key] ?? []
            let pnl = dayTrades.reduce(0) { $0 + $1.netPnL }
            running += pnl
            let date = Fmt.dayKey.date(from: key) ?? Date()
            dayList.append(DayStats(dayKey: key, date: date, trades: dayTrades,
                                    netPnL: pnl, cumulativePnL: running))
        }
        self.days = dayList

        // ---- headline numbers
        let winners = sorted.filter { $0.result == .win }
        let losers = sorted.filter { $0.result == .loss }
        let be = sorted.filter { $0.result == .breakeven }

        netPnL = sorted.reduce(0) { $0 + $1.netPnL }
        grossProfit = winners.reduce(0) { $0 + $1.netPnL }
        grossLoss = abs(losers.reduce(0) { $0 + $1.netPnL })
        totalFees = sorted.reduce(0) { $0 + $1.fees }
        winCount = winners.count
        lossCount = losers.count
        breakevenCount = be.count

        let n = sorted.count
        tradeWinRate = n == 0 ? 0 : Double(winners.count) / Double(n) * 100
        let winDays = dayList.filter { $0.netPnL > 0.0001 }.count
        dayWinRate = dayList.isEmpty ? 0 : Double(winDays) / Double(dayList.count) * 100

        profitFactor = grossLoss > 0 ? grossProfit / grossLoss : (grossProfit > 0 ? .infinity : 0)
        avgWin = winners.isEmpty ? 0 : grossProfit / Double(winners.count)
        avgLoss = losers.isEmpty ? 0 : grossLoss / Double(losers.count)
        avgWinLossRatio = avgLoss > 0 ? avgWin / avgLoss : (avgWin > 0 ? .infinity : 0)
        expectancy = n == 0 ? 0 : netPnL / Double(n)
        largestWin = winners.map(\.netPnL).max() ?? 0
        largestLoss = losers.map(\.netPnL).min() ?? 0
        avgTradePnL = n == 0 ? 0 : netPnL / Double(n)

        // ---- drawdown on daily cumulative equity
        var peak: Double = 0
        var maxDD: Double = 0
        var maxDDPct: Double = 0
        var ddDate: Date? = nil
        for d in dayList {
            peak = max(peak, d.cumulativePnL)
            let dd = peak - d.cumulativePnL
            if dd > maxDD {
                maxDD = dd
                ddDate = d.date
                maxDDPct = peak > 0 ? dd / peak * 100 : 0
            }
        }
        maxDrawdown = maxDD
        maxDrawdownPct = maxDDPct
        maxDrawdownDate = ddDate
        recoveryFactor = maxDD > 0 ? netPnL / maxDD : (netPnL > 0 ? .infinity : 0)

        // ---- streaks (from most recent backwards)
        func streak<T>(_ items: [T], sign: (T) -> Int) -> Int {
            var s = 0
            for item in items.reversed() {
                let v = sign(item)
                if v == 0 { continue }
                if s == 0 { s = v }
                else if (s > 0 && v > 0) || (s < 0 && v < 0) { s += v }
                else { break }
            }
            return s
        }
        currentTradeStreak = streak(sorted) { $0.netPnL > 0.0001 ? 1 : ($0.netPnL < -0.0001 ? -1 : 0) }
        currentDayStreak = streak(dayList) { $0.netPnL > 0.0001 ? 1 : ($0.netPnL < -0.0001 ? -1 : 0) }

        // Longest winning run, scanning forward. Breakevens don't break a streak.
        func bestRun<T>(_ items: [T], isWin: (T) -> Int) -> Int {
            var best = 0, run = 0
            for item in items {
                switch isWin(item) {
                case 1: run += 1; best = max(best, run)
                case -1: run = 0
                default: break
                }
            }
            return best
        }
        bestTradeStreak = bestRun(sorted) { $0.netPnL > 0.0001 ? 1 : ($0.netPnL < -0.0001 ? -1 : 0) }
        bestDayStreak = bestRun(dayList) { $0.netPnL > 0.0001 ? 1 : ($0.netPnL < -0.0001 ? -1 : 0) }

        avgHoldWinners = winners.isEmpty ? 0 : winners.reduce(0) { $0 + $1.duration } / Double(winners.count)
        avgHoldLosers = losers.isEmpty ? 0 : losers.reduce(0) { $0 + $1.duration } / Double(losers.count)

        // ---- Edge score components
        edge = Stats.edgeScore(
            winRate: tradeWinRate,
            profitFactor: profitFactor,
            avgWinLoss: avgWinLossRatio,
            maxDrawdownPct: maxDrawdownPct,
            recoveryFactor: recoveryFactor,
            days: dayList,
            netPnL: netPnL,
            hasTrades: n > 0
        )
    }

    /// TradeZella-published scoring bands.
    static func edgeScore(winRate: Double, profitFactor: Double, avgWinLoss: Double,
                          maxDrawdownPct: Double, recoveryFactor: Double,
                          days: [DayStats], netPnL: Double, hasTrades: Bool) -> EdgeScore {
        guard hasTrades else {
            return EdgeScore(winRateScore: 0, profitFactorScore: 0, avgWinLossScore: 0,
                             maxDrawdownScore: 0, recoveryFactorScore: 0, consistencyScore: 0)
        }

        // Win % : (win% / 60) * 100, capped at 100
        let winScore = min(100, winRate / 60.0 * 100)

        // Ratio bands used for both Profit Factor and Avg Win/Loss:
        // 2.6+ =100 | 2.4-2.59 =90-99 | 2.2-2.39 =80-89 | 2.0-2.19 =70-79
        // 1.9-1.99 =60-69 | 1.8-1.89 =50-59 | <1.8 scaled up to 50
        func ratioScore(_ r: Double) -> Double {
            guard r.isFinite else { return 100 }
            switch r {
            case 2.6...: return 100
            case 2.4..<2.6: return 90 + (r - 2.4) / 0.2 * 9
            case 2.2..<2.4: return 80 + (r - 2.2) / 0.2 * 9
            case 2.0..<2.2: return 70 + (r - 2.0) / 0.2 * 9
            case 1.9..<2.0: return 60 + (r - 1.9) / 0.1 * 9
            case 1.8..<1.9: return 50 + (r - 1.8) / 0.1 * 9
            default: return max(0, r / 1.8 * 50)
            }
        }

        // Max drawdown: 100 - drawdown%
        let ddScore = max(0, min(100, 100 - maxDrawdownPct))

        // Recovery factor bands:
        // 3.5+ =100 | 3.0-3.49 =70-89 | 2.5-2.99 =60-69 | 2.0-2.49 =50-59
        // 1.5-1.99 =30-49 | 1.0-1.49 =1-29 | <1.0 =0
        func recoveryScore(_ r: Double) -> Double {
            guard r.isFinite else { return 100 }
            switch r {
            case 3.5...: return 100
            case 3.0..<3.5: return 70 + (r - 3.0) / 0.5 * 19
            case 2.5..<3.0: return 60 + (r - 2.5) / 0.5 * 9
            case 2.0..<2.5: return 50 + (r - 2.0) / 0.5 * 9
            case 1.5..<2.0: return 30 + (r - 1.5) / 0.5 * 19
            case 1.0..<1.5: return 1 + (r - 1.0) / 0.5 * 28
            default: return 0
            }
        }

        // Consistency: 100 - (stddev of daily P&L / |total profit|) * 100, clamped
        var consistency: Double = 0
        if days.count > 1, abs(netPnL) > 0 {
            let mean = days.reduce(0) { $0 + $1.netPnL } / Double(days.count)
            let variance = days.reduce(0) { $0 + pow($1.netPnL - mean, 2) } / Double(days.count)
            let sd = sqrt(variance)
            consistency = max(0, min(100, 100 - (sd / abs(netPnL)) * 100))
        } else if days.count == 1 && netPnL > 0 {
            consistency = 50
        }

        return EdgeScore(
            winRateScore: winScore,
            profitFactorScore: ratioScore(profitFactor),
            avgWinLossScore: ratioScore(avgWinLoss),
            maxDrawdownScore: ddScore,
            recoveryFactorScore: recoveryScore(recoveryFactor),
            consistencyScore: consistency
        )
    }
}

// MARK: - Report groupings

struct BucketStat: Identifiable {
    var id: String { label }
    let label: String
    let trades: Int
    let netPnL: Double
    let winRate: Double
    var sortKey: Int = 0
}

enum Reports {
    static func byWeekday(_ trades: [Trade]) -> [BucketStat] {
        let cal = Calendar.current
        let names = cal.weekdaySymbols // Sunday..Saturday
        var buckets: [Int: [Trade]] = [:]
        for t in trades { buckets[cal.component(.weekday, from: t.exitTime), default: []].append(t) }
        return (1...7).compactMap { wd in
            guard let ts = buckets[wd], !ts.isEmpty else { return nil }
            return bucket(label: names[wd - 1], trades: ts, sortKey: wd)
        }
    }

    static func byHour(_ trades: [Trade]) -> [BucketStat] {
        let cal = Calendar.current
        var buckets: [Int: [Trade]] = [:]
        for t in trades { buckets[cal.component(.hour, from: t.entryTime), default: []].append(t) }
        return buckets.keys.sorted().map { h in
            bucket(label: String(format: "%02d:00", h), trades: buckets[h] ?? [], sortKey: h)
        }
    }

    static func bySymbol(_ trades: [Trade]) -> [BucketStat] {
        grouped(trades, key: { $0.symbol })
    }

    static func bySetup(_ trades: [Trade]) -> [BucketStat] {
        var buckets: [String: [Trade]] = [:]
        for t in trades {
            if t.setups.isEmpty { buckets["Untagged", default: []].append(t) }
            for s in t.setups { buckets[s, default: []].append(t) }
        }
        return mergeByCase(buckets).map { bucket(label: $0.key, trades: $0.value) }
            .sorted { $0.netPnL > $1.netPnL }
    }

    /// Tags typed by hand drift in case ("Mech Model" vs "MECH Model"); treat
    /// them as one bucket, labelled with the spelling used most often.
    static func mergeByCase(_ buckets: [String: [Trade]]) -> [String: [Trade]] {
        var byKey: [String: [(label: String, trades: [Trade])]] = [:]
        for (label, trades) in buckets {
            byKey[label.lowercased(), default: []].append((label, trades))
        }
        var merged: [String: [Trade]] = [:]
        for (_, variants) in byKey {
            let label = variants.max(by: { $0.trades.count < $1.trades.count })?.label ?? variants[0].label
            var seen = Set<UUID>()
            merged[label] = variants.flatMap(\.trades).filter { seen.insert($0.id).inserted }
        }
        return merged
    }

    static func byMistake(_ trades: [Trade]) -> [BucketStat] {
        var buckets: [String: [Trade]] = [:]
        for t in trades {
            for m in t.mistakes { buckets[m, default: []].append(t) }
        }
        return mergeByCase(buckets).map { bucket(label: $0.key, trades: $0.value) }
            .sorted { $0.netPnL < $1.netPnL }
    }

    static func byDuration(_ trades: [Trade]) -> [BucketStat] {
        let bands: [(String, Range<TimeInterval>)] = [
            ("< 1 min", 0..<60),
            ("1–5 min", 60..<300),
            ("5–15 min", 300..<900),
            ("15–60 min", 900..<3600),
            ("1–4 hrs", 3600..<14400),
            ("4+ hrs", 14400..<TimeInterval.greatestFiniteMagnitude)
        ]
        return bands.enumerated().compactMap { (i, band) in
            let ts = trades.filter { band.1.contains($0.duration) }
            guard !ts.isEmpty else { return nil }
            return bucket(label: band.0, trades: ts, sortKey: i)
        }
    }

    static func byDirection(_ trades: [Trade]) -> [BucketStat] {
        TradeDirection.allCases.compactMap { dir in
            let ts = trades.filter { $0.direction == dir }
            guard !ts.isEmpty else { return nil }
            return bucket(label: dir.rawValue, trades: ts)
        }
    }

    private static func grouped(_ trades: [Trade], key: (Trade) -> String) -> [BucketStat] {
        var buckets: [String: [Trade]] = [:]
        for t in trades { buckets[key(t), default: []].append(t) }
        return buckets.map { bucket(label: $0.key, trades: $0.value) }
            .sorted { $0.netPnL > $1.netPnL }
    }

    private static func bucket(label: String, trades: [Trade], sortKey: Int = 0) -> BucketStat {
        let pnl = trades.reduce(0) { $0 + $1.netPnL }
        let wins = trades.filter { $0.result == .win }.count
        let wr = trades.isEmpty ? 0 : Double(wins) / Double(trades.count) * 100
        return BucketStat(label: label, trades: trades.count, netPnL: pnl, winRate: wr, sortKey: sortKey)
    }
}
