import Foundation

// MARK: - Trade

enum TradeDirection: String, Codable, CaseIterable, Identifiable {
    case long = "Long"
    case short = "Short"
    var id: String { rawValue }
}

enum TradeResult: String, CaseIterable, Identifiable {
    case win = "Win"
    case loss = "Loss"
    case breakeven = "Breakeven"
    var id: String { rawValue }
}

enum TradeSource: String, Codable {
    case manual = "Manual"
    case metatrader = "MetaTrader 5"
    case tradovate = "Tradovate"
    case csv = "CSV Import"
    case sample = "Sample"

    /// Trades whose executions came from a broker rather than being typed in.
    var isBrokerSynced: Bool { self == .metatrader || self == .tradovate || self == .csv }
}

// MARK: - Accounts

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case funded = "Funded"
    case evaluation = "Evaluation"
    case live = "Live"
    case demo = "Demo"
    var id: String { rawValue }
}

/// How an account's trades reach the journal.
enum ConnectionKind: String, Codable, CaseIterable, Identifiable {
    case metaTrader5 = "MetaTrader 5"
    case tradovateExport = "Tradovate"
    case manual = "Manual Entry"
    var id: String { rawValue }

    var detail: String {
        switch self {
        case .metaTrader5:
            return "Fully automatic via the MetaApi cloud bridge. Entry, exit, SL, TP, size, fees and P&L sync on their own."
        case .tradovateExport:
            return "Tradovate does not offer API access for prop or evaluation accounts. Export the Orders report from Tradovate and TradeSync imports it automatically from your watch folder: entry, exit, SL, TP, size and P&L are rebuilt for you."
        case .manual:
            return "Log each trade yourself from the Daily Journal."
        }
    }
}

struct PropFirm: Identifiable, Hashable {
    let name: String
    let suggested: ConnectionKind
    let note: String
    var id: String { name }

    static let presets: [PropFirm] = [
        PropFirm(name: "Tradeify", suggested: .tradovateExport,
                 note: "Tradovate-based accounts (also used when you trade through NinjaTrader or TradingView)."),
        PropFirm(name: "Apex Trader Funding", suggested: .tradovateExport,
                 note: "Choose Tradovate if your Apex account runs on Tradovate."),
        PropFirm(name: "Take Profit Trader", suggested: .tradovateExport,
                 note: "Choose Tradovate if your account runs on Tradovate."),
        PropFirm(name: "FTMO", suggested: .metaTrader5, note: "MetaTrader 5 accounts sync automatically."),
        PropFirm(name: "FundedNext", suggested: .metaTrader5, note: "MetaTrader 5 accounts sync automatically."),
        PropFirm(name: "The5ers", suggested: .metaTrader5, note: "MetaTrader 5 accounts sync automatically."),
        PropFirm(name: "Personal Broker", suggested: .metaTrader5, note: "Your own brokerage account."),
        PropFirm(name: "Other", suggested: .manual, note: "")
    ]

    static func preset(named name: String) -> PropFirm? { presets.first { $0.name == name } }
}

struct TradingAccount: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var type: AccountType = .funded
    var firm: String = "Tradeify"
    var connection: ConnectionKind = .tradovateExport
    /// The account number as the broker prints it (e.g. the "Account" column in a Tradovate export).
    var brokerAccountNumber: String = ""
    var startingBalance: Double = 50_000
    /// Tradovate exports carry no fees; this is charged per contract, per side.
    var commissionPerContractSide: Double = 0
    var metaApi: MetaApiSettings = MetaApiSettings()
    var lastSync: Date? = nil
    var createdAt: Date = Date()

    init(name: String, type: AccountType = .funded, firm: String = "Tradeify",
         connection: ConnectionKind = .tradovateExport, startingBalance: Double = 50_000) {
        self.name = name
        self.type = type
        self.firm = firm
        self.connection = connection
        self.startingBalance = startingBalance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Account"
        type = try c.decodeIfPresent(AccountType.self, forKey: .type) ?? .funded
        firm = try c.decodeIfPresent(String.self, forKey: .firm) ?? "Other"
        connection = try c.decodeIfPresent(ConnectionKind.self, forKey: .connection) ?? .manual
        brokerAccountNumber = try c.decodeIfPresent(String.self, forKey: .brokerAccountNumber) ?? ""
        startingBalance = try c.decodeIfPresent(Double.self, forKey: .startingBalance) ?? 50_000
        commissionPerContractSide = try c.decodeIfPresent(Double.self, forKey: .commissionPerContractSide) ?? 0
        metaApi = try c.decodeIfPresent(MetaApiSettings.self, forKey: .metaApi) ?? MetaApiSettings()
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    var subtitle: String { "\(firm) · \(type.rawValue)" }

    var isAutoSynced: Bool {
        switch connection {
        case .metaTrader5: return metaApi.isConfigured
        case .tradovateExport: return true
        case .manual: return false
        }
    }
}

