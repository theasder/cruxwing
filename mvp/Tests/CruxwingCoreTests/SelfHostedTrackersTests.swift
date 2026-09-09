import Foundation
// URLRequest и HTTPURLResponse на Linux живут в FoundationNetworking — том же
// модуле, что и в ядре. Без этого набор не собирается там, где он и должен
// доказывать переносимость.
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CruxwingCore

/// Открытые трекеры, поднятые командой у себя.
///
/// Форма запросов сверена с документацией 2026-08-12. Закреплена здесь, потому
/// что две детали по тексту ошибки не восстановить: GitLab ждёт токен в
/// заголовке `PRIVATE-TOKEN`, а Gitea — со словом `token`, а не `Bearer`. И то
/// и другое при ошибке даёт 401, одинаковый на вид.
@Suite("Открытые трекеры на своём сервере")
struct SelfHostedTrackersTests {

    private func stub(status: Int = 200, json: String)
        -> (SelfHostedTrackers.HTTP, Recorder) {
        let recorder = Recorder()
        let http: SelfHostedTrackers.HTTP = { request in
            recorder.record(request)
            return (Data(json.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: [:])!)
        }
        return (http, recorder)
    }

    private static let gitlabJSON = """
    [{"iid": 42, "title": "Поднять лимиты на выгрузку", "state": "opened"}]
    """
    private static let giteaJSON = """
    [{"number": 7, "title": "Починить офлайн-синхронизацию", "state": "closed"}]
    """

    @Test("GitLab ищет задачи и шлёт PRIVATE-TOKEN")
    func gitlabSearch() async throws {
        let (http, recorder) = stub(json: Self.gitlabJSON)
        let items = try await SelfHostedTrackers(service: .gitlab, token: "tok-synthetic",
                                                 host: "gitlab.company.ru",
                                                 http: http).search("лимиты")

        let request = try #require(recorder.last)
        let url = try #require(request.url?.absoluteString)
        #expect(url.hasPrefix("https://gitlab.company.ru/api/v4/search"))
        #expect(url.contains("scope=issues"))
        #expect(request.value(forHTTPHeaderField: "PRIVATE-TOKEN") == "tok-synthetic")
        #expect(items.first?.key == "#42")
        #expect(items.first?.state == "opened")
    }

    @Test("Gitea ищет задачи и шлёт «token», а не «Bearer»")
    func giteaSearch() async throws {
        let (http, recorder) = stub(json: Self.giteaJSON)
        let items = try await SelfHostedTrackers(service: .gitea, token: "tok-synthetic",
                                                 host: "git.company.ru",
                                                 http: http).search("синхронизация")

        let request = try #require(recorder.last)
        let url = try #require(request.url?.absoluteString)
        #expect(url.hasPrefix("https://git.company.ru/api/v1/repos/issues/search"))
        // Без `type=issues` в выдачу попадают пулл-реквесты.
        #expect(url.contains("type=issues"))
        // Historical: именно слово «token». С «Bearer» сервис отвечает 401.
        #expect(request.value(forHTTPHeaderField: "Authorization") == "token tok-synthetic")
        #expect(items.first?.key == "#7")
        // Закрытая задача меняет смысл находки на противоположный.
        #expect(items.first?.state == "closed")
    }

    @Test("Redmine ищет только задачи и разворачивает results")
    func redmineSearch() async throws {
        // Единственный из трёх, кто оборачивает выдачу в объект. Массив здесь
        // не придёт, и разбор «как у всех» вернул бы пустоту.
        let json = """
        {"results": [{"id": 314, "title": "Задача #314: поднять лимиты",
                      "type": "issue"}], "total_count": 1}
        """
        let (http, recorder) = stub(json: json)
        let items = try await SelfHostedTrackers(service: .redmine, token: "tok-synthetic",
                                                 host: "redmine.company.ru",
                                                 http: http).search("лимиты")

        let request = try #require(recorder.last)
        let url = try #require(request.url?.absoluteString)
        #expect(url.hasPrefix("https://redmine.company.ru/search.json"))
        // Без этого Redmine ищет ещё по вики, форуму и новостям.
        #expect(url.contains("issues=1"))
        #expect(request.value(forHTTPHeaderField: "X-Redmine-API-Key") == "tok-synthetic")
        #expect(items.first?.key == "#314")
    }

