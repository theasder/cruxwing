import Testing
import Foundation
@testable import MeetGPT
import CruxwingCore

/// Молчащий источник оставляет след.
///
/// `withMCPDeadline` отдаёт `nil` и когда сервис отказал, и когда он просто не
/// ответил вовремя, — а веер в обоих случаях молча выбрасывает источник. Для
/// человека это разные вещи: отказ он прочтёт в настройках («право не выдано»,
/// «токен отозван»), а зависший сервис не оставлял следа НИГДЕ и просто
/// пропадал из каждой подсказки. Выглядит это как продукт, который перестал
/// находить, — и это рычаг чужой стороны: тянуть с ответом дешевле, чем
/// отказывать.
@Suite struct SilentSourceTests {

    @Test("молчание записывается и называет срок")
    func timeoutIsRecorded() async {
        let health = ConnectorHealth()
        await health.recordTimeout(service: "linear", seconds: 8)
        let refusal = await health.refusal(for: "linear")
        #expect(refusal?.words.contains("did not answer within") == true, "молчание не записано")
        #expect(refusal?.words.contains("8") == true, "срок не назван: \(refusal?.words ?? "—")")
    }

    @Test("слова сервиса сильнее нашего описания молчания")
    func spokenRefusalIsNotOverwrittenBySilence() async {
        // Порядок в жизни бывает такой: сервис отказал словами, а следующий
        // вопрос к нему просто не дошёл. «Не ответил за 8 с» на месте
        // «invalid_token — Token revoked» отправит человека чинить сеть вместо
        // токена. Наше описание молчания — беднее, чем слова сервиса.
        let health = ConnectorHealth()
        // Ошибка с русским описанием, как у настоящих коннекторов: NSError
        // Swift не считает LocalizedError, и запись сохранила бы его целиком
        // вместе с доменом и кодом — проверка тогда сравнивала бы не то.
        struct Spoken: LocalizedError {
            var errorDescription: String? { "invalid_token — Token revoked" }
        }
        await health.record(service: "weeek", error: Spoken())
        await health.recordTimeout(service: "weeek", seconds: 8)
        let refusal = await health.refusal(for: "weeek")
        #expect(refusal?.words == "invalid_token — Token revoked",
                "слова сервиса затёрты описанием молчания: \(refusal?.words ?? "—")")
    }

    @Test("успех очищает и молчание тоже")
    func successClearsSilence() async {
        // Иначе однажды зависший сервис навсегда остался бы с ярлыком
        // «не ответил», хотя отвечает уже неделю.
        let health = ConnectorHealth()
        await health.recordTimeout(service: "trello", seconds: 8)
        await health.recordSuccess(service: "trello")
        #expect(await health.refusal(for: "trello") == nil)
    }

    @Test("веер записывает молчание во всех пяти семействах")
    func everyBranchRecordsSilence() throws {
        // Структурно: поднять пять зависших сервисов ради одного `nil` дороже,
        // чем польза. Правило простое — где записан отказ, там записано и
        // молчание: обе ветки ведут к одному `nil`, и пропустить одну значит
        // вернуть тишину ровно для того семейства, о котором забыли.
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/MeetGPT/MCP/MCPGrounding.swift"), encoding: .utf8)
        let refusals = source.components(separatedBy: "ConnectorHealth.shared.record(service:").count - 1
        let silences = source.components(separatedBy: "recordTimeout(").count - 1
        #expect(refusals >= 5, "веток с записью отказа нашлось \(refusals) — проверка смотрит не туда")
        #expect(silences == refusals,
                "отказ записан в \(refusals) ветках, молчание — в \(silences)")
    }
}