enum AssetClass: String, Codable, CaseIterable, Identifiable {
    case forex = "Forex"
    case futures = "Futures"
    case stocks = "Stocks"
    case crypto = "Crypto"
    case options = "Options"
    case other = "Other"
    var id: String { rawValue }
}

// MARK: - Contract specs

enum Contracts {
    /// Dollar value of one full point, per contract.
    static let pointValues: [String: Double] = [
        "NQ": 20, "MNQ": 2,
        "ES": 50, "MES": 5,
        "YM": 5, "MYM": 0.5,
        "RTY": 50, "M2K": 5,
        "CL": 1000, "MCL": 100,
        "GC": 100, "MGC": 10,
        "SI": 5000, "SIL": 1000,
        "PL": 50, "HG": 25000, "MHG": 2500,
        "NG": 10000, "QG": 2500, "RB": 42000, "HO": 42000,
        "ZB": 1000, "UB": 1000, "ZN": 1000, "ZF": 1000, "ZT": 2000,
        "ZC": 50, "ZS": 50, "ZW": 50, "HE": 400, "LE": 400,
        "6E": 125000, "M6E": 12500, "6B": 62500, "6J": 12_500_000,
        "6A": 100000, "6C": 100000, "6S": 125000,
        "BTC": 5, "MBT": 0.1, "ETH": 50, "MET": 0.1
    ]

    /// Common desk symbols offered as quick-picks in the trade form.
    static let quickPicks = ["NQ", "MNQ", "ES", "MES", "YM", "RTY", "CL", "GC",
                             "EURUSD", "GBPUSD", "XAUUSD", "BTCUSD"]

    static func pointValue(for symbol: String) -> Double? {
        let s = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        if let v = pointValues[s] { return v }
        return pointValues[rootSymbol(of: s)]
    }

    private static let monthCodes = Set("FGHJKMNQUVXZ")
    private static let rootsLongestFirst = pointValues.keys.sorted { $0.count > $1.count }

    /// "NQZ5" → "NQ", "SILH26" → "SIL", "MESU2026" → "MES". Unknown symbols pass through.
    static func rootSymbol(of symbol: String) -> String {
        let s = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        for root in rootsLongestFirst where s.hasPrefix(root) {
            let rest = s.dropFirst(root.count)
            guard let month = rest.first, monthCodes.contains(month) else { continue }
            let year = rest.dropFirst()
            if (1...4).contains(year.count) && year.allSatisfy(\.isNumber) { return root }
        }
        return s
    }

    /// Standard-size default when there's no futures spec: forex lots, metals, shares.
    static func classDefaultPointValue(for symbol: String, assetClass: AssetClass) -> Double? {
        let s = symbol.uppercased()
        if s.hasPrefix("XAU") { return 100 }          // 100 oz per lot
        if s.hasPrefix("XAG") { return 5000 }         // 5,000 oz per lot
        switch assetClass {
        case .forex:
            // USD-quoted pairs: 100,000 units per lot → $ per 1.0 price move.
            if s.count == 6 && s.hasSuffix("USD") { return 100_000 }
            return nil
        case .stocks, .crypto: return 1
        default: return nil
        }
    }

