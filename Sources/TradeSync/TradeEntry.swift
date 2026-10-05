import SwiftUI
import AppKit

// MARK: - Trade entry / edit
//
// The single place a trade is created or edited. Captures everything the daily
// journal needs: instrument, direction, contract size, entry/stop/target,
// realized P&L, confluences, and TradingView screenshots.

struct TradeEntrySheet: View {
    @EnvironmentObject var store: TradeStore
    @Environment(\.dismiss) var dismiss

    let existing: Trade?
    let dayKey: String

    @State private var symbol = ""
    @State private var assetClass: AssetClass = .futures
    @State private var direction: TradeDirection = .long
    @State private var contracts = "1"
    @State private var entryPrice = ""
    @State private var exitPrice = ""
    @State private var stopLoss = ""
    @State private var takeProfit = ""
    @State private var pnl = ""
    @State private var commission = ""
    @State private var entryTime = Date()
    @State private var exitTime = Date()
    @State private var confluenceTags: [String] = []
    @State private var reason = ""
    @State private var mistakes: [String] = []
    @State private var rating = 0
    @State private var screenshots: [String] = []
    @State private var accountId: UUID? = nil
    @State private var editExecution = false
    @State private var error: String? = nil

    /// Executions came from the broker; the trader only adds their own context.
    private var isSynced: Bool { existing?.source.isBrokerSynced == true }

    init(existing: Trade?, dayKey: String) {
        self.existing = existing
        self.dayKey = dayKey
        let day = Fmt.dayKey.date(from: dayKey) ?? Date()
        let cal = Calendar.current
        if let t = existing {
            _symbol = State(initialValue: t.symbol)
            _assetClass = State(initialValue: t.assetClass)
            _direction = State(initialValue: t.direction)
            _contracts = State(initialValue: Fmt.volume(t.volume))
            _entryPrice = State(initialValue: t.entryPrice == 0 ? "" : Fmt.plain(t.entryPrice))
            _exitPrice = State(initialValue: t.exitPrice == 0 ? "" : Fmt.plain(t.exitPrice))
            _stopLoss = State(initialValue: t.stopLoss.map(Fmt.plain) ?? "")
            _takeProfit = State(initialValue: t.takeProfit.map(Fmt.plain) ?? "")
            _pnl = State(initialValue: String(format: "%.2f", t.grossPnL))
            _commission = State(initialValue: t.commission == 0 ? "" : String(format: "%.2f", t.commission))
            _entryTime = State(initialValue: t.entryTime)
            _exitTime = State(initialValue: t.exitTime)
            _confluenceTags = State(initialValue: t.setups)
            _reason = State(initialValue: t.notes)
            _mistakes = State(initialValue: t.mistakes)
            _rating = State(initialValue: t.rating)
            _screenshots = State(initialValue: t.screenshots)
            _accountId = State(initialValue: t.accountId)
        } else {
            _entryTime = State(initialValue: cal.date(bySettingHour: 9, minute: 30, second: 0, of: day) ?? day)
            _exitTime = State(initialValue: cal.date(bySettingHour: 10, minute: 15, second: 0, of: day) ?? day)
        }
    }

    // MARK: derived

    /// $ per point. When P&L is typed it can be implied from the price move;
    /// otherwise it must come from a spec/default (P&L is derived from it).
    private var resolvedPointValue: Double? {
        Contracts.resolvedPointValue(symbol: symbol, assetClass: assetClass, direction: direction,
                                     entry: Double(entryPrice) ?? 0, exit: Double(exitPrice) ?? 0,
                                     volume: volumeValue, grossPnL: Double(pnl))
    }
    private var pointValue: Double { resolvedPointValue ?? 1 }
    private var volumeValue: Double { Double(contracts) ?? 1 }

    /// P&L implied by entry → exit, when the user hasn't typed one.
    private var computedPnL: Double? {
        guard let ep = Double(entryPrice), let xp = Double(exitPrice), ep > 0, xp > 0,
              let pv = Contracts.pointValue(for: symbol)
                ?? Contracts.classDefaultPointValue(for: symbol, assetClass: assetClass) else { return nil }
        let move = direction == .long ? xp - ep : ep - xp
        return (move * volumeValue * pv * 100).rounded() / 100
    }

