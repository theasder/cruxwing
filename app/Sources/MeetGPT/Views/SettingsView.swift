import SwiftUI
import CruxwingCore

enum SettingsTab: String, Hashable, CaseIterable {
    case general
    case transcription
    case ai
    case connectedApps
    case accountPrivacy
}

/// Settings, restructured from a single 820pt scroll into macOS-idiomatic tabs
/// (see docs/ui-audit IA): General (app behavior) · Transcription · AI (models
/// + co-pilot) · Connected Apps (Google, MCP, team sources) · Account &
/// Privacy (sign-in, deletion, consent, data routing). Each tab sizes itself;
/// the window adapts per tab as macOS users expect.
struct SettingsView: View {

    /// Строка, которую человек копирует в сообщение об ошибке.
    ///
    /// Имя, версия и хеш исходников: по первым двум понятно, что человек
    /// запускал, по третьему — из какого кода это собрано. Хеш ставит сборка
    /// (`CruxwingSourceHash`), и он отличает две сборки одного коммита, чего
    /// номер коммита не умеет.
    static var buildSignature: String { buildSignature(from: Bundle.main.infoDictionary ?? [:]) }

    /// Отдельно от `Bundle.main`, чтобы это можно было проверить набором: под
    /// тестами `Bundle.main` — это раннер, а не приложение, и штампа там нет.
    static func buildSignature(from info: [String: Any]) -> String {
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String) ?? "cruxwing"
        let version = (info["CFBundleShortVersionString"] as? String) ?? ""
        let source = (info["CruxwingSourceHash"] as? String) ?? ""
        // Имя и версия — через пробел, штамп исходников — за точкой: она
        // отделяет то, что человек и так знает, от того, что нужно нам.
        let head = [name, version].filter { !$0.isEmpty }.joined(separator: " ")
        return source.isEmpty ? head : "\(head) · \(source)"
    }
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
        TabView(selection: $state.selectedSettingsTab) {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)
            TranscriptionSettingsTab()
                .tabItem { Label("Transcription", systemImage: "waveform") }
                .tag(SettingsTab.transcription)
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
                .tag(SettingsTab.ai)
            ConnectedAppsTab()
                .tabItem { Label("Work applications", systemImage: "app.connected.to.app.below.fill") }
                .tag(SettingsTab.connectedApps)
            AccountPrivacyTab()
                .tabItem { Label("Account and privacy", systemImage: "person.badge.key") }
                .tag(SettingsTab.accountPrivacy)
        }
        // Версия — под вкладками, чтобы её было видно с любой из них.
        // Раньше её не было нигде: сборка штампует `CruxwingSourceHash` в
        // Info.plist, но человек туда не заглянет, и сообщение «не работает»
        // приходило без ответа на первый же вопрос — какую сборку он проверял.
        // `ДЛЯ-ТЕСТИРОВЩИКА.md` пункт 4 просит прислать эту строку, поэтому
        // она выделяется мышью.
        //
        // Показывается то, что есть: у сборки разработчика штампа нет, и
        // выдумывать его нельзя — тестировщик перепишет выдумку как факт.
        Text(SettingsView.buildSignature)
            .font(Typo.caption)
            .foregroundStyle(Theme.inkTertiary)
            .textSelection(.enabled)
            .accessibilityIdentifier("settings.build-signature")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xl)
            .padding(.bottom, Space.m)
        }
        .background(Theme.canvas)
    }
}

// MARK: - Tab 1 · General (set-once app behavior)

