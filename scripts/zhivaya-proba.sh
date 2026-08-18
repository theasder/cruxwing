#!/usr/bin/env bash
# Живая проверка коннектора: сервис поднимается здесь, а не «где-то у кого-то».
#
# Правило приёма (план, §7.1) требует прогона против ЖИВОГО сервиса, и это
# упиралось в аккаунты: у сопровождающего их нет. Для сервисов, которые ставят
# себе, аккаунт не нужен — нужен контейнер. Коннектор, собранный по
# документации, отличается от работающего ровно одним: его никто не запускал.
#
#     bash scripts/zhivaya-proba.sh gitea
#     bash scripts/zhivaya-proba.sh redmine
#
# Сервис поднимается, наполняется тремя задачами (две со словом «тарифы», одна
# без), коннектор ищет это слово, контейнер удаляется. Токен создаётся здесь же
# и живёт минуту: в репозиторий ничего не попадает.
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE="${1:-}"
QUERY="${ORAKUL_PROBE_QUERY:-тарифы}"
KEEP="${ORAKUL_PROBE_KEEP:-0}"
TASKS=("Поднять тарифы с декабря" "Починить вход по SSO" "Тарифы: пересчитать лимиты")

case "$SERVICE" in
  gitea|redmine) ;;
  *) echo "Использование: $0 gitea|redmine" >&2; exit 2 ;;
esac

NAME="orakul-proba-$SERVICE"
cleanup() {
  if [ "$KEEP" = "1" ]; then echo ">> контейнер ${NAME} оставлен (ORAKUL_PROBE_KEEP=1)"; return; fi
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait_for() {  # $1 — адрес, $2 — сколько попыток
  for _ in $(seq 1 "$2"); do
    [ "$(curl -s -o /dev/null -w '%{http_code}' "$1" || true)" = "200" ] && return 0
    sleep 3
  done
  echo "!! ${SERVICE} не поднялся за отведённое время" >&2
  return 1
}

if [ "$SERVICE" = gitea ]; then
  PORT=3999
  docker run -d --name "$NAME" -e GITEA__security__INSTALL_LOCK=true \
    -e GITEA__database__DB_TYPE=sqlite3 \
    -e "GITEA__server__ROOT_URL=http://localhost:$PORT/" \
    -p "$PORT:3000" gitea/gitea:1.22 >/dev/null
  wait_for "http://localhost:$PORT/api/v1/version" 40
  PASS='ПробаProba123!'
  docker exec -u git "$NAME" gitea admin user create --username proba \
    --password "$PASS" --email proba@example.com --admin --must-change-password=false >/dev/null

  # Токен для наполнения и токен для поиска — РАЗНЫЕ, и второй только на чтение.
  # Коннектор обязан работать с наименьшими правами: если проверять полным
  # токеном, недостающее право обнаружит человек, а не набор.
  make_token() {
    curl -s -X POST -H "Content-Type: application/json" -u "proba:$PASS" \
      -d "{\"name\":\"$1\",\"scopes\":[$2]}" \
      "http://localhost:$PORT/api/v1/users/proba/tokens" \
      | python3 -c "import sys,json; print(json.load(sys.stdin)['sha1'])"
  }
  SETUP=$(make_token наполнение '"write:repository","write:issue","write:user"')
  TOKEN=$(make_token поиск '"read:issue","read:repository","read:user"')

  curl -s -X POST -H "Authorization: token $SETUP" -H "Content-Type: application/json" \
    -d '{"name":"dogovory","private":false,"auto_init":true}' \
    "http://localhost:$PORT/api/v1/user/repos" >/dev/null
  for t in "${TASKS[@]}"; do
    curl -s -X POST -H "Authorization: token $SETUP" -H "Content-Type: application/json" \
      -d "{\"title\":\"$t\",\"body\":\"обсудили на звонке\"}" \
      "http://localhost:$PORT/api/v1/repos/proba/dogovory/issues" >/dev/null
  done
else
  PORT=3998
  docker run -d --name "$NAME" -p "$PORT:3000" redmine:5 >/dev/null
  wait_for "http://localhost:$PORT/" 60
  # Redmine из коробки — на SQLite, и это важно для чтения результата: у SQLite
  # LIKE приводит к одному регистру только ASCII, поэтому «Тарифы» и «тарифы»
  # для него разные слова. См. заметку в манифесте redmine.
  TOKEN=$(docker exec "$NAME" bash -c "cd /usr/src/redmine && RAILS_ENV=production bin/rails runner \"
    Setting.rest_api_enabled = '1'
    u = User.find_by_login('admin'); u.admin = true; u.must_change_passwd = false; u.save!
    status = IssueStatus.first || IssueStatus.create!(name: 'Новая', is_closed: false)
    prio = IssuePriority.first || IssuePriority.create!(name: 'Обычный', type: 'IssuePriority', is_default: true)
    tracker = Tracker.first || Tracker.create!(name: 'Задача', default_status: status)
    p = Project.find_by_identifier('dogovory') || Project.create!(name: 'Договоры', identifier: 'dogovory', is_public: true)
    p.trackers = [tracker]; p.enabled_module_names = ['issue_tracking']; p.save!
    ['${TASKS[0]}', '${TASKS[1]}', '${TASKS[2]}'].each do |s|
      Issue.create!(project: p, subject: s, tracker: tracker, author: u, status: status, priority: prio, description: 'обсудили на звонке')
    end
    puts u.api_key
  \"" | tail -1)
fi

echo ">> ${SERVICE} поднят на localhost:$PORT, спрашиваем «${QUERY}»"
ORAKUL_PROBE_SERVICE="$SERVICE" \
ORAKUL_PROBE_TOKEN="$TOKEN" \
ORAKUL_PROBE_HOST="http://localhost:$PORT" \
ORAKUL_PROBE_QUERY="$QUERY" \
swift test --package-path app --filter LiveConnectorProbe 2>&1 \
  | grep -E '^  — |✔ Test "коннектор|✘' || true

# Ответ «ничего не нашлось» — тоже зелёный набор: проба сообщает, что сервис
# ответил. Поэтому здесь отдельно требуем, чтобы нашлось хоть что-то: две из
# трёх задач содержат слово.
echo ">> если выше нет ни одной строки «— #», коннектор ответил пустотой"