    private var effectivePnL: Double? {
        if let typed = Double(pnl) { return typed }
        return computedPnL
    }

    private var plannedRisk: Double? {
        guard resolvedPointValue != nil,
              let ep = Double(entryPrice), let sl = Double(stopLoss), ep > 0, sl > 0 else { return nil }
        let risk = abs(ep - sl) * volumeValue * pointValue
        return risk > 0 ? risk : nil
    }

    private var plannedReward: Double? {
        guard resolvedPointValue != nil,
              let ep = Double(entryPrice), let tp = Double(takeProfit), ep > 0, tp > 0 else { return nil }
        let reward = abs(tp - ep) * volumeValue * pointValue
        return reward > 0 ? reward : nil
    }

    private var rMultiple: Double? {
        guard let risk = plannedRisk, let p = effectivePnL else { return nil }
        let net = p + (Double(commission) ?? 0)
        return net / risk
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isSynced && !editExecution {
                        syncedExecutionCard
                        screenshotSection
                        confluenceSection
                        reviewSection
                    } else {
                        accountSection
                        instrumentSection
                        levelsSection
                        resultSection
                        riskStrip
                        confluenceSection
                        screenshotSection
                        reviewSection
                    }
                }
                .padding(20)
            }
            Divider().overlay(Theme.stroke)
            footer
        }
        .frame(width: 780, height: 720)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onAppear {
            if accountId == nil { accountId = store.defaultAccountId }
        }
        .background(
            // ⌘V pastes a chart screenshot from anywhere in the sheet.
            Button("") { if let n = store.screenshotFromClipboard() { screenshots.append(n) } }
                .keyboardShortcut("v", modifiers: .command)
                .opacity(0)
        )
    }

    // MARK: header / footer

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(existing == nil ? "Log Trade" : (isSynced ? "Review Trade" : "Edit Trade"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                Text(Fmt.weekdayDate.string(from: Fmt.dayKey.date(from: dayKey) ?? Date()))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
            Spacer()
            if let p = effectivePnL {
                let net = p + (Double(commission) ?? 0)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.signedMoney(net))
                        .font(.mono(19, .bold))
                        .foregroundColor(Theme.pnl(net))
                    if let r = rMultiple {
                        Text(Fmt.rMultiple(r))
                            .font(.mono(10, .semibold))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundColor(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            if let existing {
                Button("Delete Trade") {
                    store.delete(existing)
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(destructive: true))
            }
            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.red)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(PillButtonStyle())
            Button(existing == nil ? "Log Trade" : "Save Changes") { save() }
                .buttonStyle(PillButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }

    // MARK: sections

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailLabel(text: "Account")
            Picker("", selection: $accountId) {
                ForEach(store.accounts) { a in
                    Text("\(a.name) — \(a.subtitle)").tag(Optional(a.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360, alignment: .leading)
        }
    }

    /// Read-only execution summary for broker-synced trades.
    private var syncedExecutionCard: some View {
        let account = store.account(for: existing?.accountId)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.green)
                Text("Execution synced from \(existing?.source.rawValue ?? "broker")")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                if let account {
                    Text("· \(account.name)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Button("Correct broker data") { editExecution = true }
                    .buttonStyle(PillButtonStyle())
            }
            Text("Everything below was recorded for you. Add your chart and your reasoning.")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textTertiary)

            HStack(spacing: 0) {
                execCell("Symbol", symbol)
                execCell("Side", direction.rawValue, direction == .long ? Theme.green : Theme.red)
                execCell(Contracts.unitLabel(for: assetClass), contracts)
                execCell("Entry", entryPrice.isEmpty ? "—" : entryPrice)
                execCell("Exit", exitPrice.isEmpty ? "—" : exitPrice)
            }
            HStack(spacing: 0) {
                execCell("Stop Loss", stopLoss.isEmpty ? "—" : stopLoss, Theme.red)
                execCell("Take Profit", takeProfit.isEmpty ? "—" : takeProfit, Theme.green)
                execCell("Time", "\(Fmt.shortTimeHM.string(from: entryTime))–\(Fmt.shortTimeHM.string(from: exitTime))")
                execCell("Fees", commission.isEmpty ? "$0.00" : Fmt.money(Double(commission) ?? 0))
                execCell("Realized R", rMultiple.map(Fmt.rMultiple) ?? "—", rMultiple.map { Theme.pnl($0) } ?? Theme.textTertiary)
            }
        }
        .card()
    }

    private func execCell(_ label: String, _ value: String, _ color: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.mono(12.5, .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instrumentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailLabel(text: "Instrument")
            HStack(alignment: .top, spacing: 12) {
                Field(label: "Symbol") {
                    TextField("NQ", text: $symbol)
                        .inputStyle()
                        .onChange(of: symbol) { autoClassify() }
                }
                Field(label: "Direction") {
                    Picker("", selection: $direction) {
                        ForEach(TradeDirection.allCases) { d in Text(d.rawValue).tag(d) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Field(label: Contracts.unitLabel(for: assetClass),
                      hint: "Contract size / position size for this trade") {
                    TextField("1", text: $contracts).inputStyle()
                }
                Field(label: "Market") {
                    Picker("", selection: $assetClass) {
                        ForEach(AssetClass.allCases) { a in Text(a.rawValue).tag(a) }
                    }
                    .labelsHidden()
                }
            }
            // quick picks
            HStack(spacing: 5) {
                ForEach(Contracts.quickPicks, id: \.self) { s in
                    Button {
                        symbol = s
                        autoClassify()
                    } label: {
                        Text(s)
                            .font(.mono(10, .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(symbol.uppercased() == s ? Theme.accent.opacity(0.2) : Theme.cardElev))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
                                symbol.uppercased() == s ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1))
                            .foregroundColor(symbol.uppercased() == s ? Theme.accent : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private var levelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailLabel(text: "Levels")
            HStack(alignment: .top, spacing: 12) {
                Field(label: "Entry Price") {
                    TextField("0.00", text: $entryPrice).inputStyle()
                }
                Field(label: "Stop Loss") {
                    TextField("0.00", text: $stopLoss).inputStyle()
                }
                Field(label: "Take Profit") {
                    TextField("0.00", text: $takeProfit).inputStyle()
                }
                Field(label: "Exit Price", hint: "Optional — fills P&L automatically when set") {
                    TextField("optional", text: $exitPrice).inputStyle()
                }
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailLabel(text: "Result")
            HStack(alignment: .top, spacing: 12) {
                Field(label: "P&L ($)", hint: "Leave blank to calculate from entry and exit price") {
                    TextField(computedPnL.map { String(format: "auto: %.2f", $0) } ?? "0.00", text: $pnl)
                        .inputStyle()
                }
                Field(label: "Commission ($)") {
                    TextField("-4.50", text: $commission).inputStyle()
                }
                Field(label: "Entry Time") {
                    DatePicker("", selection: $entryTime, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                }
                Field(label: "Exit Time") {
                    DatePicker("", selection: $exitTime, displayedComponents: [.hourAndMinute])
                        .labelsHidden()
                }
            }
        }
    }

    private var riskStrip: some View {
        HStack(spacing: 0) {
            riskCell("$ / Point", resolvedPointValue.map { Fmt.money($0, decimals: $0 < 10 ? 2 : 0) } ?? "—",
                     Theme.textSecondary)
            riskDivider
            riskCell("Planned Risk", plannedRisk.map { Fmt.money($0) } ?? "—", Theme.red)
            riskDivider
            riskCell("Planned Reward", plannedReward.map { Fmt.money($0) } ?? "—", Theme.green)
            riskDivider
            riskCell("Plan R:R", planRR.map { String(format: "%.2f : 1", $0) } ?? "—", Theme.accent)
            riskDivider
            riskCell("Realized R", rMultiple.map(Fmt.rMultiple) ?? "—",
                     rMultiple.map { Theme.pnl($0) } ?? Theme.textTertiary)
        }
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private var planRR: Double? {
        guard let risk = plannedRisk, let reward = plannedReward, risk > 0 else { return nil }
        return reward / risk
    }

    private func riskCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.mono(12, .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }

    private var riskDivider: some View {
        Rectangle().fill(Theme.strokeSoft).frame(width: 1, height: 26)
    }

    private var confluenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailLabel(text: "Confluences")
            TagEditorView(tags: $confluenceTags,
                          vocabulary: (store.allSetups + Vocabulary.confluences).uniqued(),
                          color: Theme.accent,
                          placeholder: "Add your own confluence and press ⏎")
            VStack(alignment: .leading, spacing: 5) {
                Text("WHY I TOOK THIS TRADE")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.7)
                    .foregroundColor(Theme.textTertiary)
                TextEditor(text: $reason)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(height: 78)
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.inputBG))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
    }

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailLabel(text: "Chart Screenshots")
            ScreenshotWell(screenshots: $screenshots)
        }
    }

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RailLabel(text: "Review")
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MISTAKES")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundColor(Theme.textTertiary)
                    TagEditorView(tags: $mistakes, vocabulary: Vocabulary.mistakes,
                                  color: Theme.red, placeholder: "Custom mistake + ⏎")
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("EXECUTION GRADE")
                        .font(.system(size: 8.5, weight: .bold))
                        .tracking(0.7)
                        .foregroundColor(Theme.textTertiary)
                    StarRating(rating: $rating)
                }
                .frame(width: 140)
            }
        }
    }

    // MARK: actions

    private func autoClassify() {
        let s = symbol.uppercased()
        guard !s.isEmpty else { return }
        if Contracts.pointValue(for: s) != nil { assetClass = .futures }
        else { assetClass = MetaApiService.classify(symbol: s) }
    }

    private func save() {
        let sym = symbol.trimmingCharacters(in: .whitespaces).uppercased()
        guard !sym.isEmpty else { error = "Enter a symbol (e.g. NQ or ES)."; return }
        guard let grossPnL = effectivePnL else {
            error = "Enter the trade's P&L, or fill entry + exit price so it can be calculated."
            return
        }

        // Anchor both timestamps to the journal day this trade belongs to.
        let day = Fmt.dayKey.date(from: dayKey) ?? Date()
        let cal = Calendar.current
        func onDay(_ time: Date) -> Date {
            let c = cal.dateComponents([.hour, .minute, .second], from: time)
            return cal.date(bySettingHour: c.hour ?? 9, minute: c.minute ?? 30, second: c.second ?? 0, of: day) ?? day
        }
        var entry = onDay(entryTime)
        var exit = onDay(exitTime)
        if exit < entry { exit = entry }
        if entry > exit { entry = exit }

        var t = existing ?? Trade(symbol: sym, direction: direction,
                                  entryTime: entry, exitTime: exit,
                                  entryPrice: 0, exitPrice: 0, volume: 1, grossPnL: 0)
        t.symbol = sym
        t.assetClass = assetClass
        t.direction = direction
        t.entryTime = entry
        t.exitTime = exit
        t.entryPrice = Double(entryPrice) ?? 0
        t.exitPrice = Double(exitPrice) ?? (Double(entryPrice) ?? 0)
        t.volume = volumeValue
        t.grossPnL = grossPnL
        t.commission = Double(commission) ?? 0
        t.stopLoss = Double(stopLoss)
        t.takeProfit = Double(takeProfit)
        t.setups = confluenceTags
        t.mistakes = mistakes
        t.rating = rating
        t.notes = reason
        t.screenshots = screenshots
        t.accountId = accountId ?? store.defaultAccountId
        if existing == nil { t.source = .manual }

        if existing == nil { store.add(t) } else { store.update(t) }
        store.openJournalDay(dayKey)
        dismiss()
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
