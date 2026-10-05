import SwiftUI
import AppKit

// MARK: - Offscreen render mode (development aid)
//
// `TradeSync --snapshot <outputDirectory> [page…]` hosts each page in an
// off-screen window, lets AppKit lay it out, captures it to PNG, then exits.
// Hosting in a real window (rather than ImageRenderer) is required so scroll
// views, charts and text fields draw their contents.

enum Snapshot {

    static var isRequested: Bool {
        CommandLine.arguments.contains("--snapshot") || CommandLine.arguments.contains("--parse-tradovate")
    }

    /// `--parse-tradovate <file.csv>` prints the trades rebuilt from a Tradovate export.
    static func parseTradovate(_ path: String) {
        do {
            let export = try TradovateImporter.parse(data: try Data(contentsOf: URL(fileURLWithPath: path)))
            let numbers = export.accountNumbers.sorted()
            print("accounts in file: \(numbers.isEmpty ? ["(none)"] : numbers)")
            let groups: [String?] = numbers.isEmpty ? [nil] : numbers
            for number in groups {
                let account = TradingAccount(name: number ?? "Account", connection: .tradovateExport)
                print("── \(number ?? "all rows")")
                for t in TradovateImporter.trades(from: export, accountNumber: number, account: account) {
                    print(String(format: "%@ %@ x%@  in %@ @ %.2f  out %@ @ %.2f  SL %@  TP %@  gross %.2f  R %@",
                                 t.symbol, t.direction.rawValue, Fmt.volume(t.volume),
                                 Fmt.shortTime.string(from: t.entryTime), t.entryPrice,
                                 Fmt.shortTime.string(from: t.exitTime), t.exitPrice,
                                 t.stopLoss.map { String($0) } ?? "—", t.takeProfit.map { String($0) } ?? "—",
                                 t.grossPnL, t.rMultiple.map(Fmt.rMultiple) ?? "—"))
                }
            }
        } catch {
            print("error: \(error.localizedDescription)")
        }
        exit(0)
    }

