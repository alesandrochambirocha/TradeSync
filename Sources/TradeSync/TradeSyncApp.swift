import SwiftUI

@main
struct TradeSyncApp: App {
    @StateObject private var store = TradeStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1220, minHeight: 740)
                .background(Theme.bg)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Log Trade…") {
                    store.page = .journal
                    store.presentAddTrade = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Trading Day…") {
                    store.page = .journal
                    store.openJournalDay(Date().dayKey)
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
            CommandMenu("Journal") {
                Button("Trade Review") {
                    store.page = .review
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Go to Today") {
                    store.page = .journal
                    store.openJournalDay(Date().dayKey)
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                Button("Sync All Accounts Now") {
                    Task { await store.syncAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if MT5Check.isRequested {
            MT5Check.run()
            return
        }
        if Snapshot.isRequested {
            Snapshot.run()
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Navigation

enum NavPage: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case journal = "Daily Journal"
    case calendar = "Calendar"
    case review = "Trade Review"
    case reports = "Reports"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .journal: return "book.pages.fill"
        case .calendar: return "calendar"
        case .review: return "chart.line.flattrend.xyaxis"
        case .reports: return "chart.bar.xaxis"
        case .settings: return "gearshape.fill"
        }
    }

    static var primary: [NavPage] { [.dashboard, .journal, .calendar, .review, .reports] }
}

struct RootView: View {
    @EnvironmentObject var store: TradeStore
    @State private var syncTimer: Timer? = nil

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Rectangle().fill(Theme.stroke).frame(width: 1)
            ZStack {
                Theme.bg.ignoresSafeArea()
                Group {
                    switch store.page {
                    case .dashboard: DashboardView()
                    case .journal: JournalView()
                    case .calendar: CalendarPageView()
                    case .review: ReviewView()
                    case .reports: ReportsView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .modifier(DashboardRise(active: store.showWelcome, progress: store.welcomeReveal))
        .overlay {
            if store.showWelcome {
                WelcomeView {
                    store.showWelcome = false
                    store.welcomeReveal = 0
                }
                    .environmentObject(store)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $store.presentAddTrade) {
            TradeEntrySheet(existing: nil, dayKey: store.selectedJournalDay)
                .environmentObject(store)
        }
        .onAppear(perform: startAutoSync)
        .onDisappear { syncTimer?.invalidate() }
    }

    /// One lightweight tick a minute: scans the watch folder and pulls any
    /// MT5 account whose sync interval has elapsed.
    private func startAutoSync() {
        guard syncTimer == nil, !Snapshot.isRequested else { return }
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in await store.autoSyncTick() }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await store.autoSyncTick()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var store: TradeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            logo
                .padding(.horizontal, 15)
                .padding(.top, 38)
                .padding(.bottom, 14)

            AccountSwitcher()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            Button {
                store.page = .journal
                store.presentAddTrade = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Log Trade")
                        .font(.system(size: 12, weight: .bold))
                    Spacer()
                    Text("⌘N")
                        .font(.mono(9, .medium))
                        .opacity(0.6)
                }
                .foregroundColor(Theme.onAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.brandGradient))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 18)

            RailLabel(text: "Navigate")
                .padding(.horizontal, 14)
                .padding(.bottom, 7)
            VStack(spacing: 2) {
                ForEach(NavPage.primary) { navButton($0) }
            }
            .padding(.horizontal, 10)

            RailLabel(text: "Discipline")
                .padding(.horizontal, 14)
                .padding(.top, 20)
                .padding(.bottom, 8)
            WinStreakCard(stats: store.stats)
                .padding(.horizontal, 12)

            Spacer(minLength: 12)

            syncFooter
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            navButton(.settings)
                .padding(.horizontal, 10)
                .padding(.bottom, 14)
        }
        .frame(width: 246)
        .background(Theme.bgSidebar)
    }

    private var logo: some View {
        HStack(spacing: 10) {
            BrandMark(size: 26)
            Wordmark(size: 12.5, tracking: 1.6)
            Spacer()
        }
    }

    @ViewBuilder
    private func navButton(_ p: NavPage) -> some View {
        let selected = store.page == p
        let badge = p == .journal ? store.reviewQueueCount : 0
        Button {
            store.page = p
        } label: {
            HStack(spacing: 10) {
                Image(systemName: p.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 18)
                    .foregroundColor(selected ? Theme.accent : Theme.textSecondary)
                Text(p.rawValue)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundColor(selected ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.mono(9, .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.accent))
                        .foregroundColor(Theme.onAccent)
                        .help("\(badge) synced trade\(badge == 1 ? "" : "s") waiting for your notes and chart")
                }
                if selected {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.accent)
                        .frame(width: 2, height: 14)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
                    .fill(selected ? Theme.cardElev : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var syncFooter: some View {
        Group {
            switch store.syncStatus {
            case .idle:
                let auto = store.accounts.filter(\.isAutoSynced).count
                if auto > 0 {
                    label(icon: "bolt.horizontal.circle.fill",
                          text: "Auto-sync on · \(auto) account\(auto == 1 ? "" : "s")", color: Theme.textSecondary)
                } else {
                    label(icon: "link.badge.plus", text: "Connect an account in Settings", color: Theme.textTertiary)
                }
            case .syncing:
                label(icon: "arrow.triangle.2.circlepath", text: "Syncing…", color: Theme.accent)
            case .success(let msg):
                label(icon: "checkmark.circle.fill", text: msg, color: Theme.green)
            case .failure:
                label(icon: "exclamationmark.triangle.fill", text: "Sync issue — see Settings", color: Theme.red)
            }
        }
    }

    private func label(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(2)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.card))
    }
}

// MARK: - Account switcher

struct AccountSwitcher: View {
    @EnvironmentObject var store: TradeStore
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 9) {
                Image(systemName: store.selectedAccount == nil ? "square.stack.3d.up.fill" : "person.crop.square.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.selectedAccount?.name ?? "All Accounts")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .lineLimit(1)
                    Text(store.selectedAccount?.subtitle
                         ?? "\(store.accounts.count) account\(store.accounts.count == 1 ? "" : "s") combined")
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Theme.radiusSmall).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall).strokeBorder(Theme.stroke, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 3) {
                RailLabel(text: "Switch Account")
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                row(id: nil, title: "All Accounts",
                    subtitle: "Combined view", icon: "square.stack.3d.up.fill", pnl: pnl(for: nil))
                Divider().overlay(Theme.strokeSoft).padding(.vertical, 3)
                ForEach(store.accounts) { a in
                    row(id: a.id, title: a.name, subtitle: a.subtitle,
                        icon: a.isAutoSynced ? "bolt.horizontal.circle.fill" : "person.crop.square.fill",
                        pnl: pnl(for: a.id))
                }
                Divider().overlay(Theme.strokeSoft).padding(.vertical, 3)
                Button {
                    open = false
                    store.page = .settings
                } label: {
                    Label("Add or manage accounts…", systemImage: "plus.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .frame(width: 290)
            .background(Theme.bgSidebar)
            .preferredColorScheme(.dark)
        }
    }

    private func pnl(for id: UUID?) -> Double {
        store.trades.filter { id == nil || $0.accountId == id }.reduce(0) { $0 + $1.netPnL }
    }

    private func row(id: UUID?, title: String, subtitle: String, icon: String, pnl: Double) -> some View {
        let selected = store.settings.selectedAccountId == id
        return Button {
            store.selectAccount(id)
            open = false
        } label: {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(selected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                        .foregroundColor(Theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundColor(Theme.textTertiary)
                }
                Spacer()
                Text(Fmt.signedMoney(pnl, decimals: 0))
                    .font(.mono(10, .bold))
                    .foregroundColor(Theme.pnl(pnl))
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Theme.accent)
                    .opacity(selected ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.cardElev : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared page chrome

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}


// MARK: - Dashboard rise
// While the welcome lifts away, the dashboard comes up from beneath it:
// slightly low, soft and dim at first, settling into place as the reveal completes.

struct DashboardRise: ViewModifier {
    let active: Bool
    let progress: CGFloat

    func body(content: Content) -> some View {
        let p = active ? progress : 1
        content
            .offset(y: (1 - p) * 60)
            .blur(radius: (1 - p) * 8)
            .opacity(Double(0.35 + 0.65 * p))
    }
}