    /// Best available $-per-point: exchange spec → implied by realized P&L → class default.
    static func resolvedPointValue(symbol: String, assetClass: AssetClass, direction: TradeDirection,
                                   entry: Double, exit: Double, volume: Double, grossPnL: Double?) -> Double? {
        if let spec = pointValue(for: symbol) { return spec }
        if let pnl = grossPnL, abs(pnl) > 0, entry > 0, exit > 0, volume > 0 {
            let move = direction == .long ? exit - entry : entry - exit
            if abs(move) > 0 { return abs(pnl / (move * volume)) }
        }
        return classDefaultPointValue(for: symbol, assetClass: assetClass)
    }

    static func unitLabel(for assetClass: AssetClass) -> String {
        switch assetClass {
        case .futures: return "Contracts"
        case .stocks: return "Shares"
        case .forex: return "Lots"
        case .crypto: return "Units"
        case .options: return "Contracts"
        case .other: return "Size"
        }
    }
}

struct Trade: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var symbol: String
    var assetClass: AssetClass = .other
    var direction: TradeDirection
    var entryTime: Date
    var exitTime: Date
    var entryPrice: Double
    var exitPrice: Double
    var volume: Double            // contracts / lots / shares
    var grossPnL: Double          // before fees
    var commission: Double = 0    // negative = cost
    var swap: Double = 0
    var stopLoss: Double? = nil
    var takeProfit: Double? = nil
    var setups: [String] = []     // strategy / playbook tags
    var mistakes: [String] = []
    var rating: Int = 0           // 0-5 stars
    var notes: String = ""        // "confluences" — why the trade was taken
    var source: TradeSource = .manual
    var accountLabel: String = ""
    var externalId: String? = nil // MT5 position id for dedupe
    var screenshots: [String] = [] // filenames inside the Screenshots directory
    var accountId: UUID? = nil

    /// Synced from a broker, but the trader hasn't added their reasoning or chart yet.
    var needsReview: Bool {
        source.isBrokerSynced && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && screenshots.isEmpty
    }

    var netPnL: Double { grossPnL + commission + swap }
    var fees: Double { commission + swap }
    var duration: TimeInterval { exitTime.timeIntervalSince(entryTime) }

    var result: TradeResult {
        if netPnL > 0.0001 { return .win }
        if netPnL < -0.0001 { return .loss }
        return .breakeven
    }

    /// Planned dollar risk from entry → stop, using real contract specs when known.
    var plannedRisk: Double? {
        guard let sl = stopLoss, sl > 0, volume > 0 else { return nil }
        let distance = abs(entryPrice - sl)
        guard distance > 0 else { return nil }
        guard let pv = Contracts.resolvedPointValue(symbol: symbol, assetClass: assetClass,
                                                    direction: direction, entry: entryPrice,
                                                    exit: exitPrice, volume: volume,
                                                    grossPnL: grossPnL) else { return nil }
        let risk = distance * volume * pv
        return risk > 0 ? risk : nil
    }

    /// R-multiple based on planned risk (entry vs stop). Nil if no stop was set.
    var rMultiple: Double? {
        guard let risk = plannedRisk else { return nil }
        return netPnL / risk
    }

    init(symbol: String,
         assetClass: AssetClass = .other,
         direction: TradeDirection,
         entryTime: Date,
         exitTime: Date,
         entryPrice: Double,
         exitPrice: Double,
         volume: Double,
         grossPnL: Double,
         commission: Double = 0,
         swap: Double = 0,
         stopLoss: Double? = nil,
         takeProfit: Double? = nil,
         setups: [String] = [],
         mistakes: [String] = [],
         rating: Int = 0,
         notes: String = "",
         source: TradeSource = .manual,
         accountLabel: String = "",
         externalId: String? = nil,
         screenshots: [String] = [],
         accountId: UUID? = nil) {
        self.symbol = symbol
        self.assetClass = assetClass
        self.direction = direction
        self.entryTime = entryTime
        self.exitTime = exitTime
        self.entryPrice = entryPrice
        self.exitPrice = exitPrice
        self.volume = volume
        self.grossPnL = grossPnL
        self.commission = commission
        self.swap = swap
        self.stopLoss = stopLoss
        self.takeProfit = takeProfit
        self.setups = setups
        self.mistakes = mistakes
        self.rating = rating
        self.notes = notes
        self.source = source
        self.accountLabel = accountLabel
        self.externalId = externalId
        self.screenshots = screenshots
        self.accountId = accountId
    }

    // Tolerant decoding: missing keys fall back to defaults so journals saved by
    // older builds keep loading after the model grows.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "?"
        assetClass = try c.decodeIfPresent(AssetClass.self, forKey: .assetClass) ?? .other
        direction = try c.decodeIfPresent(TradeDirection.self, forKey: .direction) ?? .long
        entryTime = try c.decodeIfPresent(Date.self, forKey: .entryTime) ?? Date()
        exitTime = try c.decodeIfPresent(Date.self, forKey: .exitTime) ?? entryTime
        entryPrice = try c.decodeIfPresent(Double.self, forKey: .entryPrice) ?? 0
        exitPrice = try c.decodeIfPresent(Double.self, forKey: .exitPrice) ?? 0
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        grossPnL = try c.decodeIfPresent(Double.self, forKey: .grossPnL) ?? 0
        commission = try c.decodeIfPresent(Double.self, forKey: .commission) ?? 0
        swap = try c.decodeIfPresent(Double.self, forKey: .swap) ?? 0
        stopLoss = try c.decodeIfPresent(Double.self, forKey: .stopLoss)
        takeProfit = try c.decodeIfPresent(Double.self, forKey: .takeProfit)
        setups = try c.decodeIfPresent([String].self, forKey: .setups) ?? []
        mistakes = try c.decodeIfPresent([String].self, forKey: .mistakes) ?? []
        rating = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        source = try c.decodeIfPresent(TradeSource.self, forKey: .source) ?? .manual
        accountLabel = try c.decodeIfPresent(String.self, forKey: .accountLabel) ?? ""
        externalId = try c.decodeIfPresent(String.self, forKey: .externalId)
        screenshots = try c.decodeIfPresent([String].self, forKey: .screenshots) ?? []
        accountId = try c.decodeIfPresent(UUID.self, forKey: .accountId)
    }
}

