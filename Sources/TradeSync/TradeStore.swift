import Foundation
import SwiftUI
import AppKit

@MainActor
final class TradeStore: ObservableObject {
    @Published var trades: [Trade] = [] { didSet { scheduleSave() } }
    @Published var journal: [JournalEntry] = [] { didSet { scheduleSave() } }
    @Published var notes: [NotebookNote] = [] { didSet { scheduleSave() } }
    @Published var playbooks: [Playbook] = [] { didSet { scheduleSave() } }
    @Published var settings: AppSettings = AppSettings() { didSet { scheduleSave() } }

    @Published var syncStatus: SyncStatus = .idle
    @Published var presentAddTrade = false   // transient: global ⌘N / menu action
    @Published var showWelcome = false       // opening sequence, once per launch
    /// 0 = welcome fully covering, 1 = dashboard fully revealed. Shared so the
    /// dashboard can rise in step with the welcome lifting away.
    @Published var welcomeReveal: CGFloat = 0

    // Navigation lives in the store so any view can route (e.g. calendar → journal day).
    @Published var page: NavPage = .dashboard
    @Published var selectedJournalDay: String = Date().dayKey
    /// A trade to scroll to and highlight when the journal next shows its day.
    @Published var focusTradeId: UUID? = nil

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success(String)   // message
        case failure(String)
    }

    private var saveTask: Task<Void, Never>? = nil
    private var loading = false

    /// Set to point the app at a different data folder (used to test a fresh install).
    static let dataDirectoryOverride = ProcessInfo.processInfo.environment["TRADESYNC_DATA_DIR"]

    static let dataDirectory: URL = {
        if let override = dataDirectoryOverride, !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("TradeSync", isDirectory: true)
    }()
    static var dataFile: URL { dataDirectory.appendingPathComponent("data.json") }
    static var screenshotsDirectory: URL { dataDirectory.appendingPathComponent("Screenshots", isDirectory: true) }

    init() {
        migrateLegacyDataDirectory()
        load()
        if !settings.hasSeededSample && trades.isEmpty && notes.isEmpty && playbooks.isEmpty {
            seedSampleData()
            settings.hasSeededSample = true
        }
        migrateToAccounts()
        // A first launch always shows the welcome, because that's where the name is asked.
        showWelcome = (settings.showWelcomeOnLaunch || settings.traderName.isEmpty) && !Snapshot.isRequested
    }

    /// Journals written before the rename live in the NextTrader folder.
    private func migrateLegacyDataDirectory() {
        guard Self.dataDirectoryOverride == nil else { return }
        let fm = FileManager.default
        let legacy = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NextTrader", isDirectory: true)
        guard !fm.fileExists(atPath: Self.dataFile.path),
              fm.fileExists(atPath: legacy.appendingPathComponent("data.json").path) else { return }
        do {
            try fm.createDirectory(at: Self.dataDirectory, withIntermediateDirectories: true)
            for item in (try? fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)) ?? [] {
                let target = Self.dataDirectory.appendingPathComponent(item.lastPathComponent)
                if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: item, to: target) }
            }
            NSLog("TradeSync migrated journal from NextTrader")
        } catch {
            NSLog("TradeSync migration failed: \(error)")
        }
    }

    // MARK: - Accounts

    var accounts: [TradingAccount] { settings.accounts }

    var selectedAccount: TradingAccount? {
        guard let id = settings.selectedAccountId else { return nil }
        return settings.accounts.first { $0.id == id }
    }

    func account(for id: UUID?) -> TradingAccount? {
        guard let id else { return nil }
        return settings.accounts.first { $0.id == id }
    }

    func selectAccount(_ id: UUID?) { settings.selectedAccountId = id }

    /// Account new manual trades go into: the selected one, else the first.
    var defaultAccountId: UUID? { settings.selectedAccountId ?? settings.accounts.first?.id }

    func saveAccount(_ account: TradingAccount) {
        if let i = settings.accounts.firstIndex(where: { $0.id == account.id }) {
            settings.accounts[i] = account
        } else {
            settings.accounts.append(account)
        }
    }

    /// Removes the account and its trades.
    func deleteAccount(_ account: TradingAccount) {
        for t in trades where t.accountId == account.id { deleteScreenshots(of: t) }
        trades.removeAll { $0.accountId == account.id }
        settings.accounts.removeAll { $0.id == account.id }
        if settings.selectedAccountId == account.id { settings.selectedAccountId = nil }
    }

    /// Journals from before multi-account support get one account holding every trade.
    private func migrateToAccounts() {
        if settings.accounts.isEmpty {
            var first = TradingAccount(name: settings.accountName,
                                       type: .live,
                                       firm: "Personal Broker",
                                       connection: settings.metaApi.isConfigured ? .metaTrader5 : .manual,
                                       startingBalance: settings.startingBalance)
            first.metaApi = settings.metaApi
            settings.accounts = [first]
        }
        let fallback = settings.accounts[0].id
        if trades.contains(where: { $0.accountId == nil }) {
            trades = trades.map { t in
                var t = t
                if t.accountId == nil { t.accountId = fallback }
                return t
            }
        }
    }

    // MARK: - Scoped views (respect the account switcher)

    /// Trades in the currently selected account, or every account when "All" is selected.
    var scopedTrades: [Trade] {
        guard let id = settings.selectedAccountId else { return trades }
        return trades.filter { $0.accountId == id }
    }

    var scopedStartingBalance: Double {
        if let a = selectedAccount { return a.startingBalance }
        return settings.accounts.reduce(0) { $0 + $1.startingBalance }
    }

    var reviewQueueCount: Int { scopedTrades.filter(\.needsReview).count }

    // MARK: - Stats

    var stats: Stats { Stats(trades: scopedTrades) }

    func stats(for trades: [Trade]) -> Stats { Stats(trades: trades) }

    var allSetups: [String] {
        var set = Set(Vocabulary.defaultSetups)
        for t in trades { set.formUnion(t.setups) }
        for p in playbooks { set.insert(p.name) }
        return set.sorted()
    }

    var allSymbols: [String] { Set(scopedTrades.map(\.symbol)).sorted() }

    // MARK: - Trades CRUD

    func add(_ trade: Trade) {
        var t = trade
        if t.accountId == nil { t.accountId = defaultAccountId }
        trades.append(t)
    }

    func update(_ trade: Trade) {
        if let i = trades.firstIndex(where: { $0.id == trade.id }) { trades[i] = trade }
    }

    func delete(_ trade: Trade) {
        deleteScreenshots(of: trade)
        trades.removeAll { $0.id == trade.id }
    }

    /// Merge imported trades, skipping any whose externalId already exists.
    /// Returns number of newly added trades.
    @discardableResult
    func merge(imported: [Trade]) -> Int {
        let existing = Set(trades.compactMap(\.externalId))
        var added = 0
        for t in imported {
            if let ext = t.externalId, existing.contains(ext) { continue }
            trades.append(t)
            added += 1
        }
        return added
    }

    // MARK: - Journal days

    func journalEntry(for dayKey: String) -> JournalEntry {
        journal.first { $0.dayKey == dayKey } ?? JournalEntry(dayKey: dayKey)
    }

    func saveJournal(_ entry: JournalEntry) {
        var e = entry
        e.updatedAt = Date()
        if let i = journal.firstIndex(where: { $0.dayKey == entry.dayKey }) {
            journal[i] = e
        } else {
            journal.append(e)
        }
    }

    /// Every day that should appear as a folder in the Daily Journal: days with
    /// trades, days with a written recap, and days the user opened manually.
    var journalDayKeys: [String] {
        var keys = Set(scopedTrades.map { $0.exitTime.dayKey })
        // Review notes are stored as journal entries too; they aren't day folders.
        keys.formUnion(journal.map(\.dayKey).filter { !$0.hasPrefix("week-") && !$0.hasPrefix("review-") })
        return keys.sorted(by: >)
    }

    /// Creates the day folder if it doesn't exist yet, and selects it.
    func openJournalDay(_ dayKey: String) {
        if !journal.contains(where: { $0.dayKey == dayKey }) {
            journal.append(JournalEntry(dayKey: dayKey))
        }
        selectedJournalDay = dayKey
    }

    /// Trades closed on a given day, within the selected account scope.
    /// Opens the Daily Journal on a trade's day, scrolled to that trade.
    func showInJournal(_ trade: Trade) {
        openJournalDay(trade.exitTime.dayKey)
        focusTradeId = trade.id
        page = .journal
    }

    func trades(on dayKey: String) -> [Trade] {
        scopedTrades.filter { $0.exitTime.dayKey == dayKey }.sorted { $0.entryTime < $1.entryTime }
    }

    /// Deletes the day's trades in the current account scope; the recap goes
    /// only if no other account still has trades that day.
    func deleteJournalDay(_ dayKey: String) {
        let doomed = Set(trades(on: dayKey).map(\.id))
        for t in trades where doomed.contains(t.id) { deleteScreenshots(of: t) }
        trades.removeAll { doomed.contains($0.id) }
        if !trades.contains(where: { $0.exitTime.dayKey == dayKey }) {
            journal.removeAll { $0.dayKey == dayKey }
        }
    }

    // MARK: - Screenshots

    /// Writes image data into the Screenshots directory and returns its filename.
    @discardableResult
    func saveScreenshot(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let name = "shot-\(UUID().uuidString).png"
        do {
            try FileManager.default.createDirectory(at: Self.screenshotsDirectory, withIntermediateDirectories: true)
            try png.write(to: Self.screenshotsDirectory.appendingPathComponent(name), options: .atomic)
            return name
        } catch {
            NSLog("TradeSync screenshot save failed: \(error)")
            return nil
        }
    }

    @discardableResult
    func saveScreenshot(fromFileAt url: URL) -> String? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        return saveScreenshot(image)
    }

    func screenshotURL(_ name: String) -> URL {
        Self.screenshotsDirectory.appendingPathComponent(name)
    }

    func loadScreenshot(_ name: String) -> NSImage? {
        NSImage(contentsOf: screenshotURL(name))
    }

    func deleteScreenshotFile(_ name: String) {
        try? FileManager.default.removeItem(at: screenshotURL(name))
    }

    func deleteScreenshots(of trade: Trade) {
        for name in trade.screenshots { deleteScreenshotFile(name) }
    }

    /// Pulls an image off the system clipboard (⌘V from TradingView).
    func screenshotFromClipboard() -> String? {
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb) {
            return saveScreenshot(image)
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let first = urls.first {
            return saveScreenshot(fromFileAt: first)
        }
        return nil
    }

    // MARK: - Sample data

    func clearSampleData() {
        trades.removeAll { $0.source == .sample }
    }

    var hasSampleData: Bool { trades.contains { $0.source == .sample } }

    func seedSampleData() {
        let target = defaultAccountId
        trades.append(contentsOf: SampleData.trades().map { t in
            var t = t
            t.accountId = target
            return t
        })
        if playbooks.isEmpty { playbooks = SampleData.playbooks() }
        journal.append(contentsOf: SampleData.journal(from: trades)
            .filter { entry in !journal.contains { $0.dayKey == entry.dayKey } })
    }

    // MARK: - Persistence

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: Self.dataFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let doc = try? decoder.decode(StoreDocument.self, from: data) {
            trades = doc.trades
            journal = doc.journal
            notes = doc.notes
            playbooks = doc.playbooks
            settings = doc.settings
        }
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let doc = StoreDocument(trades: trades, journal: journal, notes: notes,
                                playbooks: playbooks, settings: settings)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: Self.dataDirectory, withIntermediateDirectories: true)
            let data = try encoder.encode(doc)
            try data.write(to: Self.dataFile, options: .atomic)
        } catch {
            NSLog("TradeSync save failed: \(error)")
        }
    }

    func exportJSON() -> Data? {
        let doc = StoreDocument(trades: trades, journal: journal, notes: notes,
                                playbooks: playbooks, settings: settings)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(doc)
    }
}

