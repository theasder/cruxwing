import Foundation
import Testing
@testable import CruxwingCore

/// Своя таблица CP1251 обязана совпадать с системной там, где системная есть.
///
/// Таблица переписана из спецификации руками, а рукописная таблица на 256
/// строк — это 256 возможностей опечататься, причём каждая опечатка ломает ровно
/// одну букву и незаметна на глаз: «Аня» останется «Аня», а «щ» превратится в
/// «ш» в одном файле из десяти.
///
/// Поэтому проверка не выборочная: сверяются ВСЕ байты, по одному, с
/// `.windowsCP1251` от Foundation. На Linux и Windows системной таблицы нет —
/// там этот набор пропускается с указанной причиной, а остальные ниже работают
/// и без неё.
@Suite("CP1251 против системной таблицы")
struct CP1251EquivalenceTests {

    /// Есть ли системная таблица. Проверяется вызовом, а не `#if os(...)`:
    /// вопрос не в системе, а в том, умеет ли эта Foundation такую кодировку.
    static var systemTable: Bool {
        String(data: Data([0xC0]), encoding: .windowsCP1251) != nil
    }

    /// Пропуск, а не провал: на corelibs сверять не с чем, и красная проверка
    /// сообщала бы о продукте неправду — таблица там как раз работает, просто
    /// системного эталона рядом нет.
    @Test("каждый из 256 байтов читается так же, как системной таблицей",
          .enabled(if: CP1251EquivalenceTests.systemTable,
                   "у этой Foundation нет .windowsCP1251 — сверять не с чем"))
    func everyByteMatchesFoundation() throws {
        var mismatches: [String] = []
        for byte in UInt8.min...UInt8.max {
            let data = Data([byte])
            let system = String(data: data, encoding: .windowsCP1251)
            let ours = CP1251.decode(data)
            // 0x98 в спецификации не определён. Foundation отдаёт на него
            // что-то своё; мы отказываемся — осознанная разница, а не
            // расхождение таблиц.
            if byte == 0x98 {
                #expect(ours == nil, "0x98 не определён в CP1251 и не должен читаться")
                continue
            }
            if system != ours {
                mismatches.append("0x\(String(byte, radix: 16, uppercase: true)): "
                                  + "система \(system.map { String(reflecting: $0) } ?? "nil"), "
                                  + "наша \(ours.map { String(reflecting: $0) } ?? "nil")")
            }
        }
        #expect(mismatches.isEmpty,
                "таблица разошлась с системной:\n\(mismatches.joined(separator: "\n"))")
    }

    @Test("текст переживает оборот в байты и обратно")
    func roundTrip() throws {
        let line = "Аня: тарифы — «прод», ёж, Ъ и Ї\n"
        let bytes = try #require(CP1251.encode(line), "строка не влезла в CP1251")
        #expect(CP1251.decode(bytes) == line)

        // И байты те же, что у системной таблицы, если она есть: иначе файл,
        // записанный нами, у человека на Windows откроется не так.
        if Self.systemTable {
            #expect(bytes == line.data(using: .windowsCP1251))
        }
    }

    @Test("то, чего в кодировке нет, не записывается молча")
    func refusesWhatDoesNotFit() {
        // «ñ» в CP1251 не влезает — кодировка кириллическая. Вернуть данные с
        // потерянным символом значило бы отдать файл, который читается, но
        // говорит другое.
        //
        // Здесь стоял иероглиф, и это ловил сторож случайных иероглифов в
        // русском тексте (`research-doc.test.mjs`). Сторож был прав: в наборе
        // про кириллицу иероглиф выглядит опечаткой, а не примером.
        #expect(CP1251.encode("Аня: mañana") == nil)
    }

    @Test("байт, которого в кодировке нет, делает разбор отказом")
    func undefinedByteIsRefusal() {
        // 0x98 — единственная неопределённая позиция. Файл с ним не CP1251, и
        // честный ответ «не понял», а не строка с подстановкой.
        #expect(CP1251.decode(Data([0xC0, 0x98, 0xED])) == nil)
    }
}
