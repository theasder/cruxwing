import Foundation

/// Supplies the read loop with what it cannot reach from a gateway.
///
/// `LLMGatewayFactory.make()` runs before any `AppState` exists, so the gateway
/// cannot hold one. This is the seam that lets it ask, at request time, which
/// connectors are available and whether a call is live — both of which change
/// during a session and must not be captured at construction.
///
/// Empty by default, which makes the loop inert: with no provider wired the
/// gateway does not append the tool instruction at all. That is the right
/// default for tests and for a build where connectors are not configured.
final class AgenticReadContext: @unchecked Sendable {
    static let shared = AgenticReadContext()

    private let lock = NSLock()
    private var executorProvider: (() async -> AgenticReadExecutor?)?
    private var recordingProvider: (() async -> Bool)?
    private var turnSink: ((AgenticReadStep.Turn) -> Void)?

    private init() {}

    /// Wired once by AppState at startup.
    func configure(executor: @escaping () async -> AgenticReadExecutor?,
                   isRecording: @escaping () async -> Bool,
                   onTurnComplete: @escaping (AgenticReadStep.Turn) -> Void) {
        lock.lock(); defer { lock.unlock() }
        executorProvider = executor
        recordingProvider = isRecording
        turnSink = onTurnComplete
    }

    // Снимок под замком делается в СИНХРОННОЙ функции.
    //
    // Замок и раньше не удерживался через await — значение копировалось и
    // сразу отпускалось. Но в Swift 6 `NSLock.lock()` внутри async-функции
    // запрещён сам по себе, независимо от того, что идёт следом: компилятор
    // называет это ошибкой языка. Приложение перестало бы собираться.
    private func currentExecutorProvider() -> (() async -> AgenticReadExecutor?)? {
        lock.lock(); defer { lock.unlock() }
        return executorProvider
    }

    private func currentRecordingProvider() -> (() async -> Bool)? {
        lock.lock(); defer { lock.unlock() }
        return recordingProvider
    }

    func executor() async -> AgenticReadExecutor? {
        await currentExecutorProvider()?()
    }

    func isRecording() async -> Bool {
        await currentRecordingProvider()?() ?? false
    }

    func record(_ turn: AgenticReadStep.Turn) {
        lock.lock()
        let sink = turnSink
        lock.unlock()
        sink?(turn)
    }

    /// Test seam: restore the inert default.
    func reset() {
        lock.lock(); defer { lock.unlock() }
        executorProvider = nil
        recordingProvider = nil
        turnSink = nil
    }
}
