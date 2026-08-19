import Foundation

struct ImportedContextFile: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let text: String

    /// Невидимые знаки снимаются ЗДЕСЬ, а не у читателей.
    ///
    /// Через этот тип приезжает расшифровка Fireflies — сервиса, который продаёт
    /// конкурирующий продукт, — и всё, что человек приложил сам. Читателей у
    /// текста больше десятка: `promptContext`, слепые зоны, обзор приложенного.
    /// Чистить у каждого значило бы однажды забыть у одного, поэтому текст,
    /// который нельзя увидеть, в этот тип просто не кладётся.
    init(id: UUID = UUID(), name: String, text: String) {
        self.id = id
        // Имя чистится тоже: переворот направления в имени файла — старый приём,
        // из-за которого «отчёт.txt» показывается человеку не тем, чем является.
        self.name = InvisibleText.strip(name)
        self.text = InvisibleText.strip(text)
    }

    /// Разбор сохранённой сессии идёт мимо `init` выше.
    ///
    /// Codable синтезирует свой разбор и кладёт поля напрямую — сохранённая
    /// сессия вернула бы невидимые знаки обратно в запрос, и чистка на входе
    /// оказалась бы верной ровно до первого перезапуска. Поэтому разбор зовёт
    /// тот же путь.
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try box.decode(UUID.self, forKey: .id),
                  name: try box.decode(String.self, forKey: .name),
                  text: try box.decode(String.self, forKey: .text))
    }

    var charCount: Int { text.count }
}
