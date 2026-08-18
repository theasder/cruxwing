#if canImport(AVFoundation)
import AVFoundation
#endif
import Foundation
import OrakulCore

/// Запись с микрофона — единственная часть, которую нельзя проверить тестом.
///
/// Живёт в исполняемой цели, а не в ядре: `OrakulCore` не знает про AVFoundation
/// именно затем, чтобы порт на Windows заменял этот файл, а не переписывал
/// продукт. Всё, что можно решить без микрофона, решено в `AudioAccumulator` и
/// покрыто тестами; здесь остался тонкий слой поверх системного API.
///
/// Системный звук — то, что говорят собеседники, — сюда пока не входит: он идёт
/// через ScreenCaptureKit и требует отдельного разрешения. Это следующий шаг.
enum MicrophoneRecorder {

    enum RecordingError: Error, CustomStringConvertible {
        case permissionDenied
        case engineFailed(String)
        case converterUnavailable
        /// Система без AVFoundation — Linux, а со временем и Windows.
        case unsupportedPlatform

        var description: String {
            switch self {
            case .permissionDenied:
                return """
                Нет доступа к микрофону. macOS спрашивает разрешение один раз, и \
                если его отклонили, включать надо руками:
                Системные настройки → Конфиденциальность и безопасность → Микрофон.
                """
            case .engineFailed(let message):
                return "Не смог запустить запись: \(message)"
            case .converterUnavailable:
                return "Не смог привести звук микрофона к 16 кГц моно."
            case .unsupportedPlatform:
                return """
                Запись с микрофона на этой системе не работает: она сделана на \
                AVFoundation, которого здесь нет.
                Всё остальное работает: запишите звук чем угодно в WAV 16 кГц и \
                отдайте его — `orakul расшифровать звонок.wav "Название"` \
                (с `ORAKUL_ENGINE`) или `orakul добавить расшифровка.txt "Название"`.
                """
            }
        }
    }

    /// Есть ли на этой системе микрофонный тракт вообще.
    ///
    /// Спрашивается ДО того, как человеку сказали «говорите»: на Linux запись
    /// невозможна, и приглашение говорить, за которым сразу идёт отказ, — это
    /// та самая уверенная фраза о том, чего не произошло (план, §4). Найдено
    /// запуском собранной программы в контейнере, а не чтением кода.
#if canImport(AVFoundation)
    public static let isSupported = true
#else
    public static let isSupported = false
#endif

    /// Спросить разрешение и дождаться ответа.
    ///
    /// Там, где AVFoundation нет, спрашивать не у кого: ответ «нет», и `record`
    /// ниже сообщает об этом отдельной ошибкой. Молчаливое `false` здесь
    /// выглядело бы как отказ пользователя в доступе — то есть отправило бы
    /// человека чинить разрешения, которых на этой системе не существует.
#if canImport(AVFoundation)
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .denied, .restricted: return false
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default: return false
        }
    }

    /// Записать с микрофона указанное число секунд.
    ///
    /// Возвращает сэмплы в 16 кГц моно — ровно то, что ждёт движок. Пересчёт
    /// делает системный конвертер: свой ресемплер был бы худшим местом для
    /// самодеятельности.
    static func record(seconds: Double,
                       progress: @escaping (Double) -> Void = { _ in }) async throws -> [Float] {
        guard await requestPermission() else { throw RecordingError.permissionDenied }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Double(WAVFile.sampleRate),
                                         channels: 1,
                                         interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: target) else {
            throw RecordingError.converterUnavailable
        }

        let collected = Collected(limitSeconds: seconds)

        input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { buffer, _ in
            let ratio = target.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: target,
                                                   frameCapacity: capacity) else { return }

            var consumed = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if consumed {
                    status.pointee = .noDataNow
                    return nil
                }
                consumed = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, let channel = converted.floatChannelData?[0] else { return }
            collected.append(Array(UnsafeBufferPointer(start: channel,
                                                       count: Int(converted.frameLength))))
        }

        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw RecordingError.engineFailed(error.localizedDescription)
        }

        // Опрашиваем накопленное, а не спим ровно N секунд: если микрофон молчит
        // по техническим причинам, лучше выйти по времени, чем ждать буферов,
        // которых не будет.
        let deadline = Date().addingTimeInterval(seconds + 2)
        while collected.seconds < seconds && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            progress(collected.seconds)
        }

        engine.stop()
        input.removeTap(onBus: 0)
        return collected.samples
    }

    /// Буфер под замком: обработчик микрофона зовут с аудиопотока.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var accumulator: AudioAccumulator

        init(limitSeconds: Double) {
            accumulator = AudioAccumulator(limitSeconds: limitSeconds)
        }

        func append(_ samples: [Float]) {
            lock.lock(); defer { lock.unlock() }
            accumulator.append(samples)
        }

        var seconds: Double {
            lock.lock(); defer { lock.unlock() }
            return accumulator.seconds
        }

        var samples: [Float] {
            lock.lock(); defer { lock.unlock() }
            return accumulator.samples
        }
    }
#else
    /// Здесь микрофона нет — и это единственное, чего нет. Подписи те же, чтобы
    /// `main.swift` не знал, на какой системе он собран: расходится реализация,
    /// а не устройство программы.
    static func requestPermission() async -> Bool { false }

    /// Бросает, а не возвращает пустой массив. Пустой массив уехал бы в
    /// `WAVFile.encode` и записался бы на диск как файл тишины — «записал»,
    /// когда ничего не записано. Это тот самый класс ошибок, ради которого
    /// заведено правило про уверенные фразы (план, §4).
    static func record(seconds: Double,
                       progress: @escaping (Double) -> Void = { _ in }) async throws -> [Float] {
        throw RecordingError.unsupportedPlatform
    }
#endif
}
