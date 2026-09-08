# Выпуск Orakul

Этот документ описывает новый выпуск исходников из `main` и двух macOS DMG.
Он не объявляет текущий выпуск готовым. На 25 августа 2026 года
`github.com/theasder/orakul` перенаправляет в другой репозиторий, публичная
страница отвечает 404, а исторический `v0.1.0` не проходит проверки этой ветки.
Пока владелец не восстановит идентичность репозитория, workflow выпуска
намеренно откажется работать.

## Что автоматизировано — и что нет

`.github/workflows/release-candidate.yml` запускается вручную для уже
существующего аннотированного тега `vX.Y.Z`. Он:

1. проверяет, что выполняется именно в `theasder/orakul`;
2. сверяет тег с `CFBundleShortVersionString`, требует чистый checkout и
   принадлежность коммита истории `origin/main`, затем запускает
   `node scripts/scan-history-secrets.mjs` по всем достижимым Git-объектам и
   текущим входам;
3. заново запускает три обычных набора тестов на точном коммите тега;
4. из выданных владельцем Apple credentials собирает, подписывает и
   нотаризует arm64 и x86_64;
5. проверяет оба DMG через `scripts/audit-dmg.sh`;
6. считает `SHA256SUMS`, создаёт `provenance.json` и Homebrew cask из реальных
   байтов;
7. подписывает рассчитанные хеши GitHub/Sigstore attestation, связанным с
   конкретным workflow run;
8. сохраняет результат как закрытый Actions artifact на 14 дней.

Workflow **не создаёт GitHub Release, не двигает тег, не пишет в другой
репозиторий и ничего не публикует**. Публикация остаётся отдельным действием
владельца после скачивания и повторной проверки кандидата.

Attestation доказывает, какой GitHub workflow получил конкретные хеши. Она не доказывает,
что программа безопасна, что review был качественным или что сборка
воспроизводима байт-в-байт. Встроенные в приложение `OrakulCommit` и
`OrakulSourceHash` — ещё уже: это самоотчёт артефакта. Поэтому нужны обе
проверки, но ни одну нельзя называть аудитом безопасности или reproducible
build.

## Однократная настройка владельцем

До первого запуска владелец должен сделать сам:

- вернуть репозиторию каноническое имя `theasder/orakul`;
- защитить `main`: pull request, обязательный CI и запрет force-push;
- защитить шаблон тегов `v*` от удаления и перезаписи;
- создать GitHub Environment `release`, разрешить в нём только теги `v*` и
  назначить обязательного reviewer;
- включить обязательный Code Owner review: `.github/CODEOWNERS` назначает
  единственного сопровождающего владельцем всего дерева, потому что любой
  исходник, тест или скрипт может попасть в подписанный выпуск;
- после перевода репозитория в public добавить read-only check `Dependency
  review` в обязательные: публичный GitHub включает dependency graph сам, и
  commit-pinned workflow автоматически перестаёт быть пропущенным;
- добавить в Environment `release` пять secrets:
  `APPLE_DEVELOPER_ID_P12_BASE64`, `APPLE_DEVELOPER_ID_P12_PASSWORD`,
  `APPLE_NOTARY_KEY_P8_BASE64`, `APPLE_NOTARY_KEY_ID` и
  `APPLE_NOTARY_ISSUER_ID`;
- включить GitHub Private Vulnerability Reporting, как требует
  [`SECURITY.md`](../SECURITY.md).

Два base64-значения — содержимое экспортированного сертификата Developer ID
Application (`.p12`) и ключа App Store Connect (`.p8`), а не пути
к файлам на ноутбуке. Пароль относится к `.p12`. Workflow создаёт отдельную
временную Связку ключей, удаляет её после нотарификации и не печатает значения.

Ключи AI-провайдеров здесь не нужны и в GitHub Secrets не кладутся.
Пользователь сам вводит свой ключ в **Settings → AI → Provider keys** после
установки; Orakul хранит его в своей записи macOS Keychain.

Файлы правил и secrets сами по себе не включают защиту. Пока владелец не
настроил ruleset, environment reviewer и secrets в интерфейсе GitHub, наличие
workflow в репозитории не следует выдавать за защищённый процесс выпуска.