    static var outputDirectory: URL {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1])
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tradesync-snapshots")
    }

    /// Extra named surfaces beyond the nav pages.
    enum Extra: String { case tradeEntry = "trade-entry" }

    @MainActor
    static func run() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--parse-tradovate"), i + 1 < args.count {
            parseTradovate(args[i + 1])
        }
        let dir = outputDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = TradeStore()
        if store.trades.isEmpty { store.seedSampleData() }
        store.selectedJournalDay = store.journalDayKeys.first ?? Date().dayKey
        if store.trades.isEmpty { store.seedSampleData() }

        Task { @MainActor in
            for page in NavPage.allCases {
                store.page = page
                let root = RootView()
                    .environmentObject(store)
                    .environment(\.colorScheme, .dark)
                await capture(root, size: CGSize(width: 1500, height: 940),
                              to: dir.appendingPathComponent(fileName(page.rawValue)))
            }

            // The trade entry sheet on its own, pre-filled from a real trade.
            if let sample = store.trades(on: store.selectedJournalDay).first {
                let sheet = TradeEntrySheet(existing: sample, dayKey: store.selectedJournalDay)
                    .environmentObject(store)
                    .environment(\.colorScheme, .dark)
                await capture(sheet, size: CGSize(width: 780, height: 720),
                              to: dir.appendingPathComponent(Extra.tradeEntry.rawValue + ".png"))
            }

            // A broker-synced trade as the review form shows it (copy only, never saved).
            if var synced = store.trades(on: store.selectedJournalDay).first {
                synced.source = .tradovate
                synced.notes = ""
                synced.screenshots = []
                let sheet = TradeEntrySheet(existing: synced, dayKey: store.selectedJournalDay)
                    .environmentObject(store)
                    .environment(\.colorScheme, .dark)
                await capture(sheet, size: CGSize(width: 780, height: 720),
                              to: dir.appendingPathComponent("trade-review-synced.png"))
            }

            let editor = AccountEditorSheet(account: TradingAccount(name: "", type: .live, firm: "Personal Broker", connection: .metaTrader5, startingBalance: 10_000), isNew: true)
                .environmentObject(store)
                .environment(\.colorScheme, .dark)
            await capture(editor, size: CGSize(width: 640, height: 640),
                          to: dir.appendingPathComponent("account-editor.png"))

            func welcomeView() -> some View {
                WelcomeView(onEnter: {})
                    .environmentObject(store)
                    .environment(\.colorScheme, .dark)
            }
            // mid-write frame, then the settled page
            await capture(welcomeView(), size: CGSize(width: 1500, height: 940),
                          to: dir.appendingPathComponent("welcome-writing.png"), settle: 9)
            await capture(welcomeView(), size: CGSize(width: 1500, height: 940),
                          to: dir.appendingPathComponent("welcome.png"), settle: 40)

            // Welcome at real screen sizes, including full screen on common Macs.
            for (w, h) in [(1220, 740), (1440, 900), (1512, 982), (1728, 1117), (1920, 1080), (2560, 1440)] {
                await capture(welcomeView(), size: CGSize(width: w, height: h),
                              to: dir.appendingPathComponent("welcome-\(w)x\(h).png"), settle: 30)
            }

            // Trade Review at each horizon.
            for kind in ReviewKind.allCases {
                let v = ReviewView(kind: kind)
                    .environmentObject(store)
                    .environment(\.colorScheme, .dark)
                    .background(Theme.bg)
                await capture(v, size: CGSize(width: 1254, height: 940),
                              to: dir.appendingPathComponent("review-\(kind.rawValue.replacingOccurrences(of: " ", with: "")).png"))
            }

            // Best-trade click-through: the journal opens on that day, scrolled and highlighted.
            if let best = store.scopedTrades.max(by: { $0.netPnL < $1.netPnL }) {
                store.showInJournal(best)
                let root = RootView()
                    .environmentObject(store)
                    .environment(\.colorScheme, .dark)
                await capture(root, size: CGSize(width: 1500, height: 940),
                              to: dir.appendingPathComponent("journal-focus.png"), settle: 12)
            }

            // The shade mid-rise, composited over the live dashboard.
            store.page = .dashboard
            store.showWelcome = true
            for (name, r) in [("welcome-rise-35", 0.35), ("welcome-rise-65", 0.65)] {
                store.welcomeReveal = r
                let root = RootView()
                    .environmentObject(store)
                    .environment(\.colorScheme, .dark)
                await capture(root, size: CGSize(width: 1500, height: 940),
                              to: dir.appendingPathComponent("\(name).png"), settle: 30)
            }
            store.showWelcome = false
            store.welcomeReveal = 0

            let well = ScreenshotWell(screenshots: .constant([]))
                .environmentObject(store)
                .environment(\.colorScheme, .dark)
                .padding(20)
                .background(Theme.bg)
            await capture(well, size: CGSize(width: 780, height: 110),
                          to: dir.appendingPathComponent("screenshot-well.png"))

            print("snapshots written to \(dir.path)")
            exit(0)
        }
    }

    private static func fileName(_ title: String) -> String {
        title.lowercased().replacingOccurrences(of: " ", with: "-") + ".png"
    }

    @MainActor
    private static func capture<V: View>(_ view: V, size: CGSize, to url: URL, settle: Int = 6) async {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderFrontRegardless()

        // Give SwiftUI a few run-loop passes to lay out and draw charts.
        for _ in 0..<settle {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(nanoseconds: 120_000_000)
        }

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            FileHandle.standardError.write("failed to render \(url.lastPathComponent)\n".data(using: .utf8)!)
            window.orderOut(nil)
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("rendered \(url.lastPathComponent)")
        }
        window.orderOut(nil)
    }
}

// MARK: - MT5 reconstruction check (development aid)
// `--test-mt5` feeds synthetic MetaApi deals through the importer and prints
// the trades it produces, covering layered entries and partial exits.

enum MT5Check {
    static var isRequested: Bool { CommandLine.arguments.contains("--test-mt5") }

