import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const sourceRoot = resolve(repo, 'app', 'Sources', 'MeetGPT');

function productionSwiftFiles() {
  return execFileSync('git', [
    'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--',
    'app/Sources/MeetGPT',
  ], { cwd: repo }).toString('utf8').split('\0')
    .filter((file) => file.endsWith('.swift') && existsSync(resolve(repo, file)));
}

test('public app does not compile inherited analytics, feedback upload, or StoreKit billing', () => {
  const removed = [
    'Integrations/AnalyticsEvent.swift',
    'Integrations/FunnelTracker.swift',
    'Integrations/SurfaceTracking.swift',
    'Integrations/StoreKitBridge.swift',
    'Integrations/StoreKitPurchaser.swift',
    'Views/Paywall/PaywallView.swift',
    'Feedback/FeedbackUploader.swift',
    'Feedback/FirstMeetingFeedbackSheet.swift',
    'Feedback/FirstMeetingPrompt.swift',
  ];
  for (const relative of removed) {
    assert.equal(existsSync(resolve(sourceRoot, relative)), false,
      `inherited first-party collection or commerce source returned: ${relative}`);
  }

  const files = productionSwiftFiles();
  assert.ok(files.length > 200,
    `source scan found only ${files.length} Swift files; the policy would be vacuous`);
  const source = files.map((file) => readFileSync(resolve(repo, file), 'utf8')).join('\n');
  for (const marker of [
    '/api/funnel',
    '/api/feedback',
    '/api/billing/storekit',
    '/api/billing/checkout',
    '/api/promo',
    '/api/subscribe',
    '/api/trial/device-claim',
    'FunnelTracker.',
    'FeedbackUploader.',
    'trackSurface(',
    'import StoreKit',
    'settings.privacy.analytics',
    'shouldShowPaywall',
    'paywallChoiceMade',
    'postTrialPromptShown',
    'LiveTestPromoRedemptionReceipt',
    'livetest.redeem',
  ]) {
    assert.equal(source.includes(marker), false,
      `compiled app regained an inherited collection/commerce marker: ${marker}`);
  }
});

test('live harness never grants itself paid access or depends on removed promo hooks', () => {
  const video = readFileSync(resolve(repo, 'app', 'videotest.sh'), 'utf8');
  const edge = readFileSync(resolve(repo, 'app', 'edgetest.sh'), 'utf8');
  const plan = readFileSync(resolve(repo, 'app', 'Tests', 'E2E', 'TEST_PLAN.md'), 'utf8');
  const manifestText = readFileSync(
    resolve(repo, 'app', 'Tests', 'E2E', 'coverage-manifest.json'), 'utf8');
  const manifest = JSON.parse(manifestText);
  const corpus = [video, edge, plan, manifestText].join('\n');

  for (const marker of [
    'entitle.sh',
    'livetest.redeem',
    'preparePromoRedemption',
    'DEV-UNLIMITED-LOCAL',
    'promo_redemption',
    'promo_redeem_',
    'paywall.promo-code',
    'SETTINGS-LIVE-PROMO-REDEMPTION',
    'PromoRedemptionReceiptTests',
    'PaywallViewTests',
  ]) {
    assert.equal(corpus.includes(marker), false,
      `removed promo/paywall test dependency returned: ${marker}`);
  }
  assert.match(video, /ORAKUL_LIVETEST_AI_ASSERTIONS/,
    'live AI coverage no longer has an explicit user-configured-provider boundary');
  assert.ok(Array.isArray(manifest.requirements) && manifest.requirements.length > 50,
    'coverage manifest became vacuous while removing the promo requirement');
});