GitHub даёт artifact attestations публичным репозиториям на всех текущих
планах, но приватным и internal — только на Enterprise Cloud. Поэтому в
приватном личном репозитории этот workflow обязан остановиться на attestation:
не удаляйте шаг ради зелёной галочки, а запускайте выпуск после контролируемого
перевода проверенного репозитория в public либо на Enterprise Cloud. Это
ограничение зафиксировано в
[`actions/attest`](https://github.com/actions/attest#readme).

## Подготовить тег

1. В PR обновить `CFBundleShortVersionString` в `app/Support/Info.plist` и
   пользовательские release notes. Не править номер после тега.
2. Дождаться обязательных review и CI, затем слить PR в `main`.
3. Из нового чистого checkout проверить будущий тег локально. До создания тега
   полезны `npm run doctor` и все три набора тестов.
4. Создать **аннотированный** тег и отправить только его:

   ```bash
   git switch main
   git pull --ff-only
   git status --short                 # вывод обязан быть пустым
   git tag -a v0.2.0 -m "orakul v0.2.0"
   git push origin v0.2.0
   ```

Lightweight tag (`git tag v0.2.0`) release gate отвергнет. Workflow не создаёт
и не исправляет тег за владельца.

## Собрать кандидата

Запустить workflow **с самого тега**, передав тот же тег как input, затем
одобрить deployment в Environment `release`:

```bash
gh workflow run release-candidate.yml --ref v0.2.0 -f tag=v0.2.0
```

Два значения намеренно дублируются: workflow откажется работать, если его
определение взято не из `refs/tags/v0.2.0`. Обычный запуск из `main` с тегом
только в поле input не является выпуском. Успешный run оставит artifact
`orakul-vX.Y.Z-release-candidate` со следующим составом:

```text
orakul-AppleSilicon.dmg
orakul-Intel.dmg
orakul.rb
provenance.json
SHA256SUMS
orakul-attestation.sigstore.json
```

Для локальной диагностики уже собранных и нотарифицированных образов доступна
та же граница без GitHub:

```bash
npm run release:check -- v0.2.0
# release:check уже включает полный scripts/scan-history-secrets.mjs
bash scripts/audit-dmg.sh \
  app/dist/orakul-AppleSilicon.dmg \
  app/dist/orakul-Intel.dmg
bash scripts/release-manifest.sh v0.2.0
```

Локальный `provenance.json` не имеет подписи GitHub: это читаемый манифест, а
не attestation. Подписанный Sigstore bundle появляется только в workflow.

## Проверить скачанное и только потом публиковать

Artifact Actions — zip-контейнер. После скачивания распаковать его в отдельный
каталог и выполнить:

```bash
cd /путь/к/orakul-v0.2.0-release-candidate
shasum -a 256 -c SHA256SUMS

gh attestation verify orakul-AppleSilicon.dmg \
  --repo theasder/orakul \
  --signer-workflow theasder/orakul/.github/workflows/release-candidate.yml \
  --source-ref refs/tags/v0.2.0 \
  --deny-self-hosted-runners
gh attestation verify orakul-Intel.dmg \
  --repo theasder/orakul \
  --signer-workflow theasder/orakul/.github/workflows/release-candidate.yml \
  --source-ref refs/tags/v0.2.0 \
  --deny-self-hosted-runners
```

Для офлайн-проверки сначала на доверенной машине получить актуальный корень,
а затем перенести его вместе с кандидатом. Сохранённый workflow bundle
подписан и потому не входит в собственный `SHA256SUMS`:

```bash
gh attestation trusted-root > trusted_root.jsonl
gh attestation verify orakul-AppleSilicon.dmg \
  --repo theasder/orakul \
  --signer-workflow theasder/orakul/.github/workflows/release-candidate.yml \
  --source-ref refs/tags/v0.2.0 \
  --deny-self-hosted-runners \
  --bundle orakul-attestation.sigstore.json \
  --custom-trusted-root trusted_root.jsonl
```

На macOS из checkout того же тега повторить содержательную проверку обоих
образов:

```bash
git checkout v0.2.0
bash scripts/audit-dmg.sh \
  /путь/к/orakul-AppleSilicon.dmg \
  /путь/к/orakul-Intel.dmg
```

Только после этого владелец может создать **draft**, прочитать release notes,
проверить имена и скачать draft ещё раз перед публикацией. Например:

```bash
gh release create v0.2.0 \
  orakul-AppleSilicon.dmg \
  orakul-Intel.dmg \
  SHA256SUMS provenance.json orakul-attestation.sigstore.json \
  --verify-tag --draft --generate-notes --title "orakul v0.2.0"
```

Команда приведена как ручной шаг владельца; workflow её не вызывает. После
публикации следует скачать DMG уже с публичного URL, снова сверить SHA-256,
attestation, Gatekeeper и оба архитектурных имени. Homebrew cask переносится в
отдельный `theasder/homebrew-orakul` только после создания этого tap владельцем.

## Отказ — это результат

Выпуск должен остановиться, если тег лёгкий, версия расходится, checkout
грязный, тег не в истории `main`, одного DMG нет, sidecar не совпадает, Apple
не приняла подпись/нотарификацию, Gatekeeper отказал или attestation не
создалась. Обходить эти отказы переменной окружения в release workflow нельзя.
Исправление делается новым коммитом, новым review и новым тегом; опубликованный
тег не переписывается.
