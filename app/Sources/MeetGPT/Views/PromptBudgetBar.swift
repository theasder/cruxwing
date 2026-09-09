import AppKit
import SwiftUI

enum CreditUsagePhase: Equatable {
    case loading
    case fresh
    case stale
    /// No account session to query a balance for. Distinct from `unavailable`
    /// (the request failed): one is fixed by signing in, the other by waiting.
    /// Collapsing them into one label makes a missing session look like a
    /// transient service failure.
    case signedOut
    case unavailable
}

/// Owns one cancellable, generation-checked balance request. Some transports
/// do not stop immediately when a Swift task is canceled, so the generation
/// guard is what prevents an older response from overwriting a newer balance.
@MainActor
final class CreditUsageLoader: ObservableObject {
    typealias Fetch = @MainActor () async throws -> PaywallUsage?

    @Published private(set) var usage: PaywallUsage?
    @Published private(set) var phase: CreditUsagePhase = .loading

    private let fetch: Fetch
    private var refreshTask: Task<Void, Never>?
    private var generation = 0

    init(fetch: @escaping Fetch = { try await PaywallAPI.usage() }) {
        self.fetch = fetch
    }

    /// `claimingTrial` is the first-launch device-trial request still in flight.
    ///
    /// Without it the badge reads "sign in for free credits" for the second that
    /// claim takes, then flips to a balance — so the very first thing a new user
    /// is told is to sign in, and it is retracted immediately. There IS an
    /// answer coming; "loading" is what that looks like.
    func refresh(enabled: Bool, claimingTrial: Bool = false) {
        refreshTask?.cancel()
        generation &+= 1
        let requestGeneration = generation

        guard enabled else {
            // Still waiting on the trial. Not signed out yet — that verdict is
            // only true once the claim has resolved and failed.
            if claimingTrial {
                usage = nil
                phase = .loading
                return
            }
            // Not a failure: there is no account session (or the backend
            // gateway is off), so there is no balance to ask for. Reporting it
            // as `unavailable` made a signed-out app indistinguishable from a
            // transient service failure.
            usage = nil
            phase = .signedOut
            return
        }
        // A cached number is useful in the popover, but it is no longer current
        // once a post-charge refresh begins. Hide it from the compact summary
        // until the generation-checked response arrives.
        phase = usage == nil ? .loading : .stale

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let live = try await self.fetch()
                guard !Task.isCancelled, requestGeneration == self.generation else { return }
                if let live {
                    self.usage = live
                    self.phase = .fresh
                } else {
                    self.phase = self.usage == nil ? .unavailable : .stale
                }
            } catch {
                guard !Task.isCancelled, requestGeneration == self.generation else { return }
                self.phase = self.usage == nil ? .unavailable : .stale
            }
        }
    }

    func clear() {
        refreshTask?.cancel()
        generation &+= 1
        usage = nil
        // Cleared because the session went away — that is signed-out, not a
        // failed request.
        phase = .signedOut
    }

    func cancel() {
        refreshTask?.cancel()
        generation &+= 1
    }
}