// MARK: - Journal / Notes

struct JournalEntry: Identifiable, Codable {
    var id: UUID = UUID()
    var dayKey: String          // "yyyy-MM-dd"
    var text: String = ""
    var updatedAt: Date = Date()

    init(dayKey: String, text: String = "") {
        self.dayKey = dayKey
        self.text = text
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

/// Retained so journals written by earlier builds still decode.
struct NotebookNote: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var content: String = ""
    var folder: String = "General"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

// MARK: - Playbook

struct Playbook: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var icon: String = "book.closed.fill"
    var summary: String = ""
    var entryCriteria: [String] = []
    var exitCriteria: [String] = []
    var riskRules: [String] = []
    var createdAt: Date = Date()

    init(name: String, icon: String = "book.closed.fill", summary: String = "",
         entryCriteria: [String] = [], exitCriteria: [String] = [], riskRules: [String] = []) {
        self.name = name
        self.icon = icon
        self.summary = summary
        self.entryCriteria = entryCriteria
        self.exitCriteria = exitCriteria
        self.riskRules = riskRules
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "book.closed.fill"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        entryCriteria = try c.decodeIfPresent([String].self, forKey: .entryCriteria) ?? []
        exitCriteria = try c.decodeIfPresent([String].self, forKey: .exitCriteria) ?? []
        riskRules = try c.decodeIfPresent([String].self, forKey: .riskRules) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// Trades are linked to a playbook when the trade's setups contain the playbook name.
    func trades(in all: [Trade]) -> [Trade] {
        all.filter { $0.setups.contains(name) }
    }
}

// MARK: - Settings

struct MetaApiSettings: Codable, Equatable {
    var token: String = ""
    var accountId: String = ""
    var region: String = "london"
    var autoSync: Bool = false
    var syncIntervalMinutes: Int = 15
    var lastSync: Date? = nil
    var connectedAccountName: String? = nil

    var isConfigured: Bool { !token.isEmpty && !accountId.isEmpty }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        accountId = try c.decodeIfPresent(String.self, forKey: .accountId) ?? ""
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? "london"
        autoSync = try c.decodeIfPresent(Bool.self, forKey: .autoSync) ?? false
        syncIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .syncIntervalMinutes) ?? 15
        lastSync = try c.decodeIfPresent(Date.self, forKey: .lastSync)
        connectedAccountName = try c.decodeIfPresent(String.self, forKey: .connectedAccountName)
    }
}