private struct GeneralSettingsTab: View {
    @EnvironmentObject var state: AppState
    @State private var appearance: AppAppearance = Config.appAppearance
    @State private var readingScale: Double = Config.readingTextScale
    @State private var callDetection: Bool = Config.callDetectionEnabled
    @State private var ignoreMedia: Bool = Config.ignoreMediaApps
    @State private var reminders: Bool = Config.meetingRemindersEnabled
    @State private var blindSpotBanners: Bool = Config.blindSpotTextNotificationsEnabled
    @State private var reminderMinutes: Int = Config.meetingReminderMinutes
    @State private var customRole: String = Config.userCustomRole

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsSection(title: "Appearance",
                            caption: "«Auto» follows the system; «Light» and «Dark» override it.") {
                SettingsRow {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Picker("", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { mode in Text(mode.label).tag(mode) }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                    .onChange(of: appearance) { state.setAppearance($1) }
                    .accessibilityLabel("Appearance")
                    .accessibilityIdentifier("settings.general.theme")
                }
                SettingsRow {
                    Label("Text size", systemImage: "textformat.size")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    // Applies to the transcript and the assistant answer only.
                    // Scaling the chrome as well would collide the controls at
                    // the smallest supported window, and prose is what people
                    // mean by "bigger text".
                    Picker("", selection: $readingScale) {
                        ForEach(ReadingTextScale.steps, id: \.self) { step in
                            Text(ReadingTextScale.label(for: step)).tag(step)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                    .onChange(of: readingScale) { state.readingTextScale = $1 }
                    .accessibilityLabel("Text size")
                    .accessibilityIdentifier("settings.general.readingTextSize")
                }
            }

            // The setup guide runs once and never returns, because the gate
            // records the last step FINISHED. Someone who clicked past the
            // capture check had no way back to it — and no way to re-run the
            // six-second test that proves both audio sources are audible, which
            // is the check that answers "why is the other side silent?" before a
            // real call does.
            SettingsSection(title: "First-run setup",
                            caption: "Runs the permission check, the audio-capture check and the worked example again. Nothing but the setup itself is reset.") {
                SettingsRow {
                    Label("Show the setup again", systemImage: "arrow.counterclockwise")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Button("Show") { state.replayOnboarding() }
                        .accessibilityIdentifier("settings.general.replayOnboarding")
                }
            }

            SettingsSection(title: "Profile",
                            caption: "Your role changes how the AI reads a call: a product manager and a founder end up with different results. Choose one from the list or write your own. The role can also be switched in the sidebar.") {
                SettingsRow {
                    Label("Your role", systemImage: "person.text.rectangle")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Picker("", selection: $state.userRoleID) {
                        Text("Not set").tag(String?.none)
                        Divider()
                        ForEach(RoleSkillMatrix.positions) { position in
                            Text(position.label).tag(String?.some(position.id))
                        }
                        Divider()
                        Text("Write your own…").tag(String?.some(RoleSkillMatrix.customRoleID))
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .frame(maxWidth: 240)
                    .accessibilityLabel("Your role")
                    .accessibilityIdentifier("settings.general.role")
                }
                if state.userRoleID == RoleSkillMatrix.customRoleID {
                    SettingsRow {
                        TextField("for example, head of growth at a fintech startup",
                                  text: $customRole)
                            .textFieldStyle(.plain)
                            .font(Typo.callout)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, Space.m)
                            .frame(height: 30)
                            .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1))
                            .onChange(of: customRole) { Config.userCustomRole = $1 }
                            .accessibilityLabel("Your own role")
                            .accessibilityIdentifier("settings.general.custom-role")
                    }
                }
            }

            SettingsSection(title: "During a call",
                            caption: "cruxwing notices a call application opening and offers to start recording.") {
                SettingsRow {
                    Label("Tell me about calls", systemImage: "bell.badge")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: $callDetection)
                        .labelsHidden().toggleStyle(.switch)
                        .onChange(of: callDetection) { Config.callDetectionEnabled = $1; state.applyCallDetectionSettings() }
                        .accessibilityLabel("Tell me about calls")
                        .accessibilityIdentifier("settings.general.call-detection")
                }
                SettingsRow {
                    Label("Ignore music and video", systemImage: "music.note.tv")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: $ignoreMedia)
                        .labelsHidden().toggleStyle(.switch)
                        .disabled(!callDetection)
                        .onChange(of: ignoreMedia) { Config.ignoreMediaApps = $1 }
                        .accessibilityLabel("Ignore music and video")
                        .accessibilityIdentifier("settings.general.ignore-media")
                }
            }

            SettingsSection(title: "During a call",
                            caption: "A quiet banner when a new blind spot is found and cruxwing is minimised — text only, no sound.") {
                SettingsRow {
                    Label("Blind-spot banners", systemImage: "bell.badge")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: $blindSpotBanners)
                        .labelsHidden().toggleStyle(.switch)
                        .onChange(of: blindSpotBanners) { Config.blindSpotTextNotificationsEnabled = $1 }
                        .accessibilityLabel("Blind-spot banners")
                        .accessibilityIdentifier("settings.general.blindSpotBanners")
                }
            }

            SettingsSection(title: "Before the meeting",
                            caption: state.googleConnected
                                ? "Reminders arrive ahead of time, before a meeting in the calendar."
                                : "Reminders need Google Calendar — connect it on the «Connected apps» tab.") {
                SettingsRow {
                    Label("Remind me before meetings", systemImage: "bell.and.waves.left.and.right")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: $reminders)
                        .labelsHidden().toggleStyle(.switch)
                        .onChange(of: reminders) { Config.meetingRemindersEnabled = $1; state.applyReminderSettings() }
                        .accessibilityLabel("Remind me before meetings")
                        .accessibilityIdentifier("settings.general.reminders")
                }
                SettingsRow {
                    Label("Time before the meeting", systemImage: "clock")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Picker("", selection: $reminderMinutes) {
                        Text("1 minute before").tag(1)
                        Text("5 minutes before").tag(5)
                        Text("10 minutes before").tag(10)
                        Text("15 minutes before").tag(15)
                        Text("30 minutes before").tag(30)
                    }
                    .labelsHidden().pickerStyle(.menu).fixedSize()
                    .disabled(!reminders)
                    .onChange(of: reminderMinutes) { Config.meetingReminderMinutes = $1; state.applyReminderSettings() }
                    .accessibilityLabel("How far ahead to remind")
                    .accessibilityIdentifier("settings.general.reminder-lead-time")
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 520)
        .onAppear {
            appearance = Config.appAppearance
            callDetection = Config.callDetectionEnabled
            ignoreMedia = Config.ignoreMediaApps
            reminders = Config.meetingRemindersEnabled
            blindSpotBanners = Config.blindSpotTextNotificationsEnabled
            reminderMinutes = Config.meetingReminderMinutes
            customRole = Config.userCustomRole
        }
    }
}

// MARK: - Tab 2 · Transcription

private struct TranscriptionSettingsTab: View {
    @EnvironmentObject var state: AppState
    @State private var transcriptionLanguage: String = Config.transcriptionLanguage
    @State private var glossary: String = Config.transcriptionGlossary
    @State private var localModel: String = Config.localWhisperModel
    @State private var micNoiseSuppression: Bool = Config.micNoiseSuppressionEnabled
    @State private var adaptiveLocal: Bool = Config.adaptiveLocalWhisperEnabled
    @State private var postStopFinalPass: Bool = Config.transcriptionPostStopFinalPassEnabled
    @State private var localSpeakerLabels: Bool = Config.localDiarizationEnabled
    @State private var remoteSpeakerCount: Int = Config.localDiarizationRemoteSpeakerCount
    @State private var assemblyDiarization: Bool = Config.assemblyAIDiarizationEnabled
    @State private var firefliesEnhance: Bool = Config.firefliesTranscriptEnhanceEnabled
    @State private var credentialRevision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                SettingsSection(
                    title: "Cloud transcription keys",
                    caption: "Optional. You add and delete the key yourself; it is kept in the Keychain and used for a direct request to the chosen service. The build carries no cruxwing keys and no server-side substitution."
                ) {
                    TranscriptionProviderKeysSection(
                        store: state.transcriptionProviderKeys,
                        onRemove: { state.removeTranscriptionKey(for: $0) }
                    ) { provider, isConfigured in
                        credentialRevision &+= 1
                        if provider == .assemblyAI, !isConfigured {
                            assemblyDiarization = false
                            Config.assemblyAIDiarizationEnabled = false
                        }
                    }
                }

                SettingsSection(title: "Engine",
                                caption: "«Local» keeps the call audio on this computer. Deepgram or Whisper means the audio goes to that cloud provider. Changing the engine mid-call takes effect immediately.") {
                    ForEach(TranscriptionEngine.selectableCases) { option in
                        EngineChoiceRow(engine: option,
                                        selected: state.selectedTranscriptionEngine == option,
                                        available: option == .deepgram
                                            ? state.hasDeepgram
                                            : Config.engineAvailable(option)) {
                            // AppState owns the selected row because a WebSocket
                            // handoff can still fail asynchronously after this
                            // closure returns and must visibly roll back.
                            state.selectTranscriptionEngine(option)
                        }
                    }
                }

