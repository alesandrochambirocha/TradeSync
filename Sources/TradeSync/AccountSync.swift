import Foundation

// MARK: - Automatic account sync
//
// Runs on launch and on a timer. MetaTrader 5 accounts are pulled from MetaApi;
// Tradovate accounts (Tradeify and other prop firms) are imported from Orders
// exports that land in the watch folder. Everything is de-duplicated, so a
// sync can run as often as needed without creating copies.

extension TradeStore {

    /// Called every minute by the app. Cheap when nothing changed.
    func autoSyncTick() async {
        guard settings.autoSyncEnabled else { return }
        scanImportFolder()
        let interval = TimeInterval(max(5, settings.syncIntervalMinutes) * 60)
        for account in settings.accounts where account.connection == .metaTrader5 && account.metaApi.isConfigured {
            let due = account.lastSync.map { Date().timeIntervalSince($0) >= interval } ?? true
            if due { await syncMetaTrader(accountId: account.id) }
        }
    }

    /// "Sync Now": every connected account, regardless of timers.
    func syncAll() async {
        syncStatus = .syncing
        var added = scanImportFolder(reportStatus: false)
        var failures: [String] = []
        for account in settings.accounts where account.connection == .metaTrader5 && account.metaApi.isConfigured {
            switch await pullMetaTrader(account, fullHistory: false) {
            case .success(let n): added += n
            case .failure(let e): failures.append("\(account.name): \(e.localizedDescription)")
            }
        }
        if let first = failures.first {
            syncStatus = .failure(first)
        } else {
            syncStatus = .success(added > 0 ? "Logged \(added) new trade\(added == 1 ? "" : "s")" : "All accounts up to date")
        }
    }

    // MARK: MetaTrader 5

    func syncMetaTrader(accountId: UUID, fullHistory: Bool = false) async {
        guard let account = account(for: accountId) else { return }
        syncStatus = .syncing
        switch await pullMetaTrader(account, fullHistory: fullHistory) {
        case .success(let n):
            syncStatus = .success(n > 0 ? "\(account.name): logged \(n) new trade\(n == 1 ? "" : "s")"
                                        : "\(account.name) is up to date")
        case .failure(let e):
            syncStatus = .failure("\(account.name): \(e.localizedDescription)")
        }
    }

    private func pullMetaTrader(_ account: TradingAccount, fullHistory: Bool) async -> Result<Int, Error> {
        let service = MetaApiService(settings: account.metaApi)
        // Overlap the window by 2 days so partially synced days heal themselves.
        let start: Date
        if fullHistory || account.lastSync == nil {
            start = Calendar.current.date(byAdding: .year, value: -3, to: Date())!
        } else {
            start = Calendar.current.date(byAdding: .day, value: -2, to: account.lastSync!)!
        }
        do {
            let fetched = try await service.fetchTrades(from: start, to: Date(), accountLabel: account.name)
            let existing = Set(trades.compactMap(\.externalId))
            let imported = fetched.compactMap { t -> Trade? in
                var t = t
                // Position ids are only unique per MT5 account.
                let legacy = t.externalId ?? ""
                if existing.contains(legacy) { return nil }
                t.externalId = "\(legacy)@\(account.metaApi.accountId)"
                t.accountId = account.id
                return t
            }
            let added = merge(imported: imported)
            markSynced(account.id)
            return .success(added)
        } catch {
            return .failure(error)
        }
    }

    func testMetaTraderConnection(accountId: UUID) async {
        guard var account = account(for: accountId) else { return }
        syncStatus = .syncing
        do {
            let info = try await MetaApiService(settings: account.metaApi).testConnection()
            account.metaApi.connectedAccountName = info.name
            if let region = info.region, !region.isEmpty { account.metaApi.region = region }
            if account.brokerAccountNumber.isEmpty, let login = info.login { account.brokerAccountNumber = login }
            saveAccount(account)
            let name = info.name ?? info.login ?? "account"
            let deploying = (info.connectionStatus == "CONNECTED" || info.state == "DEPLOYED")
                ? "" : " (still deploying on MetaApi)"
            syncStatus = .success("Connected to \(name)\(deploying)")
        } catch {
            syncStatus = .failure(error.localizedDescription)
        }
    }

    // MARK: Tradovate exports

