import Testing
import Foundation
@testable import OrakulCore

/// Чем мы представляемся чужому сервису.
///
/// Без явного заголовка систему собирает его сама — из ИМЕНИ ИСПОЛНЯЕМОГО
/// ФАЙЛА. У собранного приложения это «MeetGPT»: внутреннее имя цели, которого
/// нет ни на странице, ни в интерфейсе, — а продукт называется orakul.
/// Измерено 2026-08-21 на своём сервере, записавшем настоящий запрос:
/// «MeetGPT/… CFNetwork/… Darwin/24.6.0».
///
/// Видел это каждый подключённый сервис, включая сервис конкурента.
@Suite struct HowWeIntroduceOurselvesTests {

    @Test("представляемся публичным именем продукта")
    func introducesItselfByThePublicName() {
        let agent = ConnectorSession.userAgent
        #expect(agent.hasPrefix("orakul/"), "чужой сервис видит не то имя: \(agent)")
        #expect(!agent.contains("MeetGPT"), "внутреннее имя цели уезжает наружу: \(agent)")
    }

    @Test("версия системы чужому серверу не сообщается")
    func saysNothingAboutTheMachine() {
        // Назвать себя — вежливость и требование части API. Перечислять версию
        // macOS постороннему — нет: это отпечаток машины, а не представление.
        let agent = ConnectorSession.userAgent
        #expect(!agent.contains("Darwin"))
        #expect(!agent.contains("CFNetwork"))
        #expect(!agent.contains("Mac OS"))
    }

    @Test("заголовок стоит на общей сессии, а не у отдельного коннектора")
    func theHeaderLivesOnTheSharedSession() {
        // Одна дверь в сеть — одно представление. Расставленный по коннекторам
        // заголовок отличался бы у того, кого забыли.
        let header = ConnectorSession.session.configuration
            .httpAdditionalHeaders?["User-Agent"] as? String
        #expect(header == ConnectorSession.userAgent,
                "общая сессия представляется иначе: \(header ?? "—")")
    }
}