                SettingsSection(title: "Language",
                                caption: "«Auto» overrides the language as the conversation goes. If the whole call is in Russian, choose Russian: on short, noisy fragments «Auto» gets it wrong. «Auto» is for conversations that really do use two languages. Takes effect from the next recording.") {
                    SettingsRow {
                        Label("Language", systemImage: "globe")
                            .labelStyle(SettingLabelStyle())
                        Spacer()
                        Picker("", selection: $transcriptionLanguage) {
                            ForEach(Config.transcriptionLanguageOptions, id: \.code) { option in
                                Text(option.label).tag(option.code)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu)
                        .frame(maxWidth: 220)
                        .onChange(of: transcriptionLanguage) { Config.transcriptionLanguage = $1 }
                        .accessibilityLabel("Transcription language")
                        .accessibilityIdentifier("settings.transcription.language")
                    }
                }

                SettingsSection(title: "Microphone",
                                caption: "This optional Apple processing removes echo and background noise, but while recording it can dampen the sound from your speakers. Leave it off to keep the volume steady; with headphones there is no such cost. Takes effect from the next recording.") {
                    SettingsRow {
                        Label("Apple noise suppression", systemImage: "waveform.badge.mic")
                            .labelStyle(SettingLabelStyle())
                        Spacer()
                        Toggle("", isOn: $micNoiseSuppression)
                            .labelsHidden().toggleStyle(.switch)
                            .onChange(of: micNoiseSuppression) { Config.micNoiseSuppressionEnabled = $1 }
                            .accessibilityLabel("Apple noise suppression")
                            .accessibilityIdentifier("settings.transcription.aec")
                    }
                }

                SettingsSection(title: "Enrich from Fireflies",
                                caption: "Off by default, and it works only together with the shared automatic-requests switch on the «AI» tab. After a call, cruxwing reconciles the Fireflies transcript with the local one through your chosen AI provider; that sends it the text and creates spend under your contract. Names and terms may be refined against the connected applications you allowed.") {
                    SettingsRow {
                        Label("Enrich the transcript from Fireflies", systemImage: "flame")
                            .labelStyle(SettingLabelStyle())
                        Spacer()
                        Toggle("", isOn: $firefliesEnhance)
                            .labelsHidden().toggleStyle(.switch)
                            .onChange(of: firefliesEnhance) { Config.firefliesTranscriptEnhanceEnabled = $1 }
                            .accessibilityLabel("Enrich the transcript from Fireflies")
                            .accessibilityIdentifier("settings.transcription.fireflies-enhance")
                    }
                }

                if state.selectedTranscriptionEngine == .local {
                    SettingsSection(title: "On-device model",
                                    caption: "A larger model is usually more accurate, but downloads longer and runs heavier. The change takes effect from the next recording.") {
                    Picker("", selection: $localModel) {
                        ForEach(LocalWhisperModel.options) { option in
                            Text("\(option.title) — \(option.id)").tag(option.id)
                        }
                    }
                    .labelsHidden().pickerStyle(.radioGroup)
                    .onChange(of: localModel) {
                        // An explicit pick is never rewritten by the default
                        // correction that downgrades over-provisioned machines.
                        Config.localModelChosenByUser = true
                        Config.localWhisperModel = $1
                    }
                    .accessibilityLabel("On-device recognition model")
                    .accessibilityIdentifier("settings.transcription.local-model")
                    if let picked = LocalWhisperModel.options.first(where: { $0.id == localModel }) {
                        Text(picked.caption)
                            .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    SettingsRow {
                        Label("Tuning for this machine", systemImage: "speedometer")
                            .labelStyle(SettingLabelStyle())
                        Spacer()
                        Toggle("", isOn: $adaptiveLocal)
                            .labelsHidden().toggleStyle(.switch)
                            .onChange(of: adaptiveLocal) { Config.adaptiveLocalWhisperEnabled = $1 }
                            .accessibilityLabel("Recognition tuning")
                            .accessibilityIdentifier("settings.transcription.adaptive")
                    }
                    Text("If transcription keeps falling behind, cruxwing picks a lighter model for the next recording. At Base it will suggest Deepgram, but it never goes to the cloud on its own.")
                        .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    SettingsSection(
                        title: "Post-call refinement",
                        caption: "Off by default. Turned on, cruxwing re-reads the saved audio on this Mac after you stop. The live transcript is kept if the new result is incomplete or lost content.") {
                        SettingsRow {
                            Label("Refine after stopping", systemImage: "waveform.badge.checkmark")
                                .labelStyle(SettingLabelStyle())
                            Spacer()
                            Toggle("", isOn: $postStopFinalPass)
                                .labelsHidden().toggleStyle(.switch)
                                .onChange(of: postStopFinalPass) {
                                    Config.transcriptionPostStopFinalPassEnabled = $1
                                }
                                .accessibilityLabel("Refine the local transcript after stopping")
                                .accessibilityIdentifier("settings.transcription.post-stop-final-pass")
                        }
                    }

                    SettingsSection(
                        title: "Private speaker labels · Beta",
                        caption: "Turn this on before the next local recording: cruxwing keeps the other party's track in memory. After stopping, choose 1–4 voices and run identification; the number can be changed and re-run on the same call. There is no automatic count — when measured, it overstated the number of voices. The first run downloads about 34 MB of models. Audio and embeddings stay on this Mac, and no voiceprints are stored. Labels are saved only in this call's local history on this Mac. For calls longer than an hour, only the fully saved part is labelled. Beta — check the labels before sending them anywhere."
                    ) {
                        SettingsRow {
                            Label("Identify speakers on this Mac", systemImage: "person.2.wave.2")
                                .labelStyle(SettingLabelStyle())
                            Spacer()
                            Toggle("", isOn: $localSpeakerLabels)
                                .labelsHidden().toggleStyle(.switch)
                                .onChange(of: localSpeakerLabels) {
                                    Config.localDiarizationEnabled = $1
                                }
                                .accessibilityLabel("Identify speakers on this Mac")
                                .accessibilityIdentifier(
                                    "settings.transcription.local-diarization")
                        }
                        SettingsRow {
                            Label("Other voices", systemImage: "person.3")
                                .labelStyle(SettingLabelStyle())
                            Spacer()
                            Picker("", selection: $remoteSpeakerCount) {
                                ForEach(LocalDiarization.remoteSpeakerCountRange, id: \.self) {
                                    Text("\($0)").tag($0)
                                }
                            }
                            .labelsHidden().pickerStyle(.menu)
                            .frame(maxWidth: 90)
                            .disabled(!localSpeakerLabels)
                            .onChange(of: remoteSpeakerCount) {
                                Config.localDiarizationRemoteSpeakerCount = $1
                            }
                            .accessibilityLabel("Number of other voices")
                            .accessibilityIdentifier(
                                "settings.transcription.local-diarization-speakers")
                        }
                    }
                }

                if state.hasAssemblyAI {
                    SettingsSection(title: "Who spoke — after the call",
                                    caption: "Optional processing through AssemblyAI. Takes effect from the next recording: cruxwing keeps the other party's track and uploads it only after you press «Identify speakers» — never on its own during a call.") {
                        SettingsRow {
                            Label("Allow cloud speaker identification", systemImage: "person.2.wave.2")
                                .labelStyle(SettingLabelStyle())
                            Spacer()
                            Toggle("", isOn: $assemblyDiarization)
                                .labelsHidden().toggleStyle(.switch)
                                .onChange(of: assemblyDiarization) { Config.assemblyAIDiarizationEnabled = $1 }
                                .accessibilityLabel("Allow cloud speaker identification")
                                .accessibilityIdentifier("settings.transcription.assembly-diarization")
                        }
                    }
                }

                SettingsSection(title: "Your own glossary",
                                caption: "Product names, abbreviations, personal names — one per line or separated by commas. It tells any engine the correct spelling. Terms from connected applications are shown for review first; accepted ones take effect from the next recording, even if you accepted them mid-call.") {
                    TextEditor(text: $glossary)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .scrollContentBackground(.hidden)
                        .padding(Space.s)
                        .frame(height: 96)
                        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1))
                        .overlay(alignment: .topLeading) {
                            if glossary.isEmpty {
                                Text("cruxwing, RICE, ARR, Kubernetes…")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(Theme.inkTertiary)
                                    .padding(.horizontal, Space.s + 4).padding(.vertical, Space.s + 8)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onChange(of: glossary) {
                            Config.transcriptionGlossary = $1
                            state.noteConnectedGlossaryManualEdit($1)
                        }
                        .accessibilityLabel("Your own recognition glossary")
                        .accessibilityIdentifier("settings.transcription.glossary")
                    if !glossary.isEmpty {
                        // Русский счёт, а не «term/terms»: 1 термин, 2 термина,
                        // 5 терминов. Английское «-s» на числе — та мелочь, по
                        // которой сразу видно переведённый продукт.
                        Text("\(Config.glossaryTerms.count) \(DisplayFormatting.termsWord(Config.glossaryTerms.count)) active")
                            .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
                    }

                    Divider().overlay(Theme.hairline)

                    SettingsRow {
                        Label("Take hints from work applications", systemImage: "app.connected.to.app.below.fill")
                            .labelStyle(SettingLabelStyle())
                        Spacer()
                        Toggle("", isOn: $state.useConnectedAppsInPrompts)
                            .labelsHidden().toggleStyle(.switch)
                            .accessibilityLabel("Take transcription hints from work applications")
                            .accessibilityIdentifier("settings.transcription.glossary-suggestions.enabled")
                    }

                    SettingsRow {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Find names and terms")
                                .font(Typo.callout).foregroundStyle(Theme.ink)
                            Text(connectedGlossaryCostCaption)
                                .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if state.connectedGlossarySuggestionStatus == .loading {
                            ProgressView().controlSize(.small)
                        }
                        Button("Find terms") {
                            Task { await state.generateConnectedGlossarySuggestions() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!state.canGenerateConnectedGlossarySuggestions)
                        .accessibilityIdentifier("settings.transcription.glossary-suggestions.generate")
                    }

                    if state.connectedGlossarySourceCount == 0 {
                        HStack {
                            Text("Connect an application that can be read first.")
                                .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
                            Spacer()
                            Button("Work applications") { state.selectedSettingsTab = .connectedApps }
                                .buttonStyle(.link)
                                .accessibilityIdentifier("settings.transcription.glossary-suggestions.open-apps")
                        }
                    }

                    if let message = connectedGlossaryStatusMessage {
                        Text(message)
                            .font(Typo.caption)
                            .foregroundStyle(connectedGlossaryStatusIsError
                                ? Theme.danger : Theme.inkTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("settings.transcription.glossary-suggestions.status")
                    }

                    if !state.connectedGlossarySuggestions.isEmpty {
                        ForEach(state.connectedGlossarySuggestions) { suggestion in
                            HStack(alignment: .top, spacing: Space.s) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.term)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Theme.ink)
                                    Text(suggestion.reason + sourceSuffix(suggestion.sources))
                                        .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: Space.s)
                                Button("Hide") {
                                    state.rejectConnectedGlossarySuggestion(id: suggestion.id)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Hide \(suggestion.term)")
                                Button("Add") {
                                    if state.acceptConnectedGlossarySuggestion(id: suggestion.id) {
                                        glossary = Config.transcriptionGlossary
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .accessibilityLabel("Add \(suggestion.term) to the transcription glossary")
                            }
                            .padding(.vertical, 3)
                        }
                        HStack {
                            if let metrics = state.connectedGlossarySuggestionMetrics {
                                Text("sources: \(metrics.sourceCount) · input tokens: \(metrics.estimatedInputTokens)\(metrics.cached ? " · cached" : "") · your AI provider meters the spend")
                                    .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
                            }
                            Spacer()
                            Button("Hide all") {
                                state.rejectAllConnectedGlossarySuggestions()
                            }
                            .buttonStyle(.link)
                            .accessibilityIdentifier("settings.transcription.glossary-suggestions.dismiss-all")
                        }
                    }
                }
            }
            .padding(Space.xl)
        }
        .frame(width: 520, height: 620)
        .onAppear {
            transcriptionLanguage = Config.transcriptionLanguage
            glossary = Config.transcriptionGlossary
            localModel = Config.localWhisperModel
            micNoiseSuppression = Config.micNoiseSuppressionEnabled
            adaptiveLocal = Config.adaptiveLocalWhisperEnabled
            postStopFinalPass = Config.transcriptionPostStopFinalPassEnabled
            localSpeakerLabels = Config.localDiarizationEnabled
            remoteSpeakerCount = Config.localDiarizationRemoteSpeakerCount
            assemblyDiarization = Config.assemblyAIDiarizationEnabled
            firefliesEnhance = Config.firefliesTranscriptEnhanceEnabled
        }
    }

    private var connectedGlossaryCostCaption: String {
        let model = LLMCatalog.background(for: Config.selectedModel)
        // Стоимость здесь не называется: считать её при inputTokens: 0 значит
        // печатать ноль. Строка вычислялась и выбрасывалась — предупреждение
        // компилятора про неё нашла scripts/proverka-preduprezhdenij.sh в тот
        // день, когда её научили ронять прогон.
        return "Reads no more than \(ConnectedGlossarySuggestionService.maxSources) short excerpts from the applications and ranks the terms it found with \(model.label). The call transcript goes nowhere in the process."
    }

    private var connectedGlossaryStatusMessage: String? {
        if let message = state.connectedGlossarySuggestionMessage { return message }
        switch state.connectedGlossarySuggestionStatus {
        case .idle, .loading, .ready: return nil
        case .empty: return "No new terms from the connected applications."
        case .unavailable(let message), .failed(let message): return message
        }
    }

    private var connectedGlossaryStatusIsError: Bool {
        switch state.connectedGlossarySuggestionStatus {
        case .unavailable, .failed: return true
        default: return false
        }
    }

    private func sourceSuffix(_ sources: [String]) -> String {
        sources.isEmpty ? "" : " · " + sources.joined(separator: ", ")
    }
}

// MARK: - Tab 3 · AI (plan, model, co-pilot)

private struct AISettingsTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            // Блока «Тариф» здесь нет и не будет. Значок кредитной карты,
            // бейдж плана и кнопка «Управление…» — это интерфейс продукта, за
            // который платят; cruxwing бесплатен целиком, и строка про план
            // означала бы, что где-то есть другой.