struct AppSettings: Codable, Equatable {
    // Legacy single-account fields — read once to build the first TradingAccount.
    var startingBalance: Double = 10_000
    var accountName: String = "Main Account"
    var metaApi: MetaApiSettings = MetaApiSettings()
    var hasSeededSample: Bool = false

    var accounts: [TradingAccount] = []
    /// nil = "All Accounts".
    var selectedAccountId: UUID? = nil
    var autoSyncEnabled: Bool = true
    var syncIntervalMinutes: Int = 15
    /// Folder watched for Tradovate exports. Defaults to ~/Downloads.
    var importFolderPath: String = ""
    /// "path|modification-time" of export files already imported.
    var processedImports: [String] = []
    var showWelcomeOnLaunch: Bool = true
    /// Used in the welcome line; defaults to the macOS account's first name.
    var traderName: String = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startingBalance = try c.decodeIfPresent(Double.self, forKey: .startingBalance) ?? 10_000
        accountName = try c.decodeIfPresent(String.self, forKey: .accountName) ?? "Main Account"
        metaApi = try c.decodeIfPresent(MetaApiSettings.self, forKey: .metaApi) ?? MetaApiSettings()
        hasSeededSample = try c.decodeIfPresent(Bool.self, forKey: .hasSeededSample) ?? false
        accounts = try c.decodeIfPresent([TradingAccount].self, forKey: .accounts) ?? []
        selectedAccountId = try c.decodeIfPresent(UUID.self, forKey: .selectedAccountId)
        autoSyncEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoSyncEnabled) ?? true
        syncIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .syncIntervalMinutes) ?? 15
        importFolderPath = try c.decodeIfPresent(String.self, forKey: .importFolderPath) ?? ""
        processedImports = try c.decodeIfPresent([String].self, forKey: .processedImports) ?? []
        showWelcomeOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .showWelcomeOnLaunch) ?? true
        traderName = try c.decodeIfPresent(String.self, forKey: .traderName) ?? ""
    }

    var importFolder: URL {
        if !importFolderPath.isEmpty { return URL(fileURLWithPath: importFolderPath, isDirectory: true) }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }
}

// MARK: - Persisted document

struct StoreDocument: Codable {
    var trades: [Trade] = []
    var journal: [JournalEntry] = []
    var notes: [NotebookNote] = []
    var playbooks: [Playbook] = []
    var settings: AppSettings = AppSettings()

    init(trades: [Trade] = [], journal: [JournalEntry] = [], notes: [NotebookNote] = [],
         playbooks: [Playbook] = [], settings: AppSettings = AppSettings()) {
        self.trades = trades
        self.journal = journal
        self.notes = notes
        self.playbooks = playbooks
        self.settings = settings
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trades = try c.decodeIfPresent([Trade].self, forKey: .trades) ?? []
        journal = try c.decodeIfPresent([JournalEntry].self, forKey: .journal) ?? []
        notes = try c.decodeIfPresent([NotebookNote].self, forKey: .notes) ?? []
        playbooks = try c.decodeIfPresent([Playbook].self, forKey: .playbooks) ?? []
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
    }
}

// MARK: - Common tag vocabularies

enum Vocabulary {
    static let mistakes = [
        "FOMO Entry", "Moved Stop Loss", "Oversized", "Revenge Trade",
        "Chased Price", "No Stop Loss", "Early Exit", "Late Entry",
        "Traded the News", "Broke Rules", "Overtraded", "Held Loser Too Long"
    ]
    static let defaultSetups = [
        "Breakout", "Pullback", "Reversal", "Trend Continuation",
        "Opening Range", "Support/Resistance", "Supply & Demand", "News Play"
    ]
    /// Suggested confluence tags for the daily journal.
    static let confluences = [
        "HTF Trend Aligned", "Key Level Reclaim", "Liquidity Sweep", "Fair Value Gap",
        "Order Block", "VWAP Reclaim", "Volume Confirmation", "Momentum Divergence",
        "Opening Range Break", "Prior Day High/Low", "Session Open", "News Catalyst"
    ]
}
