import Foundation
// URLRequest и HTTPURLResponse на Linux живут в FoundationNetworking — том же
// модуле, что и в ядре. Без этого набор не собирается там, где он и должен
// доказывать переносимость.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import OrakulCore

/// Поиск по базе знаний.
///
/// Раздел заметок в `RESEARCH-AND-PLAN` §2.1 был закрыт как невозможный — и это
/// по-прежнему верно для российских облаков: у Яндекс Вики нет поиска по
/// тексту, у Teamly нет публичного API. Но открытые вики, которые команда
/// поднимает у себя, поиск отдают, и здесь закреплена его форма.
@Suite("База знаний")
struct TeamNotesTests {

    private func stub(status: Int = 200, json: String) -> (TeamNotes.HTTP, Recorder) {
        let recorder = Recorder()
        let http: TeamNotes.HTTP = { request in
            recorder.record(request)
            return (Data(json.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: [:])!)
        }
        return (http, recorder)
    }

    private static let outlineJSON = """
    {"data": [{"context": "…решили поднять месячный на пятнадцать процентов…",
               "document": {"id": "d1", "title": "Тарифы 2026"}}]}
    """

    @Test("Outline ищет POST-ом и берёт токен в Bearer")
    func outlineSearch() async throws {
        let (http, recorder) = stub(json: Self.outlineJSON)
        let hits = try await TeamNotes(service: .outline, token: "tok-synthetic",
                                       host: "wiki.company.ru", http: http).search("тарифы")

        // Первый запрос: к незнакомому сервису первый кириллический вопрос задаётся
        // дважды, чтобы узнать, сравнивает ли он байты. Слово человека уносит первый.
        let request = try #require(recorder.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://wiki.company.ru/api/documents.search")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-synthetic")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["query"] as? String == "тарифы")

        // В подсказку идут слова вокруг совпадения, а не ссылка: ссылку на
        // звонке никто не откроет.
        #expect(hits.first?.title == "Тарифы 2026")
        #expect(hits.first?.context.contains("пятнадцать процентов") == true)
    }

    @Test("без адреса используется облако сервиса, а не ошибка")
    func emptyHostMeansCloud() async throws {
        // Отличие от GitLab и Gitea: там адрес обязателен, здесь нет. Outline
        // бывает облачным, и требовать адрес значило бы не пустить половину.
        let (http, recorder) = stub(json: Self.outlineJSON)
        _ = try await TeamNotes(service: .outline, token: "tok",
                                host: nil, http: http).search("q")
        #expect(recorder.last?.url?.absoluteString
                == "https://app.getoutline.com/api/documents.search")
    }

    @Test("без токена запрос не уходит")
    func tokenIsRequired() async {
        let (http, recorder) = stub(json: "{}")
        await #expect(throws: TeamNotes.ConnectorError.notConfigured) {
            try await TeamNotes(service: .outline, token: "  ",
                                host: "wiki.company.ru", http: http).search("q")
        }
        #expect(recorder.count == 0)
    }

    @Test("401 и 403 читаются как неподходящий токен")
    func unauthorisedIsRecognised() async {
        // 403 отделён от 401 (2026-08-19). Прежде здесь стояло ожидание
        // одного и того же ответа на оба кода, и оно закрепляло дефект:
        // движок их различает намеренно, а обёртка сводила обратно.
        // «Токен не принят» отправляет выпускать новый, «нет права» —
        // выдавать право; совет не тот, и человек потратит вечер.
        for (status, expected) in [(401, TeamNotes.ConnectorError.unauthorised),
                                   (403, TeamNotes.ConnectorError.forbidden)] {
            let (http, _) = stub(status: status, json: "{}")
            await #expect(throws: expected) {
                try await TeamNotes(service: .outline, token: "t",
                                    host: nil, http: http).search("q")
            }
        }
    }

    @Test("ошибка сервиса не выдаётся за пустую выдачу")
    func errorBodyIsNotAnEmptyResult() async {
        // Пустой список сказал бы «не описывали», и человек бы поверил.
        let (http, _) = stub(json: #"{"error": "authentication_required"}"#)
        await #expect(throws: TeamNotes.ConnectorError.unreadable) {
            try await TeamNotes(service: .outline, token: "t", host: nil, http: http).search("q")
        }
    }

    @Test("пустой запрос никуда не уходит")
    func blankQueryIsNotSent() async throws {
        let (http, recorder) = stub(json: Self.outlineJSON)
        let hits = try await TeamNotes(service: .outline, token: "t",
                                       host: nil, http: http).search("   ")
        #expect(hits.isEmpty)
        #expect(recorder.count == 0)
    }
    @Test("every credential hint is written in the product's language")
    func promptIsWrittenForPeople() {
        for service in TeamNotes.Service.allCases {
            #expect(!service.credentialHint.isEmpty)
            #expect(service.credentialHint.range(
                of: "[а-яА-ЯёЁ]", options: .regularExpression) == nil,
                    "a Russian hint outlived the switch to English: \(service)")
        }
    }

    /// Тексты отказов не были покрыты ничем — и в них жила ошибка, которую
    /// видел каждый, кто подключал заметки: «База знаний не подключён»,
    /// «не принял токен», «ответил ошибкой». Название женского рода, глаголы
    /// мужского. У остальных коннекторов подлежащее мужского рода («Трекер»,
    /// «Мессенджер», «GitHub»), поэтому там та же заготовка читается верно —
    /// отсюда и ошибка при переносе.
    @Test("отказ написан по-русски и согласован с «базой знаний»")
    func errorsAgreeInGender() throws {
        let cases: [(TeamNotes.ConnectorError, String)] = [
            (.notConfigured, "is not connected"),
            (.unauthorised, "rejected the token"),
            (.http(500), "answered with error 500"),
            (.unreadable, "answered in a way we could not read"),
        ]
        for (error, expected) in cases {
            let text = try #require(error.errorDescription)
            #expect(text.hasPrefix("The knowledge base "), "the service is not named: \(text)")
            #expect(text.contains(expected), "в «\(text)» нет «\(expected)»")
        }
    }

    @Test("название и подсказка адреса есть у каждого сервиса заметок",
          arguments: TeamNotes.Service.allCases)
    func serviceStrings(service: TeamNotes.Service) {
        #expect(!service.title.isEmpty)
        #expect(service.hostPrompt.lowercased().contains("address"),
                "the prompt does not say what to type: \(service.hostPrompt)")
    }
}