            // Выше выбора модели: модель без ключа не отвечает, а в готовом
            // установщике ключей нет ни одного.
            SettingsSection(title: "Provider keys",
                            caption: "The key is entered once and lives in the Keychain. Spend goes through your own contract with the provider — cruxwing is not a middleman and takes no money. Without a key the model will not answer: keys are deliberately not baked into the ready-made installers.") {
                ProviderKeysSection()
            }

            SettingsSection(title: "Model",
                            caption: "Choose a provider and a version — or leave «Auto» and cruxwing picks one per request. Every model is available: none are withheld.") {
                ModelSelectionRows()
            }

            SettingsSection(title: "Copilot",
                            caption: Config.managedUsageLimitsEnabled
                                ? "Looks for blind spots as the recording goes, against your goal and the transcript. The observations share one hourly budget: switch one off and the rest refresh more often."
                                : "Off by default. Turned on, cruxwing may propose a goal and a title, update the summary, enrich the transcript from Fireflies and run the checks you selected, as well as make extra passes for clarifications and follow-up questions. Every pass is a separate request under your contract with the AI provider. While the switch is off there are no background or extra passes; an explicit action may still make several requests to read connected sources, poll a council of models, or fall back to another provider.") {
                SettingsRow {
                    Label("Automatic AI requests", systemImage: "bolt.horizontal.circle")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.automaticProviderRequestsEnabled },
                        set: { state.setAutomaticProviderRequestsEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel("Automatic AI requests")
                        .accessibilityIdentifier("settings.ai.automatic-provider-requests")
                }
                SettingsRow {
                    Label("Brainstorming during a call", systemImage: "lightbulb")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.blindSpotsEnabled },
                        set: { state.setBlindSpotsEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel("Brainstorming during a call")
                        .accessibilityIdentifier("settings.ai.brainstorm")
                        .disabled(!state.automaticProviderRequestsEnabled)
                }
                SettingsRow {
                    Label("Agenda and framing", systemImage: "scope")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.agendaCheckingEnabled },
                        set: { state.setAgendaCheckingEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel("Agenda and framing")
                        .accessibilityIdentifier("settings.ai.agenda")
                        .disabled(!state.automaticProviderRequestsEnabled)
                }
                SettingsRow {
                    Label("Fact checking during a call", systemImage: "checkmark.seal")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.liveFactCheckingEnabled },
                        set: { state.setFactCheckDuringCallsEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel("Fact checking during a call")
                        .accessibilityIdentifier("settings.ai.fact-check")
                        .disabled(!state.automaticProviderRequestsEnabled)
                }
                SettingsRow {
                    Label("Watching the rhetoric", systemImage: "text.badge.xmark")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.rhetoricWatchEnabled },
                        set: { state.setRhetoricDuringCallsEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel("Watching the rhetoric")
                        .accessibilityIdentifier("settings.ai.rhetoric")
                        .disabled(!state.automaticProviderRequestsEnabled)
                }
                SettingsRow {
                    Label("Watching how the call is going", systemImage: "location.north.line")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { state.facilitationWatchEnabled },
                        set: { state.setFacilitationDuringCallsEnabled($0) }))
                        .labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel("Watching how the call is going")
                        .accessibilityIdentifier("settings.ai.facilitation")
                        .disabled(!state.automaticProviderRequestsEnabled)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 520)
    }
}