test('every LLM provider key is runtime BYOK with no build-time fallback', () => {
  const build = readFileSync(resolve(repo, 'app', 'build.sh'), 'utf8');
  const config = readFileSync(resolve(repo, 'app', 'Sources', 'MeetGPT', 'Config.swift'), 'utf8');
  const keyStore = readFileSync(
    resolve(repo, 'app', 'Sources', 'MeetGPT', 'AI', 'ProviderKeyStore.swift'), 'utf8');
  const secrets = readFileSync(
    resolve(repo, 'app', 'Sources', 'MeetGPT', 'Secrets.swift'), 'utf8');
  const envExample = readFileSync(resolve(repo, 'app', '.env.example'), 'utf8');

  const buildVariables = [
    'OPENAI_API_KEY',
    'ANTHROPIC_API_KEY',
    'GOOGLE_AI_API_KEY',
    'DEEPSEEK_API_KEY',
    'DASHSCOPE_API_KEY',
    'ZHIPU_API_KEY',
    'MOONSHOT_API_KEY',
  ];
  for (const variable of buildVariables) {
    assert.equal(build.includes(`sw ${variable}`), false,
      `build.sh can still compile the user's ${variable}`);
    assert.equal(envExample.includes(variable), false,
      `.env.example still instructs contributors to supply ${variable} at build time`);
  }
  for (const field of [
    'openAIAPIKey', 'anthropicAPIKey', 'googleAIAPIKey', 'deepSeekAPIKey',
    'dashScopeAPIKey', 'zhipuAPIKey', 'moonshotAPIKey',
  ]) {
    assert.equal(new RegExp(`static let\\s+${field}\\b`).test(build + secrets), false,
      `Secrets regained a baked LLM credential field: ${field}`);
    assert.equal(config.includes(`Secrets.${field}`), false,
      `Config regained a build-time fallback: Secrets.${field}`);
  }
  for (const provider of [
    'openAI', 'anthropic', 'google', 'deepSeek', 'qwen', 'zhipu', 'moonshot',
    'yandexGPT',
  ]) {
    assert.match(config,
      new RegExp(`ProviderKeyStore\\.current\\.key\\(for:\\s*\\.${provider}\\)\\s*\\?\\?\\s*""`),
      `${provider} no longer resolves exclusively from the user's Keychain`);
  }
  assert.doesNotMatch(keyStore, /resolvedKey|\bbaked\b/i,
    'ProviderKeyStore regained a baked-key fallback API');
});

