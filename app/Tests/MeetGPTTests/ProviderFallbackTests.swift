import Foundation
import Testing
@testable import MeetGPT

/// Запасной провайдер, когда у первого отказал ключ.
///
/// Это и есть устойчивость к одному поставщику: ключ отозвали, тариф сменили,
/// сервис лёг — продукт обязан продолжить на другом. Зависимость от одного
/// вендора — рычаг, которым пользуются.
///
/// До 2026-08-21 живой отбор `providerFallbackModels` не был покрыт НИЧЕМ, а
/// покрыт был `authFallbackModel` — однострочная обёртка над ним, которую не
/// звал никто, кроме набора. Хуже того, её проверка перебирала тарифы с
/// `guard … else { continue }`: на машине без настроенных провайдеров пул пуст,
/// и ни одно утверждение не выполнялось ни разу.
///
/// Поэтому здесь настроенность ПОДСТАВЛЯЕТСЯ, а не читается с машины: проверка
/// обязана работать одинаково у всех и не имеет права тихо пропустить себя.
@Suite struct ProviderFallbackTests {

    static func fallbacks(excluding provider: LLMProvider,
                          tier: Tier = .premium,
                          hasImages: Bool = false,
                          configured: Set<LLMProvider> = Set(LLMProvider.allCases)) -> [LLMModel] {
        AutoOrchestrator.providerFallbackModels(
            excluding: provider, tier: tier, hasImages: hasImages,
            isConfigured: { configured.contains($0) })
    }

    @Test("запасной — всегда другой провайдер")
    func neverTheSameProvider() {
        for provider in LLMProvider.allCases {
            let models = Self.fallbacks(excluding: provider)
            #expect(!models.isEmpty, "\(provider.rawValue): запасных нет вовсе")
            #expect(models.allSatisfy { $0.provider != provider },
                    "\(provider.rawValue) предложен сам себе")
        }
    }

    @Test("ненастроенный провайдер в запасные не попадает")
    func onlyConfiguredProviders() {
        // Ключа нет — обращение к нему станет вторым отказом подряд, и человек
        // увидит два сбоя вместо одного.
        let allowed: Set<LLMProvider> = [.openAI]
        let models = Self.fallbacks(excluding: .anthropic, configured: allowed)
        #expect(!models.isEmpty)
        #expect(models.allSatisfy { allowed.contains($0.provider) })
    }

    @Test("запасной разрешён тарифом, на котором человек сидит")
    func staysWithinTheTier() {
        for tier in Tier.allCases {
            for model in Self.fallbacks(excluding: .anthropic, tier: tier) {
                #expect(model.isAvailable(for: tier),
                        "\(model.id) предложен на тарифе \(tier), где он недоступен")
            }
        }
    }

    @Test("для запроса с картинками предлагают только зрячие модели")
    func imagesNarrowTheChoice() {
        let models = Self.fallbacks(excluding: .anthropic, hasImages: true)
        #expect(!models.isEmpty, "с картинками не осталось ни одного запасного")
        #expect(models.allSatisfy { $0.supportsVision })
    }

    @Test("от каждого провайдера — одна модель, сильные первыми")
    func oneModelPerProviderStrongestFirst() {
        // Список строится из МНОЖЕСТВА провайдеров, порядок обхода которого не
        // определён, — поэтому сортировка здесь не украшение: без неё два
        // одинаковых отказа чинились бы разными моделями.
        let models = Self.fallbacks(excluding: .anthropic)
        #expect(models.count >= 3, "запасных слишком мало, чтобы проверять порядок")
        let ranks = models.map { LLMCatalog.rank(of: $0) }
        #expect(ranks == ranks.sorted(), "запасные идут не по силе: \(ranks)")
        let providers = models.map(\.provider)
        #expect(Set(providers).count == providers.count, "один провайдер предложен дважды")

        // Про доупорядочивание по имени провайдера при РАВНОМ ранге проверки
        // здесь нет, и это сказано вслух: в сегодняшнем каталоге равных рангов
        // нет вовсе (измерено), поэтому та ветка не может сработать, а
        // утверждение о ней было бы утверждением ни о чём. Появятся равные —
        // появится и проверка.
        #expect(Set(ranks).count == ranks.count,
                "в каталоге появились равные ранги — пора проверить и доупорядочивание")
    }

    @Test("никого не настроено — запасных нет, и это не сбой")
    func noConfiguredProvidersMeansNoFallback() {
        #expect(Self.fallbacks(excluding: .anthropic, configured: []).isEmpty)
    }
}