/// Preflight under the prompt chips: connected app identities plus an absolute
/// input-budget rail. It makes the one reversible saving action obvious without
/// pretending a rough character count is a provider invoice.
struct PromptBudgetBar: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var mcp: MCPConnectionManager
    @StateObject private var creditLoader = CreditUsageLoader()
    @State private var showSignIn = false
    private let maximumVisibleApps = 5

    private var connectedApps: [ConnectedAppIdentity] {
        var apps: [ConnectedAppIdentity] = []

        if state.googleConnected, Config.googleScopeVersion >= GoogleAuth.scopeVersion {
            let granted = Config.googleGrantedServices
            let services = GoogleService.allCases
                .filter { granted.contains($0.rawValue) }
                .map(\.label)
            if !services.isEmpty {
                apps.append(ConnectedAppIdentity(
                    id: "google",
                    name: "Google",
                    symbol: "square.grid.3x3",
                    detail: services.joined(separator: ", ")
                ))
            }
        }

        // `…IncludingMuted`, deliberately: a muted app that vanished from the
        // strip would leave the user no way to unmute it.
        apps += mcp.researchableServersIncludingMuted.map { server in
            ConnectedAppIdentity(
                id: "mcp:\(server.id)",
                name: server.id == "atlassian" ? "Atlassian" : server.name,
                symbol: server.symbol,
                detail: server.id == "atlassian" ? "Jira and Confluence" : nil
            )
        }

        apps += TeamConnectors.configured.map { service in
            ConnectedAppIdentity(
                id: "team:\(service.rawValue)",
                name: service.label,
                symbol: service.symbol,
                detail: nil
            )
        }
        return apps
    }

    var body: some View {
        let apps = connectedApps
        VStack(alignment: .leading, spacing: 6) {
            // An UNEXPECTED sign-out outranks the generic invitation: it names
            // what happened, which account, and that the connectors survived —
            // the three things missing when this last went unannounced.
            if let notice = state.signedOutNotice, state.wheesprAvailable {
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Theme.danger)
                    Text(notice.message)
                        .font(Typo.caption)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Sign in") { showSignIn = true }
                        .buttonStyle(QuietButtonStyle(prominent: true))
                    Button {
                        state.dismissSignedOutNotice()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(IconButtonStyle(size: 20))
                    .accessibilityLabel("Hide the sign-out notice")
                }
                .padding(Space.s)
                .background(Theme.danger.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                .accessibilityElement(children: .contain)
            } else if Config.llmViaBackend && state.wheesprAvailable && !state.wheesprConnected {
                HStack(spacing: Space.s) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(Theme.accent)
                    Text("Sign in for credits and sync.")
                        .font(Typo.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Spacer(minLength: 0)
                    Button("Sign in") { showSignIn = true }
                        .buttonStyle(QuietButtonStyle(prominent: true))
                }
                .padding(.horizontal, 2)
            }

            ViewThatFits(in: .horizontal) {
                appStrip(apps, visibleLimit: maximumVisibleApps)
                appStrip(apps, visibleLimit: 2)
                appStrip(apps, visibleLimit: 1)
            }

            PromptBudgetControl(
                estimate: state.promptTokenEstimate,
                connectedAppsTokenPotential: state.connectedAppsTokenPotential,
                connectedAppsEnabled: $state.useConnectedAppsInPrompts,
                connectedAppsAvailable: !apps.isEmpty,
                creditUsage: creditLoader.usage,
                creditUsagePhase: creditLoader.phase,
                freeTierMonthlyCredits: state.freeTierMonthlyCredits
            )
        }
        .task {
            refreshCreditUsage()
            // Only fetched while on a trial — that is the one place the number
            // is shown, and it is a public endpoint either way.
            await state.loadFreeTierAllowanceIfNeeded()
        }
        .sheet(isPresented: $showSignIn) {
            SignInSheet().environmentObject(state)
        }
        .onChange(of: state.aiStreaming) { _, streaming in
            guard !streaming else { return }
            refreshCreditUsage()
        }
        .onChange(of: state.wheesprConnected) { _, connected in
            if connected {
                refreshCreditUsage()
            } else {
                creditLoader.clear()
            }
        }
        .onChange(of: state.currentTier) {
            refreshCreditUsage()
        }
        .onChange(of: state.computeUsageRevision) { refreshCreditUsage() }
        .onDisappear { creditLoader.cancel() }
    }

    private func appStrip(_ apps: [ConnectedAppIdentity], visibleLimit: Int) -> some View {
        let visible = Array(apps.prefix(visibleLimit))
        let hidden = Array(apps.dropFirst(visibleLimit))
        return HStack(spacing: Space.s) {
            appBadges(visible, hidden: hidden)
            AddAppsButton()
            Spacer(minLength: 0)
        }
        .frame(height: 22)
    }

    private func refreshCreditUsage() {
        creditLoader.refresh(
            enabled: Config.llmViaBackend && state.wheesprConnected,
            claimingTrial: state.trialClaimInFlight)
    }

    @ViewBuilder
    private func appBadges(_ visible: [ConnectedAppIdentity],
                           hidden: [ConnectedAppIdentity]) -> some View {
        if visible.isEmpty {
            Label("No applications connected", systemImage: "app.dashed")
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize()
        } else {
            ForEach(visible) { app in ConnectedAppBadge(app: app) }
            if !hidden.isEmpty { ConnectedAppsOverflowBadge(apps: hidden) }
        }
    }
}

private struct ConnectedAppIdentity: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let detail: String?
}

/// One connected app, and the switch for whether THIS call uses it.
///
/// A click mutes rather than disconnects. Different calls draw on different
/// apps — a hiring call has no use for the analytics workspace — and the only
/// way to express that used to be disconnecting, which throws away an OAuth
/// grant to skip one conversation.
///
/// Muted state is legible without colour: the label carries a slash icon and
/// the badge drops to a sunken fill, so it reads as off in a screenshot and to
/// a screen reader alike.
private struct ConnectedAppBadge: View {
    @EnvironmentObject var state: AppState
    let app: ConnectedAppIdentity

    private var isMuted: Bool { state.isAppMuted(app.id) }

    var body: some View {
        Button {
            state.setApp(app.id, muted: !isMuted)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isMuted ? "slash.circle" : app.symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isMuted ? Theme.inkTertiary : Theme.accent)
                Text(app.name)
                    .font(Typo.caption.weight(.medium))
                    .foregroundStyle(isMuted ? Theme.inkTertiary : Theme.inkSecondary)
                    .strikethrough(isMuted, color: Theme.inkTertiary)
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background(Capsule().fill(isMuted ? Theme.surfaceSunken : Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .help(isMuted
            ? "\(app.name) is connected but unused. Click to bring it back into play."
            : ["\(app.name) is connected — click to skip it on this call", app.detail]
                .compactMap { $0 }
                .joined(separator: " · "))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(["\(app.name), connected", app.detail]
            .compactMap { $0 }
            .joined(separator: ", "))
        .accessibilityValue(isMuted ? "Unused" : "In use")
        .accessibilityHint(isMuted ? "Use this application again" : "Skip this application")
        .accessibilityIdentifier("apps.badge.\(app.id)")
    }
}

private struct ConnectedAppsOverflowBadge: View {
    let apps: [ConnectedAppIdentity]

    /// Имена через запятую — отдельно от строки, а не внутри интерполяции.
    private var names: String { apps.map(\.name).joined(separator: ", ") }

    var body: some View {
        Text("+\(apps.count)")
            .font(Typo.caption.weight(.semibold))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.surfaceSunken))
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .fixedSize()
            // Список имён собирается ДО строки. Вложенные скобки внутри
            // интерполяции сбивают сторожа русского текста (RussianCopyTests):
            // он вырезает \(...) до первой закрывающей скобки, и хвост
            // «.joined(separator:» остаётся в строке как латиница. Заодно
            // строка стала читаемой.
            .help("Also connected: \(names)")
            .accessibilityLabel("\(apps.count) more applications connected — \(names)")
    }
}

private struct ConnectedAppsBudgetToggle: View {
    @Binding var isOn: Bool
    let enabled: Bool

    private var effectiveValue: Binding<Bool> {
        Binding(
            get: { enabled && isOn },
            set: { value in if enabled { isOn = value } }
        )
    }

    var body: some View {
        Toggle(isOn: effectiveValue) {
            Text(label)
                .lineLimit(1)
                .monospacedDigit()
        }
            .font(Typo.caption.weight(.medium))
            .foregroundStyle(labelColor)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .fixedSize()
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.5)
            .help(enabled
                ? (isOn
                    ? "Pause requests to the connected applications. The connections themselves stay."
                    : "Bring back context from the connected applications. Nothing was disconnected during the pause.")
                : "Connect an application first")
            .accessibilityLabel("Use work applications in prompts")
            .accessibilityValue(accessibilityValue)
    }

    private var label: String {
        guard enabled else { return "Applications unavailable" }
        return isOn ? "Apps on" : "Applications paused"
    }

    private var labelColor: Color {
        guard enabled else { return Theme.inkTertiary }
        return isOn ? Theme.amber : Theme.accentText
    }

    private var accessibilityValue: String {
        guard enabled else { return "Unavailable: no application is connected" }
        return (isOn ? "On" : "Off") + "; the connections stay"
    }
}

private struct AddAppsButton: View {
    @EnvironmentObject var state: AppState

    @ViewBuilder
    var body: some View {
        if #available(macOS 14.0, *) {
            ModernAddAppsButton()
        } else {
            Button {
                state.selectedSettingsTab = .connectedApps
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                AddAppsLabel()
            }
            .buttonStyle(.plain)
            .help("Open «Settings → Connected apps»")
        }
    }
}

@available(macOS 14.0, *)
private struct ModernAddAppsButton: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button {
            state.selectedSettingsTab = .connectedApps
            openSettings()
        } label: {
            AddAppsLabel()
        }
        .buttonStyle(.plain)
        .help("Open «Settings → Connected apps»")
    }
}

private struct AddAppsLabel: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
            Text("Add applications")
                .font(Typo.caption.weight(.medium))
        }
        .foregroundStyle(Theme.inkSecondary)
        .padding(.horizontal, Space.s)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
        .contentShape(Capsule())
        .fixedSize()
    }
}