// MARK: - Tab 4 · Connected Apps (Google · MCP · team sources)

private struct ConnectedAppsTab: View {
    @EnvironmentObject var state: AppState
    @State private var teamSourcesExpanded = !TeamConnectors.configured.isEmpty

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                // Первым блоком, а не по алфавиту: человек, у которого задачи
                // в Яндекс Трекере, ищет здесь именно его. Список, начатый с
                // Notion, читается как «нашего нет» — и дальше не листается.
                SettingsSection(title: "Russian trackers",
                                caption: "These services have no MCP server, so they connect by token: create one in your tracker and paste it here. The token lives in the Keychain, and requests go straight to the service.") {
                    RussianTrackersSection()
                }

                // Сразу за трекерами: вопрос соседний, но другой — не
                // «заводили ли задачу», а «обсуждали ли это». Ответ на второй
                // чаще лежит в переписке, чем в трекере.
                SettingsSection(title: "Work messengers",
                                caption: "Пачка, Mattermost and Rocket.Chat can search messages. Telegram connects through a bot of its own: the Bot API does not hand over old history, so cruxwing archives locally and searches only messages that arrive after connecting.") {
                    WorkMessengersSection()
                }

                SettingsSection(title: "Self-hosted open trackers",
                                caption: "GitLab, Gitea (and Forgejo, a fork of Gitea with the same API), Redmine, Plane, GitFlic and Jira are hosted by the team itself, so besides a token they need a server address. Jira here is only the self-hosted one: the cloud version connects over MCP above. GitHub connects above: its address is always the same. Plane and GitFlic have no word search — cruxwing looks through the most recent issues and writes under the answer how many it looked through.") {
                    SelfHostedTrackersSection()
                }

                // Западные трекеры отдельно от предыдущей секции: там адрес
                // сервера обязателен, здесь его нет вовсе.
                SettingsSection(title: "Western trackers",
                                caption: "Linear and Trello are cloud services, so no address is needed. Linear's key is pasted as is; Trello needs an application key besides the token — both come from the same page, trello.com/power-ups/admin. The keys live in the Keychain, and requests go straight to the service.") {
                    WesternTrackersSection()
                }

                SettingsSection(title: "Knowledge base",
                                caption: "Outline, BookStack, Wiki.js and Nextcloud can search documents, and cruxwing asks them during a call: a decision written into a wiki six months ago will not be found in issues or in chat. Яндекс Вики and Teamly cannot be connected — the first has no text search in its public documentation, and the second publishes no API description at all.") {
                    TeamNotesSection()
                }

                SettingsSection(title: "Notes on this computer",
                                caption: "An Obsidian vault, or any directory of .md files. The one source that needs neither a key nor a network: cruxwing reads your disk and sends nothing anywhere. A large vault is not read in full — the program writes under the answer how many files it actually read.") {
                    LocalNotesSection()
                }

                SettingsSection(title: "Google",  // имя сервиса, не переводится
                                caption: "Calendar, Docs, Sheets and Drive connect through separate permissions that you control. Search is read-only; when exporting, cruxwing creates and changes only the files it created itself.") {
                    GoogleSignInRow()
                }

                SettingsSection(title: "Work applications",
                                caption: "MCP servers connect in one click: ordinary OAuth in the browser, no keys. The tokens stay in the Keychain. Salesforce, Affinity and thousands of others go through Zapier.") {
                    MCPAppsSection()
                }

                if Config.llmViaBackend {
                    SettingsSection(title: "Calls, in your own AI tool",
                                    caption: "Managed compatibility provides an MCP address for calls and the decision log.") {
                        OwnMCPCard()
                    }
                }