test('direct BYOK has no inherited Orakul credit or monthly research limit', () => {
  const config = readFileSync(resolve(sourceRoot, 'Config.swift'), 'utf8');
  const appState = readFileSync(resolve(sourceRoot, 'AppState.swift'), 'utf8');
  const usage = readFileSync(
    resolve(sourceRoot, 'Tariff', 'UsageTracker.swift'), 'utf8');
  const brainstorm = readFileSync(
    resolve(sourceRoot, 'Views', 'BrainstormPanel.swift'), 'utf8');
  const budget = readFileSync(
    resolve(sourceRoot, 'Views', 'PromptBudgetBar.swift'), 'utf8');

  assert.match(config, /managedUsageLimitsEnabled:\s*Bool\s*\{\s*llmViaBackend\s*\}/,
    'managed limits are no longer tied exclusively to the managed backend');
  assert.match(usage, /UsageLimitPolicy\.permits\([\s\S]{0,240}Config\.managedUsageLimitsEnabled/,
    'connected-app research can regain an Orakul quota in direct mode');
  for (const recorder of ['recordMeeting', 'recordAIRequest', 'recordCopilot']) {
    assert.match(usage,
      new RegExp(`static func ${recorder}\\([^)]*\\) \\{[\\s\\S]{0,160}guard Config\\.managedUsageLimitsEnabled`),
      `${recorder} regained dead local product-analytics writes in direct mode`);
  }
  assert.match(appState, /UsageLimitPolicy\.remaining\([\s\S]{0,180}Config\.managedUsageLimitsEnabled/,
    'automatic co-pilot can regain an inherited monthly cutoff in direct mode');
  assert.match(brainstorm, /Config\.managedUsageLimitsEnabled[\s\S]{0,260}лимита Orakul нет/,
    'the reachable research UI still presents a managed-plan allowance to BYOK users');
  assert.match(budget, /if Config\.llmViaBackend[\s\S]{0,1800}Orakul не продаёт кредиты и не ограничивает запросы/,
    'the direct-provider prompt details are still framed as an Orakul credit product');
  assert.match(budget,
    /private func directContextStatus[\s\S]{0,420}Config\.selectedRequestModel\.contextTokens/,
    'the direct-provider prompt summary regained the managed 6k tariff boundary');
  assert.match(budget,
    /if Config\.llmViaBackend \{ return TokenEstimate\.baseCreditInputTokens \}[\s\S]{0,120}Config\.selectedRequestModel\.contextTokens/,
    'the direct-provider context rail regained the managed 6k tariff boundary');
  assert.doesNotMatch(budget, /у провайдера это дороже|меньше 6k|сверх 6k/,
    'reachable BYOK copy still presents the inherited 6k tariff as provider pricing');
});

test('direct BYOK makes no automatic provider requests until the user opts in', () => {
  const config = readFileSync(resolve(sourceRoot, 'Config.swift'), 'utf8');
  const appState = readFileSync(resolve(sourceRoot, 'AppState.swift'), 'utf8');
  const settings = readFileSync(resolve(sourceRoot, 'Views', 'SettingsView.swift'), 'utf8');

  assert.match(config,
    /automaticProviderRequestsEnabled:[\s\S]{0,260}ai\.automaticProviderRequests[\s\S]{0,120}\?\? false/,
    'automatic provider work no longer defaults to explicit opt-in');
  assert.match(config, /brainstorm\.enabled[\s\S]{0,80}\?\? false/,
    'brainstorm requests regained a default-on setting');
  assert.match(config, /agendacheck\.enabled[\s\S]{0,80}\?\? false/,
    'agenda requests regained a default-on setting');
  assert.match(config,
    /firefliesTranscriptEnhanceEnabled:[\s\S]{0,220}transcription\.firefliesEnhance[\s\S]{0,90}return false/,
    'automatic Fireflies model enhancement regained a default-on setting');

  for (const functionName of [
    'startBrainstorming', 'startAgendaChecking', 'startFactCheckLoop',
    'startRhetoricLoop', 'startFacilitationLoop', 'startTitleSuggestion',
    'startDigestLoop',
  ]) {
    assert.match(appState,
      new RegExp(`func ${functionName}\\([^)]*\\)[^{]*\\{[\\s\\S]{0,420}guard automaticProviderRequestsEnabled`),
      `${functionName} can start provider work without master consent`);
  }
  assert.match(appState,
    /func startGoalSuggestion\([^)]*\)[^{]*\{[\s\S]{0,3600}guard self\.automaticProviderRequestsEnabled else \{ return \}[\s\S]{0,220}let system =/,
    'goal suggestion can reach model inference without master consent');
  assert.match(settings,
    /settings\.ai\.automatic-provider-requests[\s\S]{0,900}disabled\(!state\.automaticProviderRequestsEnabled\)/,
    'Settings no longer exposes and enforces the master automatic-request switch');
  assert.match(settings, /Every pass is a separate request/,
    'Settings stopped disclosing that automatic passes are separate provider requests');

  const setter = appState.slice(
    appState.indexOf('func setAutomaticProviderRequestsEnabled'),
    appState.indexOf('func setBlindSpotsEnabled'));
  assert.match(setter,
    /if !enabled \{ cancelAutomaticFirefliesEnhance\(\) \}[\s\S]{0,220}guard isRecording/,
    'turning automatic requests off while idle can leave Fireflies provider work alive');

  const goal = appState.slice(
    appState.indexOf('private func startGoalSuggestion'),
    appState.indexOf('private func stopGoalSuggestion'));
  const goalModelCall = goal.indexOf('self.llm.streamChat');
  const goalRecheck = goal.lastIndexOf(
    'guard self.automaticProviderRequestsEnabled, !Task.isCancelled', goalModelCall);
  assert.ok(goalModelCall > 0 && goalRecheck > 0 && goalModelCall - goalRecheck < 500,
    'goal inference no longer rechecks consent after connector awaits');

  const digest = appState.slice(
    appState.indexOf('private func foldDigest() async'),
    appState.indexOf('// MARK: - Answer refine', appState.indexOf('private func foldDigest() async')));
  assert.ok((digest.match(/automaticProviderRequestsEnabled/g) ?? []).length >= 3,
    'rolling digest no longer rechecks consent before and after provider work');
  assert.ok((appState.match(/mayEnterAutomaticWatchProviderBoundary\(/g) ?? []).length >= 5,
    'one of the four automatic watches can cross an await without rechecking consent');
  assert.match(appState,
    /func refreshMeetingBrief\(\) async \{[\s\S]{0,300}guard automaticProviderRequestsEnabled/,
    'managed reminder polling can still trigger an ambient model brief with master consent off');

  const firefliesSchedule = appState.slice(
    appState.indexOf('private func scheduleFirefliesEnhance()'),
    appState.indexOf('func enhanceTranscriptWithFirefliesNow'));
  assert.ok((firefliesSchedule.match(/automaticProviderRequestsEnabled/g) ?? []).length >= 2,
    'the automatic Fireflies scheduler no longer guards both scheduling and wake-up');
});

test('connected-app pause and source attribution cover agentic reads', () => {
  const app = readFileSync(resolve(sourceRoot, 'MeetGPTApp.swift'), 'utf8');
  const gateway = readFileSync(
    resolve(sourceRoot, 'AI', 'AgenticReadGateway.swift'), 'utf8');

  assert.match(app,
    /AgenticReadContext\.shared\.configure[\s\S]{0,900}guard state\.useConnectedAppsInPrompts else \{ return nil \}/,
    'the global connected-app pause can be bypassed by mid-answer agentic reads');
  assert.match(gateway,
    /private func complete\([\s\S]{0,420}turn\.sourceNote[\s\S]{0,220}onDelta\(suffix\)/,
    'connector reads can disappear from the visible answer when the attribution sink is absent');
});

test('direct UI does not invent credits or advertise managed-only services', () => {
  const fullContext = readFileSync(
    resolve(sourceRoot, 'AI', 'FullContextRequest.swift'), 'utf8');
  const brainstorm = readFileSync(
    resolve(sourceRoot, 'Views', 'BrainstormPanel.swift'), 'utf8');
  const glossary = readFileSync(
    resolve(sourceRoot, 'AI', 'ConnectedGlossarySuggestionService.swift'), 'utf8');
  const settings = readFileSync(resolve(sourceRoot, 'Views', 'SettingsView.swift'), 'utf8');
  const sidebar = readFileSync(resolve(sourceRoot, 'Views', 'Sidebar.swift'), 'utf8');
  const appState = readFileSync(resolve(sourceRoot, 'AppState.swift'), 'utf8');

  assert.doesNotMatch(fullContext, /baseCreditsByModel|fallbackCredits|Quote\.credits/,
    'full-context UI regained invented Orakul credit pricing');
  assert.doesNotMatch(brainstorm, /quote\.credits/,
    'reachable full-context chip regained invented Orakul credits');
  assert.doesNotMatch(glossary, /estimatedComputeCredits/,
    'connected glossary regained invented Orakul credit estimates');
  assert.match(settings, /if Config\.llmViaBackend[\s\S]{0,320}OwnMCPCard\(\)/,
    'direct Settings can advertise the inherited first-party MCP server');
  assert.match(sidebar, /if Config\.llmViaBackend\s*\{\s*LedgerSection\(\)/,
    'direct Sidebar can advertise the inherited server ledger');
  assert.match(appState,
    /if Config\.llmViaBackend[\s\S]{0,360}writeback:[\s\S]{0,320}else[\s\S]{0,220}composition: "Capture the decision"\)/,
    'direct Log Decision can advertise a managed ledger writeback');

  const brainstormService = readFileSync(
    resolve(sourceRoot, 'AI', 'BrainstormService.swift'), 'utf8');
  const factCheckService = readFileSync(
    resolve(sourceRoot, 'AI', 'FactCheckService.swift'), 'utf8');
  for (const [name, source] of [
    ['brainstorm', brainstormService], ['fact-check', factCheckService],
  ]) {
    assert.match(source,
      /if Config\.llmViaBackend && !base\.isEmpty/,
      `a local direct build can route ${name} through an inherited backend merely because BACKEND_URL is set`);
  }
  assert.match(appState, /var wheesprAvailable: Bool \{\s*Config\.llmViaBackend\s*\}/,
    'direct mode can advertise the inherited account merely because BACKEND_URL is set');
  assert.match(appState, /var ledgerConfigured: Bool \{\s*Config\.llmViaBackend\s*\}/,
    'direct mode can advertise the inherited ledger merely because BACKEND_URL is set');
});

test('copied server pricing contract and commercial research stay out of public Orakul', () => {
  const removed = [
    'app/contract/contract.json',
    'app/Tests/MeetGPTTests/SharedContract.swift',
    'app/docs/ROADMAP-RICE-2026H2.md',
    'app/docs/fireflies-pricing.md',
    'app/docs/fireflies-walkthrough.md',
    'app/docs/integrations-directory.json',
    'app/docs/fireflies-walkthrough/02-meeting-detail.jpg',
    'app/docs/fireflies-walkthrough/03-ai-skills-in-meeting.jpg',
    'app/docs/fireflies-walkthrough/04-skills-marketplace.jpg',
    'app/docs/fireflies-walkthrough/05-pricing-annual.jpg',
    'app/docs/fireflies-walkthrough/06-pricing-monthly.jpg',
  ];
  for (const path of removed) {
    assert.equal(existsSync(resolve(repo, path)), false,
      `inherited server/commercial artifact returned: ${path}`);
  }

  const contractConsumers = [
    'app/Tests/MeetGPTTests/FullContextRequestTests.swift',
    'app/Tests/MeetGPTTests/TariffAllowanceTests.swift',
  ].map((path) => readFileSync(resolve(repo, path), 'utf8')).join('\n');
  assert.doesNotMatch(contractConsumers, /SharedContract|contract\/contract\.json/,
    'tests regained a dependency on the copied server pricing contract');
});
