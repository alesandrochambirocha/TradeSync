import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings
// Accounts (live, funded, evaluation), how each one connects, automatic sync,
// and local data.

struct SettingsView: View {
    @EnvironmentObject var store: TradeStore
    @State private var editing: TradingAccount? = nil
    @State private var importMessage: String? = nil
    @State private var importIsError = false
    @State private var confirmClearAll = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                accountsSection
                autoSyncSection
                tradovateGuide
                startupSection
                csvSection
                dataSection
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PageHeader(title: "Settings", subtitle: "Accounts, automatic sync & data")
                .background(Theme.bg)
        }
        .sheet(item: $editing) { account in
            AccountEditorSheet(account: account, isNew: store.account(for: account.id) == nil)
                .environmentObject(store)
        }
    }

    // MARK: Accounts

    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Accounts",
                              subtitle: "Each account keeps its own trades and stats. Switch between them from the sidebar.")
                Spacer()
                Button {
                    editing = TradingAccount(name: "", type: .live, firm: "Personal Broker", connection: .metaTrader5, startingBalance: 10_000)
                } label: {
                    Label("Add Account", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            }
            VStack(spacing: 8) {
                ForEach(store.accounts) { account in
                    accountRow(account)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func accountRow(_ account: TradingAccount) -> some View {
        let count = store.trades.filter { $0.accountId == account.id }.count
        let pnl = store.trades.filter { $0.accountId == account.id }.reduce(0.0) { $0 + $1.netPnL }
        return HStack(spacing: 12) {
            Image(systemName: account.connection == .manual ? "square.and.pencil" : "bolt.horizontal.circle.fill")
                .font(.system(size: 15))
                .foregroundColor(account.isAutoSynced ? Theme.accent : Theme.textTertiary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    TagChip(text: account.type.rawValue, color: Theme.textSecondary)
                }
                Text([account.firm,
                      account.connection.rawValue,
                      account.brokerAccountNumber.isEmpty ? nil : "#\(account.brokerAccountNumber)",
                      account.lastSync.map { "synced \(Fmt.dateTime.string(from: $0))" }]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.signedMoney(pnl, decimals: 0))
                    .font(.mono(12, .bold))
                    .foregroundColor(Theme.pnl(pnl))
                Text("\(count) trade\(count == 1 ? "" : "s")")
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.textTertiary)
            }
            switch account.connection {
            case .metaTrader5:
                Button("Sync") { Task { await store.syncMetaTrader(accountId: account.id) } }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!account.metaApi.isConfigured)
            case .tradovateExport:
                Button("Import Export…") { importTradovate(into: account) }
                    .buttonStyle(PillButtonStyle())
            case .manual:
                EmptyView()
            }
            Button("Edit") { editing = account }
                .buttonStyle(PillButtonStyle())
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.bg.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.strokeSoft, lineWidth: 1))
    }

    private func importTradovate(into account: TradingAccount) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose the Orders CSV exported from Tradovate"
        panel.directoryURL = store.settings.importFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let added = try store.importTradovateFile(at: url, into: account.id)
            store.syncStatus = .success("\(account.name): logged \(added) new trade\(added == 1 ? "" : "s")")
        } catch {
            store.syncStatus = .failure(error.localizedDescription)
        }
    }

    // MARK: Auto-sync

    private var autoSyncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Automatic Sync",
                              subtitle: "Trades are logged for you. You only add screenshots and your reasoning.")
                Spacer()
                syncStatusLabel
            }
            FormRow(label: "Auto-sync") {
                Toggle("", isOn: Binding(
                    get: { store.settings.autoSyncEnabled },
                    set: { store.settings.autoSyncEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                Text("MT5 every")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                Picker("", selection: Binding(
                    get: { store.settings.syncIntervalMinutes },
                    set: { store.settings.syncIntervalMinutes = $0 }
                )) {
                    Text("5 min").tag(5)
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("60 min").tag(60)
                }
                .labelsHidden()
                .frame(width: 90)
                Spacer()
            }
            FormRow(label: "Watch folder") {
                Text(store.settings.importFolder.path)
                    .font(.mono(10.5, .medium))
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") { chooseFolder() }
                    .buttonStyle(PillButtonStyle())
            }
            Text("Tradovate exports saved here are picked up within a minute. Files from other apps are ignored, and re-exporting the same days never creates duplicates.")
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
            HStack {
                Button {
                    Task { await store.syncAll() }
                } label: {
                    Label("Sync All Accounts Now", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                Text("⌘R")
                    .font(.mono(10, .medium))
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = store.settings.importFolder
        panel.message = "Choose the folder your Tradovate exports download to"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.settings.importFolderPath = url.path
    }

    private var syncStatusLabel: some View {
        Group {
            switch store.syncStatus {
            case .idle:
                EmptyView()
            case .syncing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Syncing…")
                }
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
            case .success(let msg):
                Label(msg, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.green)
                    .lineLimit(2)
            case .failure(let msg):
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.red)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: 360, alignment: .trailing)
    }

    // MARK: Tradovate guide

    private var tradovateGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Connecting Tradeify and other Tradovate prop accounts",
                          subtitle: "Tradovate doesn't offer API access for prop firm or evaluation accounts, so the journal reads Tradovate's own trade report.")
            VStack(alignment: .leading, spacing: 7) {
                step(1, "Add an account above with the firm set to Tradeify and the connection set to Tradovate.")
                step(2, "In Tradovate, open Account Reports and choose the Orders tab.")
                step(3, "Pick the date range, then download the CSV. It saves to your Downloads folder.")
                step(4, "TradeSync imports it within a minute: entry, exit, stop loss, take profit, contracts, times and P&L are all filled in from your orders.")
            }
            Text("Tradovate reports don't include fees. Set your commission per contract on the account so net P&L matches your dashboard.")
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(n)")
                .font(.mono(9.5, .bold))
                .frame(width: 17, height: 17)
                .background(Circle().fill(Theme.accent))
                .foregroundColor(Theme.onAccent)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Startup

    private var startupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Startup", subtitle: "The opening screen you see when TradeSync launches")
            FormRow(label: "Your name") {
                TextField("shown on the welcome screen", text: Binding(
                    get: { store.settings.traderName },
                    set: { store.settings.traderName = $0 }
                ))
                .inputStyle()
                .frame(maxWidth: 240)
                Spacer()
            }
            HStack {
                Toggle("", isOn: Binding(
                    get: { store.settings.showWelcomeOnLaunch },
                    set: { store.settings.showWelcomeOnLaunch = $0 }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                Text("Show the welcome screen on launch")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Button("Preview") { store.showWelcome = true }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Generic CSV

    private var csvSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Other CSV Import",
                          subtitle: "MetaTrader report exports or the TradeSync template, into the selected account")
            HStack(spacing: 10) {
                Button {
                    openCSV()
                } label: {
                    Label("Import CSV…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(PillButtonStyle())

                Button {
                    saveTemplate()
                } label: {
                    Label("Save Template…", systemImage: "doc.badge.plus")
                }
                .buttonStyle(PillButtonStyle())

                Spacer()
                if let importMessage {
                    Label(importMessage, systemImage: importIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(importIsError ? Theme.red : Theme.green)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func openCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose a CSV file with your trades"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let target = store.defaultAccountId
            let label = store.account(for: target)?.name ?? ""
            let trades = try CSVImporter.parse(data: try Data(contentsOf: url), accountLabel: label).map { t in
                var t = t
                t.accountId = target
                return t
            }
            let added = store.merge(imported: trades)
            importMessage = "Imported \(added) new trade\(added == 1 ? "" : "s") into \(label)"
            importIsError = false
        } catch {
            importMessage = error.localizedDescription
            importIsError = true
        }
    }

    private func saveTemplate() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "tradesync-template.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? CSVImporter.templateCSV.data(using: .utf8)?.write(to: url)
    }

    // MARK: Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Data", subtitle: "Everything is stored locally on your Mac")
            HStack(spacing: 10) {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Backup…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PillButtonStyle())

                Button {
                    exportTradesCSV()
                } label: {
                    Label("Export Trades CSV…", systemImage: "tablecells")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(store.scopedTrades.isEmpty)

                if store.hasSampleData {
                    Button("Remove Sample Data") { store.clearSampleData() }
                        .buttonStyle(PillButtonStyle())
                } else {
                    Button("Load Sample Data") { store.seedSampleData() }
                        .buttonStyle(PillButtonStyle())
                }

                Button("Delete All Trades…") { confirmClearAll = true }
                    .buttonStyle(PillButtonStyle(destructive: true))
                Spacer()
            }
            Text("Data file: \(TradeStore.dataFile.path)")
                .font(.system(size: 10))
                .foregroundColor(Theme.textTertiary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .alert("Delete all trades?", isPresented: $confirmClearAll) {
            Button("Delete Everything", role: .destructive) {
                for t in store.trades { store.deleteScreenshots(of: t) }
                store.trades.removeAll()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes every trade in every account, including their screenshots. Accounts and session recaps are kept. This cannot be undone.")
        }
    }

    private func exportTradesCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "tradesync-trades.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        func esc(_ s: String) -> String {
            s.contains(",") || s.contains("\"") || s.contains("\n")
                ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
        }
        var csv = "account,symbol,direction,volume,entry_time,entry_price,exit_time,exit_price,pnl,commission,swap,stop_loss,take_profit,confluences,mistakes,rating,notes\n"
        for t in store.scopedTrades.sorted(by: { $0.exitTime < $1.exitTime }) {
            csv += [
                esc(store.account(for: t.accountId)?.name ?? ""),
                t.symbol,
                t.direction == .long ? "buy" : "sell",
                Fmt.volume(t.volume),
                df.string(from: t.entryTime),
                String(t.entryPrice),
                df.string(from: t.exitTime),
                String(t.exitPrice),
                String(format: "%.2f", t.grossPnL),
                String(format: "%.2f", t.commission),
                String(format: "%.2f", t.swap),
                t.stopLoss.map { String($0) } ?? "",
                t.takeProfit.map { String($0) } ?? "",
                esc(t.setups.joined(separator: "; ")),
                esc(t.mistakes.joined(separator: "; ")),
                String(t.rating),
                esc(t.notes)
            ].joined(separator: ",") + "\n"
        }
        try? csv.data(using: .utf8)?.write(to: url)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "tradesync-backup.json"
        guard panel.runModal() == .OK, let url = panel.url, let data = store.exportJSON() else { return }
        try? data.write(to: url)
    }
}

// MARK: - Account editor

struct AccountEditorSheet: View {
    @EnvironmentObject var store: TradeStore
    @Environment(\.dismiss) var dismiss
    @State var account: TradingAccount
    let isNew: Bool
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "Add Account" : "Edit Account")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider().overlay(Theme.stroke)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        RailLabel(text: "Account")
                        HStack(alignment: .top, spacing: 12) {
                            Field(label: "Name") {
                                TextField("e.g. IC Markets Live, Tradeify 50K", text: $account.name).inputStyle()
                            }
                            Field(label: "Starting Balance ($)") {
                                TextField("50000", value: $account.startingBalance, format: .number.locale(Locale(identifier: "en_US"))).inputStyle()
                            }
                        }
                        Field(label: "Type") {
                            Picker("", selection: $account.type) {
                                ForEach(AccountType.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        RailLabel(text: "Prop Firm / Broker")
                        HStack(alignment: .top, spacing: 12) {
                            Field(label: "Firm") {
                                Picker("", selection: $account.firm) {
                                    ForEach(PropFirm.presets) { Text($0.name).tag($0.name) }
                                    if PropFirm.preset(named: account.firm) == nil {
                                        Text(account.firm).tag(account.firm)
                                    }
                                }
                                .labelsHidden()
                                .onChange(of: account.firm) {
                                    if isNew, let preset = PropFirm.preset(named: account.firm) {
                                        account.connection = preset.suggested
                                    }
                                }
                            }
                            Field(label: "Connection") {
                                Picker("", selection: $account.connection) {
                                    ForEach(ConnectionKind.allCases) { Text($0.rawValue).tag($0) }
                                }
                                .labelsHidden()
                            }
                        }
                        if let note = PropFirm.preset(named: account.firm)?.note, !note.isEmpty {
                            Text(note)
                                .font(.system(size: 10.5))
                                .foregroundColor(Theme.textTertiary)
                        }
                        Text(account.connection.detail)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.card))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.stroke, lineWidth: 1))
                    }

                    connectionFields
                }
                .padding(20)
            }

            Divider().overlay(Theme.stroke)
            HStack {
                if !isNew {
                    Button("Delete Account…") { confirmDelete = true }
                        .buttonStyle(PillButtonStyle(destructive: true))
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PillButtonStyle())
                Button(isNew ? "Add Account" : "Save") {
                    account.name = account.name.trimmingCharacters(in: .whitespaces)
                    account.brokerAccountNumber = account.brokerAccountNumber.trimmingCharacters(in: .whitespaces)
                    store.saveAccount(account)
                    if isNew { store.selectAccount(account.id) }
                    // A new MT5 account connects and pulls its full history straight away.
                    if isNew, account.connection == .metaTrader5, account.metaApi.isConfigured {
                        let id = account.id
                        Task {
                            await store.testMetaTraderConnection(accountId: id)
                            await store.syncMetaTrader(accountId: id, fullHistory: true)
                        }
                    }
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(account.name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(account.name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
        }
        .frame(width: 640, height: 640)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .alert("Delete \(account.name)?", isPresented: $confirmDelete) {
            Button("Delete Account & Trades", role: .destructive) {
                store.deleteAccount(account)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All trades and screenshots in this account are permanently removed.")
        }
    }

    @ViewBuilder
    private var connectionFields: some View {
        switch account.connection {
        case .tradovateExport:
            VStack(alignment: .leading, spacing: 10) {
                RailLabel(text: "Tradovate")
                HStack(alignment: .top, spacing: 12) {
                    Field(label: "Tradovate Account Number",
                          hint: "As shown in Tradovate and in the export's Account column. Leave blank to fill it from your first export.") {
                        TextField("filled from your first export", text: $account.brokerAccountNumber).inputStyle()
                    }
                    Field(label: "Commission / Contract / Side ($)",
                          hint: "Tradovate exports don't include fees. Use your firm's per-side rate.") {
                        TextField("0.00", value: $account.commissionPerContractSide, format: .number.locale(Locale(identifier: "en_US"))).inputStyle()
                    }
                }
            }
        case .metaTrader5:
            VStack(alignment: .leading, spacing: 10) {
                RailLabel(text: "MetaTrader 5 via MetaApi")
                Text("Create a free account at metaapi.cloud, add your MT5 login there (the read-only investor password is enough), then paste the API token and the MetaApi account ID here.")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Field(label: "API Token") {
                    SecureField("MetaApi auth token", text: $account.metaApi.token).inputStyle()
                }
                HStack(alignment: .top, spacing: 12) {
                    Field(label: "MetaApi Account ID") {
                        TextField("865d3a4d-…", text: $account.metaApi.accountId).inputStyle()
                    }
                    Field(label: "Region") {
                        Text(account.metaApi.connectedAccountName == nil
                             ? "Detected automatically"
                             : account.metaApi.region)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.vertical, 7)
                            .help("TradeSync asks MetaApi where your account is hosted, so there's nothing to choose.")
                    }
                }
                if !isNew {
                    HStack {
                        Button("Test Connection") {
                            store.saveAccount(account)
                            Task { await store.testMetaTraderConnection(accountId: account.id) }
                        }
                        .buttonStyle(PillButtonStyle())
                        .disabled(!account.metaApi.isConfigured)
                        Button("Import Full History") {
                            store.saveAccount(account)
                            Task { await store.syncMetaTrader(accountId: account.id, fullHistory: true) }
                        }
                        .buttonStyle(PillButtonStyle())
                        .disabled(!account.metaApi.isConfigured)
                    }
                }
            }
        case .manual:
            EmptyView()
        }
    }
}