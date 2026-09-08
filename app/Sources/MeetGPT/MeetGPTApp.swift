import AppKit
import SwiftUI

/// Dock behavior SwiftUI doesn't provide on its own: clicking the Dock icon
/// re-shows the main window when every window was closed.
final class DockActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        // Only act when NO window is visible (the "reopen from fully closed"
        // case). When a window is already up — the Settings/connectors window,
        // a sheet mid-OAuth, whatever — do nothing but let AppKit bring the
        // user's OWN front window back. The earlier version force-fronted the
        // MAIN window unconditionally, which shoved the Settings window behind
        // it after an app connect (read as the connectors window "closing").
        guard !flag else { return true }
        sender.activate(ignoringOtherApps: true)
        if let window = sender.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        // true = let AppKit ALSO recreate the WindowGroup window if needed.
        return true
    }
}

@main
struct MeetGPTApp: App {
    @NSApplicationDelegateAdaptor(DockActivationDelegate.self) private var dockDelegate
    @StateObject private var state = AppState()
    /// Work-app connections over MCP (Notion, Fireflies, Linear, …).
    @StateObject private var mcp = MCPConnectionManager()
    /// Floating co-pilot card (always-on-top, toggled from the menu bar).
    @StateObject private var overlay = OverlayController()

    init() {
        // Apply the saved light/dark theme before any window appears.
        NSApplication.shared.appearance = Config.appAppearance.nsAppearance
        // Channel watcher (Team sources) — default-off, and runs only after the
        // user has explicitly enabled it and configured keywords.
        Task { @MainActor in TeamWatcher.shared.apply() }
        // Load the vendored Agent Skills from the bundle (observable in Console).
        let reviewed = BundledSkillLibrary.rankable
        Log.general.info("Loaded \(reviewed.count, privacy: .public) runtime-reviewed bundled skill(s)")
        // Warm on-device sentence embeddings for relevance ranking (utility QoS).
        Task.detached(priority: .utility) {
            BundledSkillEmbeddingIndex.ensureBuilt(library: reviewed)
            let n = BundledSkillEmbeddingIndex.cachedCount
            if n > 0 {
                Log.general.info("Skill embedding index ready (\(n, privacy: .public) vectors)")
            } else {
                Log.general.info("Skill embedding index unavailable — using token relevance fallback")
            }
        }
    }

    var body: some Scene {
        WindowGroup("orakul", id: "main") {
            ContentView()
                .environmentObject(state)
                .environment(\.readingTextScale, state.readingTextScale)
                .environmentObject(mcp)
                .frame(minWidth: 1000, minHeight: 600)
                // Let prompt-button workflows ground from connected work-apps.
                .onAppear {
                    state.mcp = mcp
                    // Item 10's remaining wire: give the agentic-read loop a live
                    // executor built from the connected servers, so a blind spot
                    // or a prompt can actually resolve a read tool. The Caller is
                    // async, so it hops to the @MainActor manager cleanly; the
                    // executor is rebuilt per request off the current connections.
                    AgenticReadContext.shared.configure(
                        executor: {
                            // Built on the MainActor because the manager is
                            // MainActor-isolated; the async provider makes that
                            // hop explicit and race-free, and the snapshot is
                            // taken per request so a mid-session connect is seen.
                            await MainActor.run { () -> AgenticReadExecutor? in
                                // The global pause is a consent boundary, not a
                                // hint for only the preloaded grounding path.
                                // Agentic mid-answer reads must obey it too.
                                guard state.useConnectedAppsInPrompts else { return nil }
                                let servers = mcp.researchableServers
                                guard !servers.isEmpty else { return nil }
                                // Snapshot the tool lists here, on the actor —
                                // [Tool] is a value type, so the executor can
                                // read it from any thread. Reading mcp.tools(for:)
                                // lazily inside the executor would cross back off
                                // the MainActor on every resolve.
                                let toolsByServer = Dictionary(
                                    uniqueKeysWithValues: servers.map { ($0.id, mcp.tools(for: $0.id)) })
                                return AgenticReadExecutor(
                                    servers: servers,
                                    toolsForServer: { toolsByServer[$0] ?? [] },
                                    call: { server, tool, arguments in
                                        try await mcp.callToolText(
                                            server: server, tool: tool, arguments: arguments)
                                    })
                            }
                        },
                        isRecording: { await MainActor.run { state.isRecording } },
                        onTurnComplete: { _ in })
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // Pane visibility (backlog item 3). In the menu bar deliberately:
            // the acceptance rule is that no state may hide the toggle itself.
            PaneCommands(store: PaneLayoutStore.shared)
            // The break-out from Socratic mode. A real menu command rather than
            // a key handler buried in the composer: the acceptance criterion is
            // ONE keystroke to get the answer plainly, and a shortcut nobody can
            // find in a menu is not discoverable enough to count.
            CommandGroup(after: .textEditing) {
                Button("Дальше ответить прямо") { state.answerPlainlyNext() }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                    .disabled(!state.socraticModeEnabled || state.socraticBrokenOut)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .environment(\.readingTextScale, state.readingTextScale)
                .environmentObject(mcp)
                .environmentObject(overlay)
        } label: {
            Image(systemName: state.isRecording ? "record.circle" : "brain.head.profile")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(state)
                .environment(\.readingTextScale, state.readingTextScale)
                .environmentObject(mcp)
        }
    }
}