enum CreditBadge: Equatable {
    case notApplicable
    case loading
    case remaining(Int)
    /// An anonymous device trial: credits in hand, and what signing up adds.
    ///
    /// The upsell belongs BESIDE the number, not instead of it. "Sign in for
    /// free credits" told a user who already had credits that they had none,
    /// and a bare count never mentions that these particular credits do not
    /// come back.
    case trial(remaining: Int, monthly: Int?)
    case stale
    /// No Cruxwing account session — there is no balance to show because there
    /// is no account to show one FOR.
    case signedOut
    case unavailable

    var isApplicable: Bool { self != .notApplicable }

    /// Whether the badge is reporting a problem the user can act on, rather
    /// than a balance. Both are "not a number", but only one is fixable by
    /// signing in, and conflating them points debugging at the wrong boundary.
    /// "12 credits · sign up for 15 a month".
    ///
    /// Names what the user HAS first, because they do have it — then what
    /// signing up adds. The monthly number is the honest pitch: a trial grant
    /// is one-off, so the difference is not three credits, it is three credits
    /// EVERY MONTH versus never again. When the catalogue has not loaded the
    /// number, the claim degrades to the shape that is still true rather than
    /// inventing one.
    static func trialText(_ remaining: Int, monthly: Int?, compact: Bool) -> String {
        if compact { return "\(remaining) cr · sign up" }
        let offer = monthly.map { "sign up — \($0) a month" } ?? "sign up — more every month"
        return "\(remaining) credits · \(offer)"
    }

    /// Both states name something the user can do about them.
    var isActionable: Bool {
        if case .trial = self { return true }
        return self == .signedOut
    }

    func label(compact: Bool) -> String {
        switch self {
        case .notApplicable: return ""
        case .loading: return compact ? "· cr…" : "· credits loading"
        case .remaining(let value): return compact ? "· \(value) cr" : "· \(value) credits left"
        case .trial(let value, let monthly):
            return "· " + Self.trialText(value, monthly: monthly, compact: compact)
        case .stale: return compact ? "· cr stale" : "· balance last checked"
        case .signedOut: return compact ? "· sign in" : "· sign in — credits are free"
        case .unavailable: return compact ? "· cr —" : "· credits unavailable"
        }
    }

    /// Same states without the "· " joiner — for when credits LEAD the rail
    /// (credit-first summary) instead of trailing the token estimate.
    func leadingLabel(compact: Bool) -> String {
        switch self {
        case .notApplicable: return ""
        case .loading: return compact ? "cr…" : "credits loading…"
        case .remaining(let value): return compact ? "\(value) cr" : "\(value) credits left"
        case .trial(let value, let monthly):
            return Self.trialText(value, monthly: monthly, compact: compact)
        case .stale: return compact ? "cr stale" : "credits: last checked"
        case .signedOut: return compact ? "sign in" : "sign in for free credits"
        case .unavailable: return compact ? "cr —" : "credits unavailable"
        }
    }

    /// Hover text. `unavailable` in particular used to be a dead end — it named
    /// a symptom and offered nothing to do about it.
    var help: String {
        switch self {
        case .notApplicable: return ""
        case .loading:       return "Checking the balance…"
        case .remaining:     return "The balance on the provider's account for the period."
        case .trial(_, let monthly):
            // Says the quiet part: these particular credits are one-off.
            let offer = monthly.map { "\($0) units every month" }
                ?? "a balance that refills every month"
            return "A starting balance, no account needed. It does not refill. "
                 + "Create an account in «Settings ▸ Account» and you get \(offer)."
        case .stale:         return "Showing the last known balance while it refreshes."
        case .signedOut:
            return "Connected applications sign in separately from your orakul account. "
                 + "Sign in under «Settings ▸ Account» to use models without your own keys."
        case .unavailable:
            return "Could not reach the billing service. That does not affect the balance itself."
        }
    }
}

/// Clickable preflight with a readable input breakdown. Managed mode uses its
/// tariff boundary; direct BYOK uses the selected model's context window.
/// The rail itself never animates while recording; only the explicit app switch
/// can change its composition, which keeps transcript scrolling stable.
struct PromptBudgetControl: View {
    let estimate: TokenEstimate
    let connectedAppsTokenPotential: Int
    @Binding var connectedAppsEnabled: Bool
    let connectedAppsAvailable: Bool
    let creditUsage: PaywallUsage?
    let creditUsagePhase: CreditUsagePhase
    /// What the free plan grants monthly, when the catalogue has answered.
    /// Passed in rather than read from the environment so the badge stays a
    /// pure function of its inputs, like everything else on this control.
    var freeTierMonthlyCredits: Int? = nil
    @State private var showDetails = false

    /// What the next prompt should cost, predicted with the same tariff the
    /// server charges (CreditCostEstimate mirrors functions/tariffs.js). nil
    /// when there is no credit meter at all — a direct-key build spends the
    /// operator's provider keys, not credits.
    private var predictedCredits: Int? {
        guard Config.llmViaBackend else { return nil }
        let selection = Config.selectedModelID
        // Auto picks its model per request, and the orchestration councils are
        // priced on a different scale entirely (5–38 credits, not the chat
        // tariff). Quoting the chat price for either would UNDER-report the
        // charge, which is worse than staying quiet — so no quote is shown and
        // the rail falls back to the plain rate label.
        guard selection != LLMCatalog.autoID,
              !selection.hasPrefix("auto:"),
              !selection.hasPrefix("council:"),
              !selection.hasPrefix("orchestrate:") else { return nil }
        return CreditCostEstimate.credits(
            model: Config.selectedModel.id,
            inputTokens: estimate.totalTokens,
            maxOutputTokens: OutputTokenBudget.explicitUserFacing)
    }

    private var costSeverity: CreditCostEstimate.Severity {
        CreditCostEstimate.severity(
            credits: predictedCredits ?? 0,
            remaining: creditUsage.map { max(0, $0.remaining.computeCredits) })
    }

    private var creditBadge: CreditBadge {
        guard Config.llmViaBackend else { return .notApplicable }
        switch creditUsagePhase {
        case .loading: return .loading
        case .fresh:
            guard let usage = creditUsage else { return .unavailable }
            // A trial account reports tier "free" with overridden allowances,
            // so the balance alone cannot tell the two apart — the session can.
            if Config.wheesprSession?.isDeviceTrial == true {
                return .trial(remaining: usage.remaining.computeCredits,
                              monthly: freeTierMonthlyCredits)
            }
            return .remaining(usage.remaining.computeCredits)
        case .stale: return .stale
        case .signedOut: return .signedOut
        case .unavailable: return .unavailable
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { showDetails.toggle() } label: {
                BudgetSummary(estimate: estimate, creditBadge: creditBadge,
                              predictedCredits: predictedCredits,
                              costSeverity: costSeverity)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .help("Show what the request is made of right now")
            .accessibilityLabel("Prompt budget")
            .accessibilityValue(accessibilityValue)
            .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                PromptBudgetDetails(
                    estimate: estimate,
                    connectedAppsTokenPotential: connectedAppsTokenPotential,
                    connectedAppsEnabled: connectedAppsEnabled,
                    creditUsage: creditUsage,
                    creditUsagePhase: creditUsagePhase,
                    predictedCredits: predictedCredits
                )
            }

            HStack {
                // Credits are NOT reported here any more. "272 of 100000
                // credits used" on an apps switch stated a ratio nobody could
                // act on, in the one place unrelated to it. The balance leads
                // the rail above, the price sits beside it, and the popover
                // holds the full breakdown.
                ConnectedAppsBudgetToggle(
                    isOn: $connectedAppsEnabled,
                    enabled: connectedAppsAvailable
                )
                Spacer(minLength: 0)
            }
        }
        .frame(height: 52)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        // Mirror the visual order: credits lead when they exist.
        switch creditBadge {
        case .notApplicable: break
        case .loading: parts.append("the credit balance is loading")
        case .remaining(let value): parts.append("\(value) compute credits left")
        case .trial(let value, let monthly):
            parts.append("\(value) free credits left, no account needed")
            parts.append(monthly.map { "sign up — \($0) every month" }
                         ?? "sign up for a monthly allowance")
        case .stale: parts.append("the credit balance has not been checked in a while; open the details for the previous value")
        case .signedOut: parts.append("you are not signed in; sign in — credits are free")
        case .unavailable: parts.append("the credit balance is unavailable")
        }
        if let predictedCredits {
            let qualifier: String
            switch costSeverity {
            case .routine: qualifier = ""
            case .notable: qualifier = ", a noticeable share of the balance"
            case .unaffordable: qualifier = ", more than the balance"
            }
            parts.append("this request is estimated at about \(predictedCredits) credits\(qualifier)")
        }
        parts.append("about \(TokenEstimate.label(estimate.totalTokens)) input tokens right now")
        parts.append("Click to expand")
        return parts.joined(separator: ", ")
    }
}