    /// Imports any new Tradovate exports in the watch folder. Returns trades added.
    @discardableResult
    func scanImportFolder(reportStatus: Bool = true) -> Int {
        let tradovateAccounts = settings.accounts.filter { $0.connection == .tradovateExport }
        guard !tradovateAccounts.isEmpty else { return 0 }

        let fm = FileManager.default
        let folder = settings.importFolder
        guard let files = try? fm.contentsOfDirectory(at: folder,
                                                      includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return 0 }
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        var processed = Set(settings.processedImports)
        var added = 0
        var touched: [String] = []

        for url in files where url.pathExtension.lowercased() == "csv" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard modified >= cutoff else { continue }
            let key = "\(url.path)|\(Int(modified.timeIntervalSince1970))"
            guard !processed.contains(key), let data = try? Data(contentsOf: url) else { continue }

            guard let export = try? TradovateImporter.parse(data: data) else {
                processed.insert(key)          // not a Tradovate file — never look at it again
                continue
            }
            let result = importTradovate(export, into: tradovateAccounts)
            added += result.added
            if result.matchedAccount {
                processed.insert(key)
                touched.append(url.lastPathComponent)
            }
        }

        // Keep the registry bounded.
        settings.processedImports = Array(processed.suffix(400))
        if reportStatus, added > 0 {
            syncStatus = .success("Logged \(added) new trade\(added == 1 ? "" : "s") from \(touched.first ?? "Tradovate export")")
        }
        return added
    }

    /// Routes an export's rows to the right TradeSync accounts by broker account number.
    /// An account with no number is bound automatically when the file holds exactly one.
    private func importTradovate(_ export: TradovateExport,
                                 into candidates: [TradingAccount]) -> (added: Int, matchedAccount: Bool) {
        var added = 0
        var matched = false

        switch export {
        case .orders:
            let numbers = export.accountNumbers
            for number in numbers {
                if var account = candidates.first(where: {
                    $0.brokerAccountNumber.caseInsensitiveCompare(number) == .orderedSame
                }) ?? unboundAccount(candidates, fileAccounts: numbers) {
                    if account.brokerAccountNumber.isEmpty {
                        account.brokerAccountNumber = number
                        saveAccount(account)
                    }
                    let trades = TradovateImporter.trades(from: export, accountNumber: number, account: account)
                    added += merge(imported: trades)
                    markSynced(account.id)
                    matched = true
                }
            }
        case .performance:
            // No account column: only safe when there's a single Tradovate account.
            if candidates.count == 1 {
                let account = candidates[0]
                added += merge(imported: TradovateImporter.trades(from: export, accountNumber: nil, account: account))
                markSynced(account.id)
                matched = true
            }
        }
        return (added, matched)
    }

    private func unboundAccount(_ candidates: [TradingAccount], fileAccounts: Set<String>) -> TradingAccount? {
        let unbound = candidates.filter { $0.brokerAccountNumber.isEmpty }
        let bound = Set(candidates.map { $0.brokerAccountNumber.uppercased() })
        let unknown = fileAccounts.filter { !bound.contains($0.uppercased()) }
        return (unbound.count == 1 && unknown.count == 1) ? unbound[0] : nil
    }

    /// Manual "Import export…" for one account; takes every row when the account has no number yet.
    func importTradovateFile(at url: URL, into accountId: UUID) throws -> Int {
        guard var account = account(for: accountId) else { return 0 }
        let export = try TradovateImporter.parse(data: try Data(contentsOf: url))
        var number: String? = account.brokerAccountNumber.isEmpty ? nil : account.brokerAccountNumber
        if number == nil, export.accountNumbers.count > 1 {
            throw TradovateImportError.ambiguousAccount(export.accountNumbers.sorted())
        }
        if number == nil, export.accountNumbers.count == 1, let only = export.accountNumbers.first {
            number = only
            account.brokerAccountNumber = only
            saveAccount(account)
        }
        let trades = TradovateImporter.trades(from: export, accountNumber: number, account: account)
        guard !trades.isEmpty else { throw TradovateImportError.noClosedTrades }
        let added = merge(imported: trades)
        markSynced(account.id)
        return added
    }

    private func markSynced(_ id: UUID) {
        if var a = account(for: id) {
            a.lastSync = Date()
            saveAccount(a)
        }
    }
}