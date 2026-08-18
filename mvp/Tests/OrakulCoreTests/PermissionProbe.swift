import Foundation
import Testing

/// Действуют ли права доступа для того, кто запустил набор.
///
/// Нужно ровно из-за одного: под root права не работают. `chmod 000` на каталоге
/// не мешает root его прочитать, поэтому проверки «отказ в доступе дошёл до
/// человека» под root не могут ни пройти, ни провалиться осмысленно — у них
/// просто не наступает условие. В контейнере CI по умолчанию именно root, и на
/// Linux эти проверки падали не из-за продукта.
///
/// Условие спрашивается ДЕЙСТВИЕМ, а не `getuid() == 0`: вопрос не в том, кто мы,
/// а в том, останавливают ли нас права. Такой ответ одинаково верен для root, для
/// файловой системы, смонтированной без поддержки прав, и для будущего Windows,
/// где модель прав другая.
enum PermissionProbe {

    /// `true`, если снятые права действительно запрещают чтение.
    ///
    /// Считается один раз: проба стоит нескольких системных вызовов, а ответ в
    /// пределах прогона не меняется.
    static let enforced: Bool = {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orakul-права-\(UUID().uuidString)")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                                   ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o000],
                                                  ofItemAtPath: root.path)
            _ = try FileManager.default.contentsOfDirectory(atPath: root.path)
            return false      // каталог без прав прочитался — значит, права не действуют
        } catch {
            return true       // не пустили: права работают, проверкам есть что проверять
        }
    }()

    /// Причина пропуска — словами. Пропуск без причины через месяц читается как
    /// «эта проверка не нужна».
    ///
    /// Тип `Comment`, а не `String`: `.enabled(if:_:)` принимает комментарий, и
    /// обычная строковая переменная к нему не приводится — приводится только
    /// литерал. Один текст в одном месте важнее удобства объявления.
    static let reason: Comment = """
        права доступа здесь не действуют (root или файловая система без прав): \
        отказ, который проверяет этот тест, наступить не может
        """
}