    /// Слово, которое ищет человек, обязано уехать в ТОТ параметр, что описан в
    /// документации вендора.
    ///
    /// Дыра найдена мутацией 2026-08-18: в манифесте Gitea имя параметра
    /// заменили с `q` на `qq` — запрос ушёл другим, и ни одна проверка не
    /// упала. Набор сверял начало адреса, `type=issues` и заголовок, а имя
    /// параметра поиска — то единственное, ради чего коннектор существует, — не
    /// проверял никто. Сервис на такой запрос отвечает либо всей лентой задач,
    /// либо пустотой, и то и другое выглядит как исправный поиск.
    @Test("слово ищется тем параметром, который описан у вендора",
          arguments: [(SelfHostedTrackers.Service.gitea, "q"),
                      (SelfHostedTrackers.Service.gitlab, "search"),
                      (SelfHostedTrackers.Service.redmine, "q")])
    func searchTermTravelsInDocumentedParameter(service: SelfHostedTrackers.Service,
                                                parameter: String) async throws {
        let (http, recorder) = stub(json: "[]")
        _ = try? await SelfHostedTrackers(service: service, token: "tok-synthetic",
                                          host: "git.company.ru",
                                          http: http).search("синхронизация")

        // Первый запрос, а не последний: на пустой выдаче коннектор спрашивает ещё
        // раз тем же словом с заглавной буквы — у Redmine и Nextcloud с базой по
        // умолчанию «тарифы» не находит «Тарифы». Здесь проверяется, КУДА уезжает
        // слово человека, а это первый запрос.
        let request = try #require(recorder.first)
        let url = try #require(request.url)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == parameter }?.value == "синхронизация",
                "у «\(service.rawValue)» слово ушло не в «\(parameter)»: \(items)")
    }

    @Test("адрес без схемы дополняется https")
    func hostGetsScheme() async throws {
        let (http, recorder) = stub(json: Self.gitlabJSON)
        _ = try await SelfHostedTrackers(service: .gitlab, token: "t",
                                         host: "gitlab.company.ru", http: http).search("q")
        #expect(recorder.last?.url?.scheme == "https")
    }

    @Test("без токена или без адреса запрос не уходит",
          arguments: SelfHostedTrackers.Service.allCases)
    func incompleteSetupNeverCallsOut(service: SelfHostedTrackers.Service) async {
        let (http, recorder) = stub(json: "[]")
        await #expect(throws: SelfHostedTrackers.ConnectorError.notConfigured) {
            try await SelfHostedTrackers(service: service, token: "",
                                         host: "git.company.ru", http: http).search("q")
        }
        await #expect(throws: SelfHostedTrackers.ConnectorError.notConfigured) {
            try await SelfHostedTrackers(service: service, token: "t",
                                         host: nil, http: http).search("q")
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
        for (status, expected) in [(401, SelfHostedTrackers.ConnectorError.unauthorised),
                                   (403, SelfHostedTrackers.ConnectorError.forbidden)] {
            let (http, _) = stub(status: status, json: "[]")
            await #expect(throws: expected) {
                try await SelfHostedTrackers(service: .gitlab, token: "t",
                                             host: "gitlab.company.ru",
                                             http: http).search("q")
            }
        }
    }

    @Test("ошибка сервиса не выдаётся за пустую выдачу")
    func errorBodyIsNotAnEmptyResult() async {
        // Оба отдают массив. Объект — это тело ошибки, и пустой список сказал
        // бы «не заводили» там, где мы просто не смогли спросить.
        let (http, _) = stub(json: #"{"message": "401 Unauthorized"}"#)
        await #expect(throws: SelfHostedTrackers.ConnectorError.unreadable) {
            try await SelfHostedTrackers(service: .gitlab, token: "t",
                                         host: "gitlab.company.ru", http: http).search("q")
        }
    }
    @Test("every prompt is written for a person, in the product's language")
    func promptsAreWrittenForPeople() {
        for service in SelfHostedTrackers.Service.allCases {
            #expect(!service.credentialHint.isEmpty)
            #expect(!service.hostPrompt.isEmpty)
            #expect(service.credentialHint.range(
                of: "[а-яА-ЯёЁ]", options: .regularExpression) == nil,
                    "a Russian hint outlived the switch to English: \(service)")
            #expect(service.hostPrompt.range(
                of: "[а-яА-ЯёЁ]", options: .regularExpression) == nil,
                    "a Russian prompt outlived the switch to English: \(service)")
        }
    }
}


@Suite("Адрес сервера: где путь срезается, а где нет")
struct HostNormalisationPolicyTests {
    /// Три сервиса ведут себя по-разному, и это решение, а не случайность.
    ///
    /// У Kaiten путь срезается: подсказка ведёт человека на доску, он копирует
    /// адрес доски из строки браузера, и `.../boards/5` + `/api/latest` дало бы
    /// 404, который нечем объяснить. Так и было — об этом стоит комментарий в
    /// коде.
    ///
    /// У поднятых у себя GitLab, Gitea, Redmine и у мессенджеров путь
    /// сохраняется: их можно поставить в подкаталог (`company.ru/gitlab`), и
    /// срезание сломало бы рабочую настройку ради предполагаемой ошибки,
    /// которой мы не наблюдали. Подсказка у них просит адрес сервера, а не
    /// адрес страницы.
    ///
    /// Проверка существует, чтобы разница осталась осознанной: если кто-то
    /// решит выровнять поведение, он увидит здесь, что именно теряет.
    @Test("Kaiten срезает путь, потому что туда ведёт подсказка")
    func kaitenStripsPath() {
        let host = RussianTrackers.Service.kaiten.host(secondary: "https://team.kaiten.ru/boards/5")
        #expect(host == "https://team.kaiten.ru/api/latest")
    }

    @Test("свои серверы путь сохраняют — их ставят в подкаталог",
          arguments: [SelfHostedTrackers.Service.gitlab, .gitea, .redmine])
    func selfHostedKeepsSubpath(service: SelfHostedTrackers.Service) {
        let host = service.host("https://company.ru/gitlab")
        #expect(host == "https://company.ru/gitlab",
                "путь срезан — установка в подкаталоге перестанет работать")
    }

    @Test("схема дописывается, если её не вписали")
    func schemeIsAdded() {
        #expect(SelfHostedTrackers.Service.gitlab.host("gitlab.company.ru")
                == "https://gitlab.company.ru")
        #expect(SelfHostedTrackers.Service.gitlab.host("  ") == nil)
    }
}