    static func run() {
        let json = """
        [
         {"id":"1","type":"DEAL_TYPE_BUY","entryType":"DEAL_ENTRY_IN","symbol":"EURUSD","volume":1.0,"price":1.0800,"profit":0,"commission":-7,"swap":0,"time":"2026-10-01T08:00:00.000Z","positionId":"A1","stopLoss":1.0770,"takeProfit":1.0900},
         {"id":"2","type":"DEAL_TYPE_BUY","entryType":"DEAL_ENTRY_IN","symbol":"EURUSD","volume":1.0,"price":1.0780,"profit":0,"commission":-7,"swap":0,"time":"2026-10-01T08:30:00.000Z","positionId":"A2","stopLoss":1.0770,"takeProfit":1.0900},
         {"id":"3","type":"DEAL_TYPE_BUY","entryType":"DEAL_ENTRY_IN","symbol":"EURUSD","volume":2.0,"price":1.0760,"profit":0,"commission":-14,"swap":0,"time":"2026-10-01T09:00:00.000Z","positionId":"A3","stopLoss":1.0770,"takeProfit":1.0900},
         {"id":"4","type":"DEAL_TYPE_SELL","entryType":"DEAL_ENTRY_OUT","symbol":"EURUSD","volume":1.0,"price":1.0850,"profit":500,"commission":-7,"swap":0,"time":"2026-10-01T10:00:00.000Z","positionId":"A1","reason":"DEAL_REASON_CLIENT"},
         {"id":"5","type":"DEAL_TYPE_SELL","entryType":"DEAL_ENTRY_OUT","symbol":"EURUSD","volume":1.0,"price":1.0850,"profit":700,"commission":-7,"swap":0,"time":"2026-10-01T10:00:00.000Z","positionId":"A2","reason":"DEAL_REASON_CLIENT"},
         {"id":"6","type":"DEAL_TYPE_SELL","entryType":"DEAL_ENTRY_OUT","symbol":"EURUSD","volume":2.0,"price":1.0850,"profit":1800,"commission":-14,"swap":0,"time":"2026-10-01T10:00:00.000Z","positionId":"A3","reason":"DEAL_REASON_CLIENT"},

         {"id":"7","type":"DEAL_TYPE_SELL","entryType":"DEAL_ENTRY_IN","symbol":"XAUUSD","volume":1.0,"price":2660.0,"profit":0,"commission":-5,"swap":0,"time":"2026-10-01T12:00:00.000Z","positionId":"B1","stopLoss":2668.0},
         {"id":"8","type":"DEAL_TYPE_SELL","entryType":"DEAL_ENTRY_IN","symbol":"XAUUSD","volume":1.0,"price":2664.0,"profit":0,"commission":-5,"swap":0,"time":"2026-10-01T12:20:00.000Z","positionId":"B1","stopLoss":2668.0},
         {"id":"9","type":"DEAL_TYPE_BUY","entryType":"DEAL_ENTRY_OUT","symbol":"XAUUSD","volume":1.0,"price":2656.0,"profit":600,"commission":-5,"swap":0,"time":"2026-10-01T13:00:00.000Z","positionId":"B1","reason":"DEAL_REASON_CLIENT"},
         {"id":"10","type":"DEAL_TYPE_BUY","entryType":"DEAL_ENTRY_OUT","symbol":"XAUUSD","volume":1.0,"price":2652.0,"profit":1200,"commission":-5,"swap":0,"time":"2026-10-01T13:30:00.000Z","positionId":"B1","reason":"DEAL_REASON_TP"}
        ]
        """
        guard let deals = try? JSONDecoder().decode([MetaApiDeal].self, from: Data(json.utf8)) else {
            print("decode failed"); exit(1)
        }
        let trades = MetaApiService.buildTrades(from: deals, accountLabel: "Test")
        print("deals in: \(deals.count) → trades out: \(trades.count)")
        for t in trades {
            print(String(format: "%@ %@ x%@  entry %.5f  exit %.5f  SL %@  net %.2f  R %@  %@→%@",
                         t.symbol, t.direction.rawValue, Fmt.volume(t.volume), t.entryPrice, t.exitPrice,
                         t.stopLoss.map { String(format: "%.4f", $0) } ?? "—",
                         t.netPnL, t.rMultiple.map(Fmt.rMultiple) ?? "—",
                         Fmt.shortTime.string(from: t.entryTime), Fmt.shortTime.string(from: t.exitTime)))
        }
        exit(0)
    }
}