struct BudgetSummary: View {
    let estimate: TokenEstimate
    let creditBadge: CreditBadge
    /// Predicted cost of the next prompt and how it sits against the balance.
    /// nil in direct-key builds, where there are no credits to spend.
    var predictedCredits: Int? = nil
    var costSeverity: CreditCostEstimate.Severity = .routine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                summaryRow(total: .long, compactStatus: false, compactCredit: false)
                summaryRow(total: .short, compactStatus: true, compactCredit: true)
                summaryRow(total: .compact, compactStatus: true, compactCredit: true)
            }
            InputBudgetRail(estimate: estimate)
                .frame(height: 6)
        }
        .accessibilityHidden(true)
    }

    private enum TotalStyle { case long, short, compact }

    private func summaryRow(total: TotalStyle,
                            compactStatus: Bool,
                            compactCredit: Bool) -> some View {
        HStack(spacing: 5) {
            if creditBadge.isApplicable {
                // Credit-led (backend mode): the user buys credits, so the rail
                // speaks credits — balance first, then whether this prompt's
                // input pushes past the base rate. Token detail lives in the
                // popover as the explainer.
                creditLead(compact: compactCredit)
                creditSpendStatus(compact: compactStatus)
            } else {
                // Direct-key/dev mode has no credit meter — token estimate
                // remains the only honest number to show. Relate it to the
                // selected model's verified context window, never to the
                // inherited managed gateway's 6k credit-price boundary.
                totalLabel(total)
                directContextStatus(compact: compactStatus)
            }
            disclosureGlyph
        }
    }

    private func creditLead(compact: Bool) -> some View {
        Text(creditBadge.leadingLabel(compact: compact))
            .font(Typo.caption.weight(.semibold))
            .foregroundStyle(Theme.inkSecondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    /// The PRICE of the next prompt, not a threshold crossing.
    ///
    /// This replaced "large input — extra credits", which fired whenever the
    /// estimate passed 6k input tokens and said nothing about how much that
    /// actually cost. On a large balance it meant a few credits out of
    /// thousands and cried wolf every time; the number lets the user judge, and
    /// the styling only escalates when the charge is big RELATIVE to what is
    /// left.
    private func creditSpendStatus(compact: Bool) -> some View {
        Group {
            if let predictedCredits {
                Text(compact ? "· ~\(predictedCredits) cr" : "· ~\(predictedCredits) credits for this request")
                    .foregroundStyle(severityColor)
            } else {
                Text(compact ? "· base" : "· base input rate")
                    .foregroundStyle(Theme.accentText)
            }
        }
        .font(Typo.caption)
        .monospacedDigit()
        .lineLimit(1)
    }

    private var severityColor: Color {
        switch costSeverity {
        case .routine: return Theme.inkTertiary
        case .notable: return Theme.amber
        case .unaffordable: return Theme.danger
        }
    }

    private func totalLabel(_ style: TotalStyle) -> some View {
        let value: String
        switch style {
        case .long: value = "~\(TokenEstimate.label(estimate.totalTokens)) on the input now"
        case .short: value = "~\(TokenEstimate.label(estimate.totalTokens)) on the input"
        case .compact: value = "~\(TokenEstimate.label(estimate.totalTokens))"
        }
        return Text(value)
            .font(Typo.caption.weight(.semibold))
            .foregroundStyle(Theme.inkSecondary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private func directContextStatus(compact: Bool) -> some View {
        let contextWindow = Config.selectedRequestModel.contextTokens
        let overflow = max(0, estimate.totalTokens - (contextWindow ?? estimate.totalTokens))
        let fraction = contextWindow.map {
            min(1, Double(estimate.totalTokens) / Double(max($0, 1)))
        }
        let percentage = fraction.map { Int(($0 * 100).rounded()) }

        return Group {
            if overflow > 0 {
                Text(compact
                     ? "· +~\(TokenEstimate.label(overflow)) over the window"
                     : "· +~\(TokenEstimate.label(overflow)) over the model's window")
                    .foregroundStyle(Theme.danger)
            } else if let percentage {
                Text(compact ? "· ~\(percentage)% of the window" : "· ~\(percentage)% of the model's window")
                    .foregroundStyle(percentage >= 80 ? Theme.amber : Theme.inkTertiary)
            } else {
                Text(compact ? "· size" : "· approximate context size")
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .font(Typo.caption)
        .monospacedDigit()
        .lineLimit(1)
    }

    private func creditLabel(compact: Bool) -> some View {
        Text(creditBadge.label(compact: compact))
            .font(Typo.caption)
            .foregroundStyle(Theme.inkTertiary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var disclosureGlyph: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Theme.inkTertiary)
    }
}

private struct InputBudgetRail: View {
    let estimate: TokenEstimate

    /// The inherited gateway prices input around a fixed 6k boundary. Direct
    /// providers do not: their meaningful boundary is the selected model's
    /// verified context window.
    private var referenceTokens: Int? {
        if Config.llmViaBackend { return TokenEstimate.baseCreditInputTokens }
        return Config.selectedRequestModel.contextTokens
    }

    private var segments: [(tokens: Int, color: Color)] {
        [(estimate.transcriptTokens, Theme.accent),
         (estimate.contextTokens, Theme.amber),
         (estimate.sourcesTokens, Theme.speakerYou),
         (estimate.instructionsTokens, Theme.inkTertiary)]
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = max(max(estimate.totalTokens, referenceTokens ?? 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceSunken)

                ForEach(Array(segments.indices), id: \.self) { index in
                    let segment = segments[index]
                    if segment.tokens > 0 {
                        let preceding = segments.prefix(index).reduce(0) { $0 + $1.tokens }
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: proxy.size.width * CGFloat(segment.tokens) / CGFloat(scale))
                            .offset(x: proxy.size.width * CGFloat(preceding) / CGFloat(scale))
                    }
                }

                if let referenceTokens {
                    Rectangle()
                        .fill(estimate.totalTokens > referenceTokens
                              ? Theme.danger : Theme.hairlineStrong)
                        .frame(width: 1, height: proxy.size.height)
                        .offset(x: min(proxy.size.width - 1,
                                       proxy.size.width
                                       * CGFloat(referenceTokens)
                                       / CGFloat(scale)))
                }
            }
            .clipShape(Capsule())
        }
        .accessibilityHidden(true)
    }
}

struct PromptBudgetDetails: View {
    let estimate: TokenEstimate
    let connectedAppsTokenPotential: Int
    let connectedAppsEnabled: Bool
    let creditUsage: PaywallUsage?
    let creditUsagePhase: CreditUsagePhase
    /// What the free plan grants monthly, when the catalogue has answered.
    /// Passed in rather than read from the environment so the badge stays a
    /// pure function of its inputs, like everything else on this control.
    var freeTierMonthlyCredits: Int? = nil
    var predictedCredits: Int? = nil

    private var includedConnectedTokens: Int {
        connectedAppsEnabled ? min(connectedAppsTokenPotential, estimate.sourcesTokens) : 0
    }

    private var otherSourceTokens: Int {
        max(0, estimate.sourcesTokens - includedConnectedTokens)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if Config.llmViaBackend {
                // Balance, then when it refills, then what it buys. This block
                // belongs only to the inherited managed gateway; direct BYOK
                // has no Orakul balance or plan.
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Credits")
                            .font(Typo.headline)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: Space.s)
                        if let tier = creditUsage?.tier, !tier.isEmpty {
                            Text(tier.capitalized)
                                .font(Typo.caption.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary)
                                .padding(.horizontal, Space.s)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.surfaceSunken))
                        }
                    }
                    if let headline = balanceHeadline {
                        Text(headline)
                            .font(Typo.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .monospacedDigit()
                    }
                }
                managedCreditSection
            } else {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Request context")
                        .font(Typo.headline)
                        .foregroundStyle(Theme.ink)
                    Text("Orakul does not sell credits and does not limit requests. You control the key and the billing of the AI provider you chose.")
                        .font(Typo.caption)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Hairline()

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Config.llmViaBackend
                     ? "What the prompt's price is made of"
                     : "What is taking up the request context")
                    .font(Typo.bodyStrong)
                    .foregroundStyle(Theme.inkSecondary)
                Text("About \(TokenEstimate.label(estimate.totalTokens)) input tokens so far")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .monospacedDigit()
            }

            InputBudgetRail(estimate: estimate)
                .frame(height: 8)

            VStack(spacing: Space.s) {
                BreakdownRow(label: "Transcript", tokens: estimate.transcriptTokens,
                             detail: nil, color: Theme.accent)
                BreakdownRow(label: "Attached context", tokens: estimate.contextTokens,
                             detail: nil, color: Theme.amber)
                BreakdownRow(
                    label: "Connected applications",
                    tokens: connectedAppsTokenPotential,
                    detail: connectedAppsEnabled ? "upper bound" : "paused",
                    color: Theme.speakerYou,
                    excluded: !connectedAppsEnabled
                )
                if otherSourceTokens > 0 {
                    BreakdownRow(label: "Other sources", tokens: otherSourceTokens,
                                 detail: nil, color: Theme.speakerYou)
                }
                BreakdownRow(label: "Shared instructions", tokens: estimate.instructionsTokens,
                             detail: "the button adds more", color: Theme.inkTertiary)
            }

            Text("The estimate is incomplete: it leaves out the request itself and the instructions the pressed button adds. The real token count also depends on the language and the chosen model, and the context pulled from applications may turn out smaller.")
                .font(Typo.caption)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
        .frame(width: 340)
    }

    /// "resets in 12 days · about 48 more prompts this size" — the two facts
    /// that turn a balance into something you can plan around.
    private var balanceHeadline: String? {
        guard let usage = creditUsage else { return nil }
        var parts: [String] = []
        if let start = CreditPeriod.parse(periodStart: usage.periodStart),
           let reset = CreditPeriod.resetDescription(periodStart: start) {
            parts.append(reset.prefix(1).uppercased() + reset.dropFirst())
        }
        if let prompts = CreditPeriod.remainingPrompts(
            remainingCredits: max(0, usage.remaining.computeCredits),
            perPrompt: predictedCredits) {
            parts.append(prompts == 1
                ? "about one more request of this size"
                : "about \(prompts) more requests of this size")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var managedCreditSection: some View {
        switch creditUsagePhase {
        case .loading:
            HStack(spacing: Space.s) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading the credit balance…")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Loading the credit balance")
        case .fresh, .stale:
            if let usage = creditUsage {
                let allowance = max(usage.allowances.computeCredits, 1)
                let remaining = max(0, usage.remaining.computeCredits)
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack {
                        Text("Credits")
                            .font(Typo.caption.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer()
                        Text("осталось \(remaining) из \(allowance)\(creditUsagePhase == .stale ? " · по последней проверке" : "")")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.inkSecondary)
                            .monospacedDigit()
                    }
                    ProgressView(value: Double(min(remaining, allowance)), total: Double(allowance))
                        .tint(remaining * 5 < allowance ? Theme.danger : Theme.accent)
                        .controlSize(.small)
                }
            } else {
                unavailableCreditRow
            }
        case .signedOut:
            signedOutCreditRow
        case .unavailable:
            unavailableCreditRow
        }

        Text("A request's cost at the provider is the model's base rate plus surcharges for a long input and a long answer. The provider computes the exact amount itself.")
            .font(Typo.caption)
            .foregroundStyle(Theme.inkTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// No account session. Names the cause and the fix, and says plainly that
    /// connected apps are a separate sign-in — a workspace with Google, Notion
    /// and Asana attached looks signed in, which is why an empty balance read
    /// as a billing bug rather than a missing account.
    private var signedOutCreditRow: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .foregroundStyle(Theme.accent)
            Text("Sign in to orakul to use models without your own keys. Connected applications sign in separately and stay connected either way.")
                .font(Typo.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You are not signed in. Sign in to orakul to see credits.")
    }

    private var unavailableCreditRow: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "creditcard")
                .foregroundStyle(Theme.inkTertiary)
            Text("Could not reach the billing service, so no balance is shown. That does not affect the balance itself.")
                .font(Typo.caption)
                .foregroundStyle(Theme.inkSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Credit balance unavailable")
    }
}

private struct BreakdownRow: View {
    let label: String
    let tokens: Int
    let detail: String?
    let color: Color
    var excluded = false

    var body: some View {
        HStack(spacing: Space.s) {
            Circle()
                .fill(excluded ? Theme.hairlineStrong : color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(label)
                .font(Typo.caption.weight(.medium))
                .foregroundStyle(excluded ? Theme.inkTertiary : Theme.inkSecondary)
            if let detail {
                Text("· \(detail)")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.inkTertiary)
            }
            Spacer()
            Text(excluded
                 ? "+~\(TokenEstimate.label(tokens)) if used"
                 : "~\(TokenEstimate.label(tokens))")
                .font(Typo.mono)
                .foregroundStyle(excluded ? Theme.inkTertiary : Theme.inkSecondary)
                .monospacedDigit()
        }
    }
}
