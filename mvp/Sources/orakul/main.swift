import Foundation
import OrakulCore

// Тонкая оболочка: вся логика и все тексты живут в OrakulCore, потому что здесь
// их нельзя проверить тестом. Исключение одно — запись с микрофона: её нельзя
// проверить тестом в принципе, поэтому она тоже здесь, и её видно.

let home = ProcessInfo.processInfo.environment["ORAKUL_HOME"]
    ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".orakul").path
let store = SessionStore(root: URL(fileURLWithPath: home))
let arguments = Array(CommandLine.arguments.dropFirst())

/// Запись с микрофона: единственная команда, которой нужен настоящий компьютер.
func recordFromMicrophone(_ rest: [String]) async -> CommandLineApp.Result {
    let seconds = Double(rest.first ?? "") ?? 15
    let title = rest.dropFirst().joined(separator: " ")

    // Сначала проверка, потом приглашение говорить. Обратный порядок звучал
    // как «Записываю 5 с. Говорите…», а следом — «записи на этой системе нет».
    guard MicrophoneRecorder.isSupported else {
        return .init(output: MicrophoneRecorder.RecordingError.unsupportedPlatform.description,
                     exitCode: 1)
    }

    FileHandle.standardError.write(Data("Recording \(Int(seconds))s. Speak…\n".utf8))
    do {
        let samples = try await MicrophoneRecorder.record(seconds: seconds) { done in
            FileHandle.standardError.write(Data("\r\(String(format: "%.0f", done))s".utf8))
        }
        FileHandle.standardError.write(Data("\n".utf8))

        var buffer = AudioAccumulator()
        buffer.append(samples)

        guard buffer.isWorthTranscribing else {
            // Отличить «тишину» от «слишком коротко» важно: причины разные и
            // чинятся по-разному. К тишине обязательно число: вердикт без
            // уровня неотличим от сломанного преобразования, и разбираться
            // пришлось бы вслепую — ровно так и выяснилось, что прежний порог
            // был ниже фона обычной комнаты.
            let reason: String
            if buffer.looksSilent {
                reason = String(format: "Silence: level %.5f against a threshold of %.3f. "
                                + "The wrong microphone is probably selected, or it is switched off.",
                                buffer.level, AudioAccumulator.silenceThreshold)
            } else {
                reason = String(format: "Too short — %.1fs recorded.", buffer.seconds)
            }
            return CommandLineApp.Result(output: reason, exitCode: 1)
        }

        // Сохраняем запись рядом, чтобы её можно было расшифровать и потом:
        // потерять созвон из-за ненастроенного движка было бы обидно.
        let wav = URL(fileURLWithPath: home)
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent("\(UUID().uuidString).wav")
        try FileManager.default.createDirectory(at: wav.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try WAVFile.encode(samples: buffer.samples).write(to: wav)

        return CommandLineApp.Result(output: """
        Recorded \(String(format: "%.1f", buffer.seconds))s → \(wav.path)
        Next: orakul transcribe \(wav.path) "\(title.isEmpty ? "Call" : title)"
        """, exitCode: 0)
    } catch {
        return CommandLineApp.Result(output: "\(error)", exitCode: 1)
    }
}

let result: CommandLineApp.Result
switch arguments.first {
case "записать", "record":
    result = await recordFromMicrophone(Array(arguments.dropFirst()))
case "корпус", "corpus":
    // Проверка корпуса речи перед замером (роадмап, §6.3). Правила те же, что
    // у самого замера: второй набор правил разошёлся бы с первым, и слово
    // «проверено» перестало бы что-то значить.
    let rest = Array(arguments.dropFirst())
    if let directory = rest.first {
        do {
            let corpus = try SpeechCorpus.load(directory: directory)
            var lines = ["Corpus: \(corpus.items.count) recordings"]
            for (genre, count) in corpus.countsByGenre.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                lines.append("  \(genre.rawValue): \(count)")
            }
            lines.append("  with a human transcript: \(corpus.withReference.count)")
            // Предупреждение, а не ошибка: корпус из одних докладов — рабочий
            // корпус, просто отвечает он на другой вопрос.
            if corpus.countsByGenre[.call] == nil {
                lines.append("!! no calls: a measurement over this corpus speaks about talks,"
                             + " and the product's promise is about calls")
            }
            result = CommandLineApp.Result(output: lines.joined(separator: "\n"), exitCode: 0)
        } catch {
            result = CommandLineApp.Result(
                output: (error as? SpeechCorpus.CorpusError)?.description
                    ?? error.localizedDescription,
                exitCode: 1)
        }
    } else {
        result = CommandLineApp.Result(
            output: "Usage: orakul corpus <folder>. The description is corpus.json inside it.",
            exitCode: 2)
    }
case "спросить", "ask":
    // Логика — в ядре и покрыта тестами; здесь только окружение и настоящий HTTP.
    let rest = Array(arguments.dropFirst())
    let environment = ProcessInfo.processInfo.environment
    if rest.count < 2 {
        result = CommandLineApp.Result(
            output: "Usage: orakul ask <service> <question>.\n"
                + "Services: " + ConnectorQuery.services.joined(separator: ", ") + ".",
            exitCode: 2)
    } else {
        // Поля, которые у сервиса свои: `ORAKUL_FIELD_workspace=…`. Имена не
        // перечислены здесь намеренно — их знает манифест, а список в двух
        // местах разъезжается ровно тогда, когда добавляют третий сервис.
        let fields = environment.reduce(into: [String: String]()) { result, pair in
            guard pair.key.hasPrefix("ORAKUL_FIELD_") else { return }
            result[String(pair.key.dropFirst("ORAKUL_FIELD_".count))] = pair.value
        }
        let settings = ConnectorQuery.Settings(
            service: rest[0],
            token: environment["ORAKUL_TOKEN"] ?? "",
            host: environment["ORAKUL_HOST"],
            scope: environment["ORAKUL_SCOPE"],
            values: fields)
        let answer = await ConnectorQuery.ask(settings,
                                              query: rest.dropFirst().joined(separator: " "))
        // Код возврата — не украшение: `orakul спросить … && развернуть`
        // продолжал работу после «нет токена», потому что здесь всегда стоял
        // ноль. Пустая выдача сбоем не считается — это ответ.
        result = CommandLineApp.Result(output: answer.text, exitCode: answer.failed ? 1 : 0)
    }
default:
    result = CommandLineApp(store: store).run(arguments)
}

// Ошибки — в stderr, чтобы `orakul найти ... > файл` не смешивал ответ с
// жалобой на аргументы.
if result.exitCode == 0 {
    print(result.output)
} else {
    FileHandle.standardError.write(Data((result.output + "\n").utf8))
}
exit(result.exitCode)