// MARK: - Sample data generator

enum SampleData {

    struct Instrument {
        let symbol: String
        let assetClass: AssetClass
        let price: Double
        let tickRange: Double     // typical price excursion
        let pointValue: Double    // $ per point per unit volume
        let volumeRange: ClosedRange<Double>
    }

    static let instruments: [Instrument] = [
        Instrument(symbol: "NQ", assetClass: .futures, price: 21450, tickRange: 60, pointValue: 20, volumeRange: 1...3),
        Instrument(symbol: "ES", assetClass: .futures, price: 6080, tickRange: 18, pointValue: 50, volumeRange: 1...3),
        Instrument(symbol: "EURUSD", assetClass: .forex, price: 1.0850, tickRange: 0.0045, pointValue: 100_000, volumeRange: 0.5...2),
        Instrument(symbol: "GBPUSD", assetClass: .forex, price: 1.2710, tickRange: 0.0050, pointValue: 100_000, volumeRange: 0.5...1.5),
        Instrument(symbol: "XAUUSD", assetClass: .forex, price: 2660, tickRange: 14, pointValue: 100, volumeRange: 0.5...2),
        Instrument(symbol: "AAPL", assetClass: .stocks, price: 232, tickRange: 2.4, pointValue: 1, volumeRange: 100...400),
        Instrument(symbol: "TSLA", assetClass: .stocks, price: 315, tickRange: 6.5, pointValue: 1, volumeRange: 50...200)
    ]