                // Expanding block: collapsed by default unless connectors are
                // configured — most users never need this section.
                DisclosureGroup(isExpanded: $teamSourcesExpanded) {
                    TeamSourcesView()
                        .padding(.top, Space.s)
                } label: {
                    HStack(spacing: Space.s) {
                        SectionLabel("Team sources")
                        if !TeamConnectors.configured.isEmpty {
                            Text("configured: \(TeamConnectors.configured.count)")
                                .font(Typo.caption)
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
                .disclosureGroupStyle(.automatic)
            }
            .padding(Space.xl)
        }
        .frame(width: 560, height: 620)
    }
}

/// The Granola-style "public MCP URL + three steps" card. The URL is the
/// backend's /mcp endpoint; auth happens in the AI tool's own browser flow.
private struct OwnMCPCard: View {
    @State private var copied = false

    private var mcpURL: String {
        Config.backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines) + "/mcp"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Text(mcpURL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .padding(.horizontal, Space.m)
                    .frame(height: 30)
                    .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(mcpURL, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Typo.caption.weight(.medium))
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel("Copy the MCP address")
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                setupStep(1, "In your own AI tool, add cruxwing as a connector at the address above.")
                setupStep(2, "Confirm the sign-in in the browser, with the same email you use in cruxwing.")
                setupStep(3, "Conversation, search and call context in any tool.")
            }
        }
    }

    private func setupStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text("\(number)")
                .font(Typo.caption.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Theme.accentSoft.opacity(0.5)))
            Text(text)
                .font(Typo.caption)
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Tab 5 · Account & Privacy

private struct AccountPrivacyTab: View {
    @State private var outboundRedaction: Bool = Config.outboundRedactionEnabled
    @State private var redactionTerms: String = Config.redactionTermsRaw
    @ObservedObject private var redactionLog = OutboundRedactionLog.shared
    @EnvironmentObject var state: AppState
    @State private var showSignIn = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var devTierPreview: String = Config.devTierOverride?.rawValue ?? "off"

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            // Раздел показывается, только когда есть куда входить.
            //
            // Он единственный из четырёх мест со входом не был ничем закрыт —
            // остальные смотрят на `wheesprAvailable`, и после того как адрес
            // сервера перестал зашиваться, они исчезли сами. А этот оставался
            // на экране и обещал ровно то, чего у cruxwing нет: «модели без своих
            // ключей» (нет сервера) и синхронизацию журнала решений (тоже нет).
            // Ключ провайдера вводится ниже, в разделе «ИИ», и вход для него не
            // нужен.
            if Config.llmViaBackend {
                SettingsSection(title: "Account",
                                caption: "Signing in is what lets you use models without your own keys and sync the decision log.") {
                    WheesprAccountRow(showSheet: $showSignIn)

                    if state.wheesprConnected {
                        SettingsRow {
                            Label("Delete the account", systemImage: "trash")
                                .labelStyle(SettingLabelStyle())
                            Spacer()
                            Button(deleting ? "Deleting…" : "Delete…", role: .destructive) {
                                confirmDelete = true
                            }
                            .disabled(deleting)
                            .accessibilityIdentifier("settings.account.delete")
                        }
                    }
                }
            }

            SettingsSection(title: "Recording consent",
                            caption: "Before your first recording you confirmed that the participants' consent is your responsibility. Revoke it and the consent screen appears again.") {
                SettingsRow {
                    Label(Config.recordingConsentAccepted ? "Consent confirmed" : "Not confirmed yet",
                          systemImage: Config.recordingConsentAccepted ? "checkmark.shield" : "shield")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    if Config.recordingConsentAccepted {
                        Button("Revoke") { Config.recordingConsentAccepted = false }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("settings.privacy.revoke-recording-consent")
                    }
                }
            }

            SettingsSection(title: "Strip secrets before sending",
                            caption: "Card numbers, API keys, document numbers and signed credentials are stripped from everything that goes to the AI provider. They are recognised by structure: a card's checksum adds up, a key has a known prefix — so ordinary numbers from the call (dates, prices, a meeting-room number) stay where they are. The request is not blocked: the secret is removed and the rest goes on.") {
                SettingsRow {
                    Label("Filter outgoing requests", systemImage: "eye.slash")
                        .labelStyle(SettingLabelStyle())
                    Spacer()
                    Toggle("", isOn: $outboundRedaction)
                        .labelsHidden()
                        .onChange(of: outboundRedaction) { Config.outboundRedactionEnabled = $1 }
                        .accessibilityLabel("Filter outgoing requests")
                        .accessibilityIdentifier("settings.privacy.outbound-redaction")
                }
                SettingsRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Remove these terms too", systemImage: "text.badge.minus")
                            .labelStyle(SettingLabelStyle())
                        Text("Project code names, customer names — one per line. They are stripped wherever they appear.")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.inkTertiary)
                        TextEditor(text: $redactionTerms)
                            .font(Typo.mono)
                            .frame(height: 64)
                            .onChange(of: redactionTerms) { Config.redactionTermsRaw = $1 }
                            .accessibilityIdentifier("settings.privacy.redaction-terms")
                    }
                }
                // Only when something was actually removed. A marker on every
                // session would train people to ignore it.
                if let summary = redactionLog.summary {
                    SettingsRow {
                        Label(summary, systemImage: "checkmark.shield")
                            .labelStyle(SettingLabelStyle())
                            .foregroundStyle(Theme.inkSecondary)
                        Spacer()
                    }
                }
            }

            SettingsSection(title: "Where your data goes",
                            caption: "Transcription runs on this computer by default. Parts of the transcript go to the provider of the chosen model when you run an AI action or explicitly turn on automatic requests — the model list shows whose provider that is. Nothing is sold or used for advertising.") {
                EmptyView()
            }

            if Config.isDevBuild {
                SettingsSection(title: "Developer",
                                caption: "Developer builds only — a released application has no such section. The preview switches the same limits a user on that plan sees. «Real access» puts everything back as it was.") {
                    SettingsRow {
                        Label("View the plan", systemImage: "wrench.and.screwdriver")
                            .labelStyle(SettingLabelStyle())
                        Spacer()
                        Picker("", selection: $devTierPreview) {
                            Text("Real access").tag("off")
                            ForEach(Tier.allCases) { tier in
                                Text(tier.label).tag(tier.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                        .onChange(of: devTierPreview) { state.setDevTierOverride(Tier(rawValue: $1)) }
                        .accessibilityLabel("View the plan")
                        .accessibilityIdentifier("settings.developer.preview-plan")
                    }
                    if let preview = Tier(rawValue: devTierPreview) {
                        SettingsRow {
                            Label("This plan includes", systemImage: "checklist")
                                .labelStyle(SettingLabelStyle())
                            Spacer()
                            Text(Self.devTierSummary(preview))
                                .font(Typo.caption)
                                .foregroundStyle(Theme.inkSecondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .padding(Space.xl)
        .frame(width: 520)
        .onAppear {
            devTierPreview = Config.devTierOverride?.rawValue ?? "off"
        }
        .sheet(isPresented: $showSignIn) { SignInSheet() }
        .confirmationDialog("Delete the account?", isPresented: $confirmDelete) {
            Button("Delete the account and all data", role: .destructive) {
                deleting = true
                Task {
                    _ = await state.deleteAccount()
                    deleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The account and its sessions will be deleted from the server permanently. Calls saved on this computer are untouched.")
        }
    }

    /// What the previewed plan grants, in the same units the app enforces.
    private static func devTierSummary(_ tier: Tier) -> String {
        let allowance = TariffAllowance.forTier(tier)
        let models = LLMCatalog.all.filter { $0.isAvailable(for: tier) }.count
        return "\(models) models · \(allowance.copilotHours)h of copilot · "
            + "\(allowance.computeCredits) credits · \(allowance.groundedCycles) grounded cycles a month"
    }
}

// MARK: - Shared building blocks

struct SettingsRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Space.m) { content }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(title)
            VStack(alignment: .leading, spacing: Space.s) { content }
            Text(caption)
                .font(Typo.caption)
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, Space.xxs)
        }
    }
}

/// One selectable transcription engine, presented by its core advantage.
private struct EngineChoiceRow: View {
    let engine: TranscriptionEngine
    let selected: Bool
    let available: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Space.m) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Theme.accent : Theme.inkTertiary)
                    .padding(.top, 1)
                Image(systemName: engine.advantageSymbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.advantageTitle)
                        .font(Typo.callout.weight(.medium))
                        .foregroundStyle(Theme.ink)
                    Text(engine.advantageCaption)
                        .font(Typo.caption)
                        .foregroundStyle(Theme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !available {
                    Text("Not in this build")
                        .font(Typo.caption)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .background(selected ? Theme.accentSoft.opacity(0.4) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.5) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.55)
        .accessibilityLabel("transcription engine: \(engine.advantageTitle)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityIdentifier("settings.transcription.engine.\(engine.rawValue)")
    }
}

// MARK: - Plan badge

private struct PlanBadge: View {
    let tier: Tier
    var body: some View {
        Text(tier.label.uppercased())
            .font(Typo.label)
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, Space.s)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.accentSoft))
    }
}

