// swift-tools-version:5.9
import PackageDescription

// orakul — сборка, отдельная от Cruxwing.
//
// Ядро (OrakulCore) не знает ни про SwiftUI, ни про CoreML, ни про
// ScreenCaptureKit: там разбор каталога кнопок, правила уровней и всё, что
// должно одинаково работать и на macOS, и на Windows. Платформенные слои —
// захват звука и оболочка — лежат снаружи и заменяются целиком.
//
// Такое разделение не вкусовщина: порт на Windows стоит ровно тех модулей,
// которые находятся вне OrakulCore, и это видно прямо из манифеста.
// Окно — единственная часть пакета, которой нужен SwiftUI, то есть Apple.
// Объявлено условно, а не «пока не трогаем»: на Linux манифест с этой целью
// разваливает сборку ЦЕЛИКОМ, вместе с ядром и командной строкой, которым
// SwiftUI не нужен. Условие вычисляется на машине, где идёт сборка.
//
// Ядра это не касается: `PortabilityTests` и без того держит его на одном
// `Foundation`, и это по-прежнему то, ради чего разделение существует.
#if os(macOS)
let windowProducts: [Product] = [.executable(name: "OrakulApp", targets: ["OrakulApp"])]
let windowTargets: [Target] = [.executableTarget(name: "OrakulApp", dependencies: ["OrakulCore"])]
#else
let windowProducts: [Product] = []
let windowTargets: [Target] = []
#endif

let package = Package(
    name: "Orakul",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OrakulCore", targets: ["OrakulCore"]),
        // Программа, которую можно запустить сегодня: захвата звука ещё нет, но
        // всё, что происходит со звонком после расшифровки, уже работает.
        .executable(name: "orakul", targets: ["orakul"])
        // Окно. Собирается в бандл скриптом scripts/bundle.sh: SwiftPM умеет
        // исполняемый файл, но не .app. Объявлено выше, условно.
    ] + windowProducts,
    targets: [
        .target(
            name: "OrakulCore",
            resources: [
                // Каталог кнопок — данные, а не код: его правит тот, кто пишет
                // тексты, и его же проверяют тесты на стороне сайта.
                .copy("Resources/prompts.ru.json"),
                // Коннекторы, описанные данными. Здесь по той же причине: их
                // правит тот, у кого есть аккаунт в сервисе, а не тот, у кого
                // есть Mac. Разбор и проверки — `ConnectorManifest`.
                .copy("Resources/connectors"),
                // Словарь — тоже данные. Его правит тот, у кого на звонках
                // слышится «промт» вместо «промпт», а не тот, у кого есть Mac.
                .copy("Resources/lexicon")
            ]
        ),
        // Оболочка без логики: разбор аргументов и тексты — в ядре, где их
        // покрывают тесты.
        .executableTarget(name: "orakul", dependencies: ["OrakulCore"]),
        .testTarget(name: "OrakulCoreTests", dependencies: ["OrakulCore"])
    ] + windowTargets
)
