import SwiftUI
import AppKit

// MARK: - Welcome
//
// The greeting is written in a script face behind a soft ink edge. Leaving is
// a shade going up: the welcome clears from the bottom, a band of mist and a
// fine scan line ride the edge, and the dashboard rises into place beneath.
// A single mouse-wheel notch plays the whole rise; a trackpad scrubs it.

struct WelcomeView: View {
    @EnvironmentObject var store: TradeStore
    var onEnter: () -> Void

    @State private var writeProgress: CGFloat = 0     // 0…1 ink reveal
    @State private var phase = 0                      // staggered reveal step
    @State private var committed = false              // the rise is playing out
    @State private var monitor: Any? = nil
    @State private var decayTimer: Timer? = nil
    @State private var lastScroll = Date.distantPast
    @State private var ringTurn = false
    @State private var askingName = false             // first launch: no name saved yet
    @State private var greetedFirstTime = false       // "Welcome, …" rather than "Welcome back, …"
    @State private var nameDraft = ""
    @FocusState private var nameFocused: Bool

    /// Lighter cut of the script; everything else stays on the system font.
    private let scriptFont = Font.custom("SnellRoundhand", size: 80)

    /// Height of the soft edge where welcome gives way to dashboard.
    private let feather: CGFloat = 280

    private var reveal: CGFloat { store.welcomeReveal }
    /// The shade starts lifting just after the text begins to dissolve.
    private var shade: CGFloat { max(0, (reveal - 0.12) / 0.88) }

    private var greeting: String {
        let n = store.settings.traderName.trimmingCharacters(in: .whitespaces)
        if askingName || n.isEmpty { return "Welcome" }
        return greetedFirstTime ? "Welcome, \(n)" : "Welcome back, \(n)"
    }

    private var trimmedDraft: String {
        String(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                welcomeLayer
                    .frame(width: size.width, height: size.height)
                    .overlay(alignment: .bottom) {
                        scrollHint
                            .opacity(phase >= 6 ? max(0, Double(1 - reveal * 3)) : 0)
                            .padding(.bottom, 44)
                    }
                    .clipped()
                    .mask(shadeMask(size))

                mistAndScanLine(size)
                    .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
        }
        .onAppear(perform: start)
        .onDisappear(perform: teardown)
        .contentShape(Rectangle())
        .onTapGesture { if !askingName { commit() } }
    }

    // MARK: layers

    private var welcomeLayer: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                ZStack {
                    hudRings
                    BrandMark(size: 84)
                        .shadow(color: .black.opacity(0.6), radius: 28, y: 14)
                }
                .opacity(phase >= 1 ? 1 : 0)
                .scaleEffect(phase >= 1 ? 1 : 0.9)
                .blur(radius: phase >= 1 ? 0 : 6)
                .padding(.bottom, 30)

                Text(WelcomeView.eyebrow())
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(2.2)
                    .foregroundColor(Theme.textTertiary)
                    .opacity(phase >= 1 ? 1 : 0)
                    .padding(.bottom, 4)

                writtenGreeting