// MARK: - Google sign-in

private struct GoogleSignInRow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Label(state.googleConnected ? "Google Workspace connected" : "Google Workspace",
                          systemImage: state.googleConnected ? "checkmark.seal.fill" : "square.grid.2x2")
                        .labelStyle(SettingLabelStyle())
                    if state.googleConnected {
                        let count = state.promptWorkflowCount(usingSourcePrefix: "google:")
                        Text("ready-made scenarios: \(count)")
                            .font(Typo.caption)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                Spacer()
                if state.googleConnecting {
                    ProgressView().controlSize(.small)
                    Text("Connecting…")
                        .font(Typo.caption)
                        .foregroundStyle(Theme.inkSecondary)
                    Button("Cancel") { state.cancelGoogleConnection() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("settings.connected.google.cancel")
                } else if state.googleConnected {
                    Button("Disconnect") { state.disconnectGoogle() }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("settings.connected.google.disconnect")
                } else {
                    GoogleSignInButton(enabled: state.hasGoogleSignInClient) {
                        Task { await state.connectGoogle() }
                    }
                }
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))

            // Granular authorization: each service is a separate scope in the
            // OAuth grant — disabled ones are excluded from the token itself.
            GoogleServiceToggles()

            if !state.hasGoogleClientID {
                Text("Add GOOGLE_CLIENT_ID to app/.env and rebuild cruxwing.")
                    .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
            } else if !state.hasGoogleClientSecret {
                Text("Add GOOGLE_CLIENT_SECRET for the same Google Desktop OAuth client and rebuild cruxwing.")
                    .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
            } else if let error = state.googleConnectionError, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Typo.caption)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else if state.googleConnected,
                      Config.googleScopeVersion < GoogleAuth.scopeVersion
                        || Config.googleGrantedServices != Config.googleEnabledServices {
                HStack(spacing: Space.s) {
                    Text("Access or search changed — reconnect to apply it.")
                        .font(Typo.caption).foregroundStyle(Theme.accentText)
                    Button("Reconnect") { Task { await state.connectGoogle() } }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(state.googleConnecting)
                        .accessibilityIdentifier("settings.connected.google.reconnect")
                }
            }
        }
    }
}

/// Per-service switches controlling what the Google grant may cover.
private struct GoogleServiceToggles: View {
    @State private var enabled = Config.googleEnabledServices

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), alignment: .leading)],
                  alignment: .leading, spacing: Space.s) {
            ForEach(GoogleService.requestable) { service in
                Toggle(service.label, isOn: Binding(
                    get: { enabled.contains(service.rawValue) },
                    set: { on in
                        if on { enabled.insert(service.rawValue) }
                        else { enabled.remove(service.rawValue) }
                        Config.googleEnabledServices = enabled
                    }
                ))
                .toggleStyle(.checkbox)
                .font(Typo.caption)
                .accessibilityIdentifier("settings.connected.google.service.\(service.rawValue)")
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 6)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
    }
}

/// Google-styled sign-in button (white surface, colored "G", clear label).
private struct GoogleSignInButton: View {
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Text("G").font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(enabled ? Theme.accent : Theme.inkTertiary)
                Text("Connect Google Calendar")
                    .font(Typo.callout.weight(.semibold))
                    .foregroundStyle(enabled ? Theme.ink : Theme.inkTertiary)
            }
            .padding(.horizontal, Space.m).padding(.vertical, 7)
            .background(Capsule().fill(hovering && enabled ? Theme.surfaceHover : Theme.surface))
            .overlay(Capsule().strokeBorder(Theme.hairlineStrong, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .help(enabled ? "Connect Google Calendar (and Docs and Sheets if you need them)" : "Google Calendar is unavailable in this build")
        .accessibilityIdentifier("settings.connected.google.connect")
        .animation(Motion.quick, value: hovering)
    }
}

// MARK: - Account row (sign in / out)

private struct WheesprAccountRow: View {
    @EnvironmentObject var state: AppState
    @Binding var showSheet: Bool

    private var title: String {
        guard state.wheesprConnected else { return "Account" }
        if let email = state.wheesprEmail, !email.isEmpty { return "Signed in · \(email)" }
        return "Signed in"
    }