    static let setups = ["Opening Range Breakout", "VWAP Pullback", "Trend Continuation", "Reversal at Key Level", "Supply & Demand"]

    static func trades() -> [Trade] {
        var rng = SeededGenerator(seed: 20260707)
        var result: [Trade] = []
        let cal = Calendar.current
        let today = Date().startOfDay

        // ~75 trading days back from today
        var tradingDays: [Date] = []
        var cursor = today
        while tradingDays.count < 75 {
            let wd = cal.component(.weekday, from: cursor)
            if wd != 1 && wd != 7 { tradingDays.append(cursor) }
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        tradingDays.reverse()

        for day in tradingDays {
            // skip ~20% of days
            if rng.next01() < 0.20 { continue }
            let tradesToday = 1 + Int(rng.next01() * 4) // 1-4
            // day bias: some days trend well for the trader
            let dayBias = rng.next01() // higher = better day
            for _ in 0..<tradesToday {
                let inst = instruments[Int(rng.next01() * Double(instruments.count)) % instruments.count]
                let hour = 8 + Int(rng.next01() * 7)      // 08:00-15:00
                let minute = Int(rng.next01() * 60)
                let entry = cal.date(bySettingHour: hour, minute: minute, second: Int(rng.next01() * 60), of: day)!
                let holdMin = 4 + rng.next01() * 110      // 4-114 min
                let exit = entry.addingTimeInterval(holdMin * 60)

                let long = rng.next01() < 0.56
                // Win probability blends day bias -> ~58% overall
                let winProb = 0.42 + dayBias * 0.33
                let isWin = rng.next01() < winProb

                let excursion = inst.tickRange * (0.35 + rng.next01() * 1.0)
                let move = isWin ? excursion : -excursion * (0.35 + rng.next01() * 0.4)
                let signedMove = long ? move : -move
                let entryPrice = inst.price * (1 + (rng.next01() - 0.5) * 0.01)
                let exitPrice = entryPrice + signedMove

                let volume = inst.volumeRange.lowerBound + rng.next01() * (inst.volumeRange.upperBound - inst.volumeRange.lowerBound)
                let vol = inst.assetClass == .stocks ? (volume / 10).rounded() * 10 : (volume * 2).rounded() / 2
                let gross = (long ? exitPrice - entryPrice : entryPrice - exitPrice) * vol * inst.pointValue
                // Stocks: ~1¢/share. Futures/forex: a few $ per contract/lot.
                let commission = inst.assetClass == .stocks
                    ? -0.01 * vol
                    : -(2.0 + rng.next01() * 6.0) * max(1, vol.rounded())

                let stopDistance = excursion * (0.5 + rng.next01() * 0.4)
                let sl = long ? entryPrice - stopDistance : entryPrice + stopDistance
                let tp = long ? entryPrice + stopDistance * 2.2 : entryPrice - stopDistance * 2.2

                var setupsPicked = [setups[Int(rng.next01() * Double(setups.count)) % setups.count]]
                if rng.next01() < 0.2 { setupsPicked.append(setups[Int(rng.next01() * Double(setups.count)) % setups.count]) }
                var mistakes: [String] = []
                if !isWin && rng.next01() < 0.45 {
                    mistakes.append(Vocabulary.mistakes[Int(rng.next01() * Double(Vocabulary.mistakes.count)) % Vocabulary.mistakes.count])
                }

                let notesPool = isWin
                    ? ["Clean execution — followed the plan A to Z.",
                       "Waited for confirmation candle before entering. Patience paid.",
                       "Scaled out at first target, let runner go to second.",
                       ""]
                    : ["Entered before confirmation. Need to wait for the close.",
                       "Sized too big for the setup quality. Cut it fast at least.",
                       "Chop day — should have stopped after two losses.",
                       ""]

                result.append(Trade(
                    symbol: inst.symbol,
                    assetClass: inst.assetClass,
                    direction: long ? .long : .short,
                    entryTime: entry,
                    exitTime: exit,
                    entryPrice: round5(entryPrice),
                    exitPrice: round5(exitPrice),
                    volume: vol,
                    grossPnL: (gross * 100).rounded() / 100,
                    commission: (commission * 100).rounded() / 100,
                    swap: 0,
                    stopLoss: round5(sl),
                    takeProfit: round5(tp),
                    setups: Array(Set(setupsPicked)),
                    mistakes: mistakes,
                    rating: isWin ? (3 + Int(rng.next01() * 3)) : (1 + Int(rng.next01() * 3)),
                    notes: notesPool[Int(rng.next01() * Double(notesPool.count)) % notesPool.count],
                    source: .sample,
                    accountLabel: "Sample Account"
                ))
            }
        }
        return result
    }

    static func round5(_ v: Double) -> Double { (v * 100_000).rounded() / 100_000 }

    static func playbooks() -> [Playbook] {
        [
            Playbook(
                name: "Opening Range Breakout",
                icon: "sunrise.fill",
                summary: "Trade the break of the first 15-minute range on index futures with volume confirmation.",
                entryCriteria: [
                    "First 15-min range established (9:30–9:45 ET)",
                    "Break of range high/low on above-average volume",
                    "No major news pending within 30 minutes",
                    "Price above/below VWAP in direction of the break"
                ],
                exitCriteria: [
                    "Target 1: 1R — take 50% off",
                    "Target 2: 2.2R or opposite side of the range",
                    "Time stop: flat by 11:30 if no follow-through"
                ],
                riskRules: [
                    "Max risk 1% of account per trade",
                    "Stop goes below/above the range midpoint",
                    "Max 2 attempts per session"
                ]
            ),
            Playbook(
                name: "VWAP Pullback",
                icon: "arrow.uturn.down.circle.fill",
                summary: "Join an established trend on the first orderly pullback into VWAP.",
                entryCriteria: [
                    "Clear trend: price making HH/HL (or LL/LH) away from VWAP",
                    "First touch of VWAP after the trend leg",
                    "Reversal candle at VWAP (hammer / engulfing)",
                    "Entry on break of the reversal candle"
                ],
                exitCriteria: [
                    "Target: prior swing high/low",
                    "Trail stop under each new higher low once 1R hit"
                ],
                riskRules: [
                    "Stop 1 ATR beyond VWAP",
                    "Skip if spread > 2 ticks",
                    "No entries in the first 5 minutes of the session"
                ]
            ),
            Playbook(
                name: "Reversal at Key Level",
                icon: "arrow.triangle.2.circlepath",
                summary: "Fade extended moves into major daily support/resistance with confirmation.",
                entryCriteria: [
                    "Price reaches a pre-marked daily/weekly level",
                    "Momentum divergence on the 5-minute chart",
                    "Failed breakout / stop-run wick through the level",
                    "Entry on reclaim of the level"
                ],
                exitCriteria: [
                    "Target 1: mid-range / VWAP",
                    "Target 2: opposite extreme of the day",
                    "Hard stop beyond the wick extreme"
                ],
                riskRules: [
                    "Only A+ levels marked in the morning plan",
                    "Half size vs. trend trades",
                    "Never add to a loser"
                ]
            )
        ]
    }

    static func notes() -> [NotebookNote] {
        [
            NotebookNote(
                title: "Morning Pre-Market Checklist",
                content: """
                ## Before the open
                - [ ] Review overnight session: range, key levels, gaps
                - [ ] Mark daily & weekly support/resistance
                - [ ] Check the economic calendar for red-folder news
                - [ ] Define max loss for the day ($500) and walk-away rule
                - [ ] Pick today's A+ setups from the playbook — no improvising

                ## Mindset
                One good trade at a time. The goal today is flawless execution, not P&L.
                """,
                folder: "Trading Plan"
            ),
            NotebookNote(
                title: "Weekly Review Template",
                content: """
                ## Wins this week
                -

                ## Mistakes & cost
                - (pull from mistake tags — what did FOMO cost this week?)

                ## Metric check
                - Win rate vs. last week:
                - Profit factor:
                - Biggest drawdown moment:

                ## One thing to change next week
                -
                """,
                folder: "Trading Plan"
            ),
            NotebookNote(
                title: "Rules I Keep Breaking",
                content: """
                1. Entering before the confirmation candle closes — cost me repeatedly.
                2. Moving stops "just a little lower". A stop is a stop.
                3. Trading through lunch chop — my stats after 11:45 are terrible.
                """,
                folder: "General"
            )
        ]
    }

    static func journal(from trades: [Trade]) -> [JournalEntry] {
        let byDay = Dictionary(grouping: trades.filter { $0.source == .sample }, by: { $0.exitTime.dayKey })
        let sortedDays = byDay.keys.sorted().suffix(6)
        let templates = [
            "Solid session. Stuck to the playbook and took only A setups. The first trade set the tone — patient entry, clean management.",
            "Choppy morning. Should have recognized the range earlier and cut size. Stopped trading before lunch which saved the day.",
            "Great trend day. Caught the move off the open and added on the first pullback. Need to work on holding runners longer.",
            "Rough day — revenge traded after the first stop-out and paid for it. Tomorrow: hard rule, 5-minute break after any loss.",
            "Did not force anything. Two trades, both planned the night before. This is what the process is supposed to feel like.",
            "News whipsaw got me once, then I adapted and traded the reaction level well. Journaling the pattern for next CPI day."
        ]
        return sortedDays.enumerated().map { (i, key) in
            JournalEntry(dayKey: key, text: templates[i % templates.count])
        }
    }
}

// Deterministic RNG so sample data is stable across launches
struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 2685821657736338717 &+ 1 }
    mutating func nextRaw() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
    mutating func next01() -> Double {
        Double(nextRaw() % 1_000_000) / 1_000_000
    }
}