                if askingName {
                    namePrompt
                        .opacity(phase >= 3 ? 1 : 0)
                        .offset(y: phase >= 3 ? 0 : 14)
                        .blur(radius: phase >= 3 ? 0 : 4)
                        .padding(.top, 18)
                } else {
                    lockup
                }
            }
            .padding(.horizontal, 48)
            // The lockup drifts up ahead of the shade.
            .offset(y: -reveal * 160)
            .blur(radius: reveal * 14)
            .opacity(max(0, Double(1 - reveal * 4)))
        }
    }

    /// Slogan and wordmark under the greeting.
    private var lockup: some View {
        VStack(spacing: 0) {
            Text(Brand.slogan)
                .font(.system(size: 17))
                .tracking(0.3)
                .foregroundColor(Theme.textSecondary)
                .opacity(phase >= 3 ? 1 : 0)
                .offset(y: phase >= 3 ? 0 : 14)
                .blur(radius: phase >= 3 ? 0 : 4)
                .padding(.top, 6)

            HStack(spacing: 10) {
                rule
                Wordmark(size: 11, tracking: 3.0, weight: .semibold)
                    .fixedSize()
                    .lineLimit(1)
                rule
            }
            .frame(width: 430)
            .opacity(phase >= 4 ? 1 : 0)
            .padding(.top, 26)
        }
    }

    /// First launch only: asks what to call the trader.
    private var namePrompt: some View {
        VStack(spacing: 18) {
            Text("Before we begin, what should we call you?")
                .font(.system(size: 16))
                .foregroundColor(Theme.textSecondary)

            VStack(spacing: 8) {
                TextField("", text: $nameDraft,
                          prompt: Text("Your first name").foregroundColor(Theme.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .light))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.textPrimary)
                    .focused($nameFocused)
                    .onSubmit(saveName)
                    .frame(width: 320)
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Theme.silver.opacity(nameFocused ? 0.6 : 0.3), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 320, height: 1)
            }

            Button(action: saveName) {
                HStack(spacing: 6) {
                    Text("Continue")
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .disabled(trimmedDraft.isEmpty)
            .opacity(trimmedDraft.isEmpty ? 0.45 : 1)

            Text("You can change this later in Settings.")
                .font(.system(size: 10.5))
                .foregroundColor(Theme.textTertiary)
        }
    }

    /// Opaque above the edge, feathered across it, clear below — so the
    /// welcome reads as a shade drawn upward off the dashboard.
    private func shadeMask(_ size: CGSize) -> some View {
        // y of the fully clear line; starts below the window, ends above it.
        let edge = size.height + feather - shade * (size.height + 2 * feather)
        return VStack(spacing: 0) {
            if edge > 1 {
                LinearGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: max(0, (edge - feather) / edge)),
                    .init(color: .black.opacity(0.55), location: max(0, (edge - feather * 0.45) / edge)),
                    .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .frame(height: edge)
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
    }

    /// Mist and a fine scan line riding the edge — only while the shade moves.
    private func mistAndScanLine(_ size: CGSize) -> some View {
        let edge = size.height + feather - shade * (size.height + 2 * feather)
        let lineY = edge - feather * 0.55
        // Strongest mid-rise, gone at rest.
        let presence = Double(sin(min(1, shade) * .pi))

        return ZStack {
            // Mist: a soft silver haze across the feather.
            Rectangle()
                .fill(LinearGradient(colors: [.clear,
                                              Theme.silver.opacity(0.07),
                                              Theme.navy.opacity(0.18),
                                              .clear],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size.width, height: feather * 1.1)
                .blur(radius: 26)
                .position(x: size.width / 2, y: lineY)

            // Scan line: a hairline with a quiet glow, brightest at centre.
            Rectangle()
                .fill(LinearGradient(colors: [.clear, Theme.accentBright.opacity(0.85), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: size.width * 0.82, height: 1)
                .shadow(color: Theme.accentBright.opacity(0.6), radius: 6)
                .shadow(color: Theme.slate.opacity(0.5), radius: 18)
                .position(x: size.width / 2, y: lineY)
        }
        .opacity(presence)
    }

    // MARK: pieces

    private var writtenGreeting: some View {
        Text(greeting)
            .font(scriptFont)
            .foregroundStyle(Theme.brandGradient)
            .fixedSize()
            .padding(.horizontal, 18)          // room for script flourishes
            .mask(inkMask)
            .overlay(penTip)
            .frame(height: 122)
    }

    /// A hard edge with a soft trailing gradient — ink arriving on the page.
    private var inkMask: some View {
        GeometryReader { g in
            let done = writeProgress >= 1
            HStack(spacing: 0) {
                // Once written, the mask must span the full width or the
                // soft edge clips the final letter.
                Rectangle()
                    .frame(width: done ? g.size.width : max(0, g.size.width * writeProgress - 28))
                LinearGradient(colors: [.black, .black.opacity(0.35), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: done ? 0 : 28)
                Spacer(minLength: 0)
            }
        }
    }

    private var penTip: some View {
        GeometryReader { g in
            Circle()
                .fill(RadialGradient(colors: [Theme.accentBright.opacity(0.45), .clear],
                                     center: .center, startRadius: 0, endRadius: 16))
                .frame(width: 34, height: 34)
                .position(x: g.size.width * writeProgress, y: g.size.height * 0.62)
                .opacity(writeProgress > 0.02 && writeProgress < 0.99 ? 1 : 0)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }

    /// Instrument rings behind the mark: one fine, one dashed and turning slowly.
    private var hudRings: some View {
        ZStack {
            Circle()
                .stroke(Theme.silver.opacity(0.09), lineWidth: 1)
                .frame(width: 168, height: 168)
            Circle()
                .stroke(Theme.silver.opacity(0.14),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 7]))
                .frame(width: 208, height: 208)
                .rotationEffect(.degrees(ringTurn ? 360 : 0))
                .animation(.linear(duration: 90).repeatForever(autoreverses: false), value: ringTurn)
            // Four cardinal ticks.
            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(Theme.silver.opacity(0.22))
                    .frame(width: 1, height: 9)
                    .offset(y: -122)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
        }
        .allowsHitTesting(false)
    }

    private var background: some View {
        ZStack {
            Theme.bg
                .overlay(
                    Theme.ambientGlow
                        .frame(width: 1100, height: 1100)
                        .offset(y: -60)
                        .opacity(phase >= 1 ? 1 : 0)
                )
            RadialGradient(colors: [.clear, Color.black.opacity(0.65)],
                           center: .center, startRadius: 260, endRadius: 820)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, Theme.stroke, .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1)
    }

    private var scrollHint: some View {
        VStack(spacing: 9) {
            Text("Scroll to enter")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(1.8)
                .foregroundColor(Theme.textSecondary)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.silver)
        }
        .frame(height: 44)
    }

    // MARK: sequence

    private func start() {
        ringTurn = true
        askingName = store.settings.traderName.trimmingCharacters(in: .whitespaces).isEmpty
        if askingName {
            // Write "Welcome", bring in the question, and put the cursor in the field.
            writeGreeting(after: 0.45, steps: [(1, 0.05), (3, 1.7)])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) { nameFocused = true }
        } else {
            writeGreeting(after: 0.45, steps: [(1, 0.05), (3, 2.25), (4, 2.5), (6, 2.95)])
            installMonitor()
        }
        // A trackpad scrub that stops short eases back down.
        decayTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in
            // Scheduled on the main run loop, so this always fires on the main actor.
            MainActor.assumeIsolated {
                // Only after a real trackpad scrub that has since stopped.
                guard !committed, reveal > 0, lastScroll != .distantPast,
                      Date().timeIntervalSince(lastScroll) > 0.35 else { return }
                if reveal > 0.28 { commit() }
                else { withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { store.welcomeReveal = 0 } }
            }
        }
    }

    /// Plays the ink reveal and staggers the rest of the page in behind it.
    private func writeGreeting(after delay: Double, steps: [(Int, Double)]) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.timingCurve(0.25, 0.9, 0.3, 1, duration: 1.9)) { writeProgress = 1 }
        }
        for (step, at) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                withAnimation(Theme.ease(0.75)) { phase = max(phase, step) }
            }
        }
    }

    /// Saves the name, rewrites the greeting with it, then continues as usual.
    private func saveName() {
        let name = trimmedDraft
        guard !name.isEmpty, askingName else { return }
        store.settings.traderName = name
        nameFocused = false
        withAnimation(Theme.ease(0.4)) {
            askingName = false
            greetedFirstTime = true
            phase = 1
        }
        writeProgress = 0
        writeGreeting(after: 0.3, steps: [(3, 2.1), (4, 2.35), (6, 2.8)])
        installMonitor()
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { event in
            if committed { return nil }
            guard event.type == .scrollWheel else { commit(); return nil }

            // A mouse wheel can't scrub, so one notch plays the whole rise.
            guard event.hasPreciseScrollingDeltas else { commit(); return nil }

            // Trackpad: follow the fingers, then decide when they lift.
            lastScroll = Date()
            let step = abs(event.scrollingDeltaY) / 150
            store.welcomeReveal = min(1, reveal + step)
            if event.phase == .ended || event.momentumPhase == .began {
                if reveal > 0.28 { commit() }
            }
            if reveal >= 0.995 { commit() }
            return nil
        }
    }

    /// Plays the shade the rest of the way up, then hands over to the dashboard.
    private func commit() {
        guard !committed else { return }
        committed = true
        teardown()
        let remaining = Double(1 - reveal)
        let duration = 0.45 + 0.85 * remaining          // a full rise ≈ 1.3s
        withAnimation(.timingCurve(0.55, 0.05, 0.25, 1, duration: duration)) {
            store.welcomeReveal = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { onEnter() }
    }

    private func teardown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        decayTimer?.invalidate()
        decayTimer = nil
    }

    /// "GOOD EVENING · SAT 3 OCT"
    static func eyebrow() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return (timeGreeting() + " · " + f.string(from: Date())).uppercased()
    }

    static func timeGreeting() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<18: return "Good afternoon"
        default: return "Good evening"
        }
    }
}