    var body: some View {
        HStack(spacing: Space.s) {
            Label(title, systemImage: state.wheesprConnected ? "checkmark.seal.fill" : "person.crop.circle")
                .labelStyle(SettingLabelStyle())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if !state.wheesprAvailable {
                Text("Unavailable in this build")
                    .font(Typo.caption).foregroundStyle(Theme.inkTertiary)
            } else if state.wheesprConnected {
                Button("Sign out") { state.signOutWheespr() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("settings.account.sign-out")
            } else {
                Button("Sign in") { showSheet = true }
                    .buttonStyle(QuietButtonStyle(prominent: true))
                    .accessibilityIdentifier("settings.account.sign-in")
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// Account sign-in: optional social (Apple / Google account) when the feature
/// flag is on, plus first-party Email code / Password / Phone.
struct SignInSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var code = ""
    // Additional providers (password / phone)
    @State private var method = "code"
    @State private var password = ""
    @State private var registering = false
    @State private var phone = ""
    @State private var phoneCodeSent = false
    @State private var working = false
    @State private var providerError: String?

    private var codeStep: Bool { state.pendingAuthEmail != nil }
    /// Judged per provider: Apple waits on App Store Connect verification,
    /// Google only needs a configured client.
    private var showsApple: Bool { SocialSignIn.showsApple() }
    private var showsGoogle: Bool {
        SocialSignIn.showsGoogle(hasClient: state.hasGoogleSignInClient)
    }
    private var socialEnabled: Bool {
        SocialSignIn.showsDivider(apple: showsApple, google: showsGoogle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Label("Sign in", systemImage: "person.crop.circle").font(Typo.title).foregroundStyle(Theme.ink)

            if socialEnabled {
                socialButtons
                HStack {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                    Text("or").font(Typo.caption).foregroundStyle(Theme.inkTertiary)
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }

            Picker("", selection: $method) {
                Text("Code from the email").tag("code")
                Text("Password").tag("password")
                Text("Phone").tag("phone")
            }
            .pickerStyle(.segmented).labelsHidden()

            if method == "password" {
                passwordFlow
            } else if method == "phone" {
                phoneFlow
            } else if !codeStep {
                Text("We will send a six-digit code to your email — no password needed.")
                    .font(Typo.callout).foregroundStyle(Theme.inkSecondary)
                field($email, prompt: "you@company.com")
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle())
                    Button(state.authWorking ? "Sending…" : "Send the code") {
                        Task { await state.requestSignInCode(email: email) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.authWorking)
                }
            } else {
                Text("Enter the code sent to \(state.pendingAuthEmail ?? "").")
                    .font(Typo.callout).foregroundStyle(Theme.inkSecondary)
                field($code, prompt: "123456")
                HStack {
                    Button("Back") { state.cancelSignIn(); code = "" }.buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button(state.authWorking ? "Verifying…" : "Verify") {
                        Task { await state.verifySignIn(code: code) }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.authWorking)
                }
            }
        }
        .padding(Space.xl).frame(width: 420).background(Theme.canvas)
        .onChange(of: state.wheesprConnected) { if $1 { dismiss() } }
    }

    // MARK: Social account login (equal prominence when enabled)

    private var socialButtons: some View {
        VStack(spacing: Space.s) {
            if showsApple {
                Button {
                    Task { await state.signInWithApple() }
                } label: {
                    Label("Sign in with Apple", systemImage: "apple.logo")
                        .font(Typo.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(state.authWorking)
            }

            if showsGoogle {
            Button {
                Task { await state.signInWithGoogleAccount() }
            } label: {
                HStack(spacing: Space.s) {
                    Text("G").font(.system(size: 13, weight: .bold, design: .rounded))
                    Text(state.authWorking ? "Start the Google sign-in again" : "Continue with Google")
                        .font(Typo.callout.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            // The flow signs in with googleSignInClientID/Secret, so that is the
            // credential the button's enabled state must reflect. Checking the
            // connector client instead could offer a button that cannot run, or
            // grey out one that can.
            //
            // Deliberately NOT disabled while authWorking: an abandoned browser
            // window keeps the flow alive for two minutes, and a greyed-out
            // button during that window was exactly the reported "wanted to
            // sign in with a different account and the button was disabled".
            // A click during a live flow cancels it and starts fresh (the
            // Google picker then offers every Chrome profile again).
            .buttonStyle(QuietButtonStyle(prominent: true))
            .disabled(!state.hasGoogleSignInClient)
            .help(state.authWorking
                  ? "The sign-in window is already open — click to start again"
                  : "Sign in to cruxwing with Google")
            }

            Text("Signing in is not the same as connecting Google Calendar under «Work applications».")
                .font(Typo.caption)
                .foregroundStyle(Theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Password provider

    private var passwordFlow: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            field($email, prompt: "you@company.com")
            SecureField("", text: $password, prompt: Text("password (at least 8 characters)"))
                .textFieldStyle(.plain).padding(Space.m)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            Toggle("Create an account", isOn: $registering)
                .toggleStyle(.checkbox).font(Typo.caption)
            if let providerError {
                Text(providerError).font(Typo.caption).foregroundStyle(Theme.recordRed)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle())
                Button(working ? "Working…" : (registering ? "Create an account" : "Sign in")) {
                    Task { await runProvider {
                        registering
                            ? try await WheesprAuth.registerPassword(email: email, password: password)
                            : try await WheesprAuth.loginPassword(email: email, password: password)
                    } }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working || email.isEmpty || password.count < 8)
            }
        }
    }

    // MARK: Phone provider (Код из SMS)

    private var phoneFlow: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            field($phone, prompt: "+15551234567")
                .disabled(phoneCodeSent)
            if phoneCodeSent { field($code, prompt: "Code from SMS") }
            if let providerError {
                Text(providerError).font(Typo.caption).foregroundStyle(Theme.recordRed)
            }
            HStack {
                if phoneCodeSent {
                    Button("Back") { phoneCodeSent = false; code = "" }.buttonStyle(QuietButtonStyle())
                }
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(QuietButtonStyle())
                Button(working ? "Sending…" : (phoneCodeSent ? "Check" : "Send the code by SMS")) {
                    Task {
                        if phoneCodeSent {
                            await runProvider { try await WheesprAuth.verifyPhone(phone: phone, code: code) }
                        } else {
                            working = true; providerError = nil
                            defer { working = false }
                            do { try await WheesprAuth.requestPhoneCode(phone: phone); phoneCodeSent = true }
                            catch { providerError = error.localizedDescription }
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working || phone.isEmpty || (phoneCodeSent && code.isEmpty))
            }
        }
    }

    /// Run a provider sign-in through the shared `applySession` path.
    private func runProvider(_ signIn: @escaping () async throws -> WheesprSession) async {
        working = true
        providerError = nil
        defer { working = false }
        do {
            let session = try await signIn()
            state.applySession(session)
        } catch {
            providerError = error.localizedDescription
        }
    }

    private func field(_ text: Binding<String>, prompt: String) -> some View {
        TextField("", text: text, prompt: Text(prompt))
            .textFieldStyle(.plain).padding(Space.m)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

struct SettingLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) {
            configuration.icon
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
            configuration.title
                .font(Typo.callout.weight(.medium))
                .foregroundStyle(Theme.inkSecondary)
        }
    }
}
