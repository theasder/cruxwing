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
#     bash scripts/zhivaya-proba.sh wikijs
#     bash scripts/zhivaya-proba.sh nextcloud
#     bash scripts/zhivaya-proba.sh plane
#     bash scripts/zhivaya-proba.sh gitlab   — минут двадцать, см. ниже
#
# Сервис поднимается, наполняется тремя задачами (две со словом «тарифы», одна
# без), коннектор ищет это слово, контейнер удаляется. Токен создаётся здесь же
# и живёт минуту: в репозиторий ничего не попадает.
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE="${1:-}"
QUERY="${ORAKUL_PROBE_QUERY:-тарифы}"
KEEP="${ORAKUL_PROBE_KEEP:-0}"
# Пустой массив и `set -u`: bash 3.2, который стоит в macOS, роняет
# `"${FIELDS[@]}"` как «unbound variable». Отсюда форма с +.
FIELDS=()
# Четвёртая запись — со словом только в КОСВЕННОЙ форме. Без неё проба не
# трогала бы русскую морфологию вовсе: чужой сервис не склоняет, и «тарифы» её
# не находит — находит вопрос основой. Заведена после того, как выяснилось, что
# набор проверял одно склонение из всех возможных, то есть самый частый случай
# разговорной речи оставался непроверенным.
TASKS=("Поднять тарифы с декабря" "Починить вход по SSO" "Тарифы: пересчитать лимиты"
       "Пересчитать смету вместе с тарифами")

case "$SERVICE" in
  gitea|redmine|wikijs|nextcloud|plane|gitlab|mattermost|rocketChat|matrix) ;;
  *) echo "Использование: $0 gitea|redmine|wikijs|nextcloud|plane|gitlab|mattermost|rocketChat|matrix" >&2; exit 2 ;;
esac

NAME="orakul-proba-$SERVICE"
cleanup() {
  if [ "$KEEP" = "1" ]; then echo ">> контейнер ${NAME} оставлен (ORAKUL_PROBE_KEEP=1)"; return; fi
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  # У Wiki.js своя база и своя сеть: без них следующий запуск поднимется
  # поверх прошлых данных, и «нашлось» будет про них.
  docker rm -f "${NAME}-db" >/dev/null 2>&1 || true
  # У Plane к базе добавляется ещё и кэш.
  docker rm -f "${NAME}-redis" >/dev/null 2>&1 || true
  docker network rm "${NAME}-net" >/dev/null 2>&1 || true
  # У Synapse настройки живут томом: без уборки следующий запуск
  # поднимется на прошлом ключе и прошлых сообщениях.
  docker volume rm "${NAME}-data" >/dev/null 2>&1 || true
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
elif [ "$SERVICE" = wikijs ]; then
  PORT=3997
  # Wiki.js без базы не поднимается, поэтому контейнера два и своя сеть между
  # ними. Наполнение вынесено в scripts/nastroit-wikijs.py: там четыре запроса
  # GraphQL подряд, и в строке командной оболочки они нечитаемы.
  docker network create "${NAME}-net" >/dev/null 2>&1 || true
  docker run -d --name "${NAME}-db" --network "${NAME}-net" \
    -e POSTGRES_DB=wiki -e POSTGRES_USER=wiki -e POSTGRES_PASSWORD=wikipass \
    postgres:15-alpine >/dev/null
  docker run -d --name "$NAME" --network "${NAME}-net" \
    -e DB_TYPE=postgres -e DB_HOST="${NAME}-db" -e DB_PORT=5432 \
    -e DB_USER=wiki -e DB_PASS=wikipass -e DB_NAME=wiki \
    -p "$PORT:3000" requarks/wiki:2 >/dev/null
  wait_for "http://localhost:$PORT/" 40

  PASS='ProbaProba123!'
  curl -s -X POST "http://localhost:$PORT/finalize" -H "Content-Type: application/json" \
    -d "{\"adminEmail\":\"proba@example.com\",\"adminPassword\":\"$PASS\",\"adminPasswordConfirm\":\"$PASS\",\"siteUrl\":\"http://localhost:$PORT\",\"telemetry\":false}" >/dev/null
  sleep 6
  wait_for "http://localhost:$PORT/" 20
  TOKEN=$(python3 scripts/nastroit-wikijs.py "$PORT" "$PASS")
elif [ "$SERVICE" = nextcloud ]; then
  PORT=3996
  PASS='ProbaProba123!'
  docker run -d --name "$NAME" -e SQLITE_DATABASE=nextcloud \
    -e NEXTCLOUD_ADMIN_USER=proba -e NEXTCLOUD_ADMIN_PASSWORD="$PASS" \
    -e NEXTCLOUD_TRUSTED_DOMAINS=localhost \
    -p "$PORT:80" nextcloud:29-apache >/dev/null
  wait_for "http://localhost:$PORT/status.php" 60

  # Единый поиск Nextcloud ищет по ИМЕНАМ файлов, поэтому «задачи» здесь —
  # файлы. Одно имя со строчной буквы намеренно: у установки по умолчанию база
  # SQLite, и поиск по русскому слову зависит от регистра (см. заметку
  # манифеста). Со строчным именем обычный запрос находит, и скрипт проверяет
  # коннектор, а не особенность чужой базы.
  # «Смета с тарифами.md» — имя с косвенной формой: единый поиск Nextcloud
  # ищет по именам файлов, значит и склонение проверяется там же.
  for f in "Тарифы и лимиты.md" "Вход по SSO.md" "тарифы на квартал.md" "Смета с тарифами.md"; do
    ENCODED=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$f")
    printf 'На звонке договорились поднять тарифы с декабря.' \
      | curl -s -u "proba:$PASS" -T - \
        "http://localhost:$PORT/remote.php/dav/files/proba/$ENCODED" -o /dev/null
  done
  docker exec -u www-data "$NAME" php occ files:scan --all >/dev/null 2>&1 || true
  TOKEN="proba:$PASS"
  FIELDS=(ORAKUL_FIELD_provider=files)
elif [ "$SERVICE" = plane ]; then
  PORT=3995
  docker network create "${NAME}-net" >/dev/null 2>&1 || true
  docker run -d --name "${NAME}-db" --network "${NAME}-net" \
    -e POSTGRES_USER=plane -e POSTGRES_PASSWORD=plane -e POSTGRES_DB=plane \
    postgres:15-alpine >/dev/null
  docker run -d --name "${NAME}-redis" --network "${NAME}-net" \
    valkey/valkey:7.2.5-alpine >/dev/null
  sleep 6
  PLANE_ENV=(-e DATABASE_URL=postgresql://plane:plane@${NAME}-db/plane
             -e REDIS_URL=redis://${NAME}-redis:6379/
             -e SECRET_KEY=proba-orakul-secret)
  docker run --rm --network "${NAME}-net" "${PLANE_ENV[@]}" \
    makeplane/plane-backend:stable ./bin/docker-entrypoint-migrator.sh >/dev/null 2>&1
  # Штатная точка входа поднимает ещё и хранилище объектов, которого здесь нет:
  # запускаем сервер напрямую. Проверяется коннектор, а не установка Plane.
  docker run -d --name "$NAME" --network "${NAME}-net" -p "$PORT:8000" \
    "${PLANE_ENV[@]}" --entrypoint gunicorn makeplane/plane-backend:stable \
    -w 1 -k uvicorn.workers.UvicornWorker plane.asgi:application --bind 0.0.0.0:8000 >/dev/null
  wait_for "http://localhost:$PORT/api/instances/" 60

  # Задачи и ключ заводятся напрямую в базе: у Plane и то и другое создаётся
  # через веб, а не через API, и кликать здесь некому. Пятая задача — со словом
  # ВНУТРИ подсветки: редактор Plane так и размечает, а сравнение с сырой
  # разметкой её не находит. Четвёртая — со словом только в описании.
  SETUP=$(docker exec -i "$NAME" python -c "
import django, os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'plane.settings.production')
django.setup()
from plane.db.models import User, Workspace, WorkspaceMember, Project, ProjectMember, State, Issue, APIToken
u, _ = User.objects.get_or_create(email='proba@example.com', defaults={'username': 'proba', 'display_name': 'Proba'})
ws, _ = Workspace.objects.get_or_create(slug='moya-komanda', defaults={'name': 'Моя команда', 'owner': u})
WorkspaceMember.objects.get_or_create(workspace=ws, member=u, defaults={'role': 20})
pr, _ = Project.objects.get_or_create(workspace=ws, identifier='PRB', defaults={'name': 'Проба', 'created_by': u})
ProjectMember.objects.get_or_create(project=pr, member=u, workspace=ws, defaults={'role': 20})
st, _ = State.objects.get_or_create(project=pr, name='В работе', workspace=ws, defaults={'group': 'started', 'created_by': u})
rows = [('${TASKS[0]}', '<p>Пересмотреть цены</p>'),
        ('${TASKS[1]}', '<p>Не пускает через провайдера</p>'),
        ('${TASKS[2]}', '<p>Лимиты в описании тоже про тарифы</p>'),
        ('${TASKS[3]}', '<p>Смета на квартал</p>'),
        ('Починить экспорт', '<p>Экспорт цен и ${QUERY} за квартал</p>'),
        ('Обновить прайс', '<p>Пересчитать <strong>тари</strong>фы за квартал</p>')]
for i, (name, html) in enumerate(rows, start=1):
    Issue.objects.get_or_create(project=pr, name=name, workspace=ws,
        defaults={'description_html': html, 'state': st, 'created_by': u, 'sequence_id': i})
t, _ = APIToken.objects.get_or_create(user=u, workspace=ws, label='proba')
print('%s %s' % (pr.id, t.token))" | tail -1)
  TOKEN="${SETUP##* }"
  FIELDS=(ORAKUL_FIELD_workspace=moya-komanda "ORAKUL_FIELD_project=${SETUP%% *}")
elif [ "$SERVICE" = mattermost ]; then
  # Первый мессенджер в этой пробе, и семья другая: у трекеров заводят задачи,
  # здесь пишут сообщения в канал.
  #
  # Образ mattermost-preview несёт базу внутри и был бы проще — но под arm64 его
  # нет вовсе («no matching manifest for linux/arm64/v8»), а гонять сервер под
  # эмуляцией ради удобства скрипта значит мерить не то. Берём обычную сборку и
  # свою Postgres рядом: две коробки и своя сеть — та же схема, что у Wiki.js и
  # Plane, и уборка для неё в этом скрипте уже написана.
  PORT=3992
  docker network create "${NAME}-net" >/dev/null
  docker run -d --name "${NAME}-db" --network "${NAME}-net" \
    -e POSTGRES_USER=mmuser -e POSTGRES_PASSWORD=mmuser -e POSTGRES_DB=mattermost \
    postgres:15-alpine >/dev/null
  docker run -d --name "$NAME" --network "${NAME}-net" -p "$PORT:8065" \
    -e MM_SQLSETTINGS_DRIVERNAME=postgres \
    -e "MM_SQLSETTINGS_DATASOURCE=postgres://mmuser:mmuser@${NAME}-db:5432/mattermost?sslmode=disable&connect_timeout=10" \
    -e "MM_SERVICESETTINGS_SITEURL=http://localhost:$PORT" \
    mattermost/mattermost-team-edition:9.11 >/dev/null
  wait_for "http://localhost:$PORT/api/v4/system/ping" 80
  PASS='ПробаProba123!'
  # Первый заведённый пользователь становится администратором — установка ещё
  # пустая, поэтому регистрация открыта и токен для неё не нужен.
  curl -s -X POST -H 'Content-Type: application/json' \
    -d "{\"email\":\"proba@example.com\",\"username\":\"proba\",\"password\":\"$PASS\"}" \
    "http://localhost:$PORT/api/v4/users" >/dev/null
  # Токен приходит ЗАГОЛОВКОМ, а не в теле: тело — это профиль.
  TOKEN=$(curl -s -i -X POST -H 'Content-Type: application/json' \
    -d "{\"login_id\":\"proba@example.com\",\"password\":\"$PASS\"}" \
    "http://localhost:$PORT/api/v4/users/login" \
    | grep -i '^token:' | cut -d' ' -f2 | tr -d '\r')
  [ -n "$TOKEN" ] || { echo "!! вход не дал токена" >&2; exit 1; }
  api() { curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$2" "http://localhost:$PORT$1"; }
  TEAM=$(api /api/v4/teams '{"name":"proba","display_name":"Проба","type":"O"}' \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  CHAN=$(api /api/v4/channels "{\"team_id\":\"$TEAM\",\"name\":\"dogovory\",\"display_name\":\"Договоры\",\"type\":\"O\"}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  for t in "${TASKS[@]}"; do
    # dict(...) вместо фигурных скобок: оболочка раскрывает их прямо внутри
    # двойных кавычек и рвёт строку питона пополам.
    api /api/v4/posts "$(python3 -c "import json,sys; print(json.dumps(dict(channel_id=sys.argv[1], message=sys.argv[2])))" "$CHAN" "$t")" >/dev/null
  done
  # Команда в адресе — идентификатор, а не имя: так записано в манифесте
  # примером, и живая установка тому единственный судья.
  #
  # Передаётся она ОБЛАСТЬЮ, а не полем: у мессенджеров поле ровно одно, и
  # проба кладёт его в `scope`. Через ORAKUL_FIELD_* оно не доедет — ветка
  # мессенджеров в пробе полей манифеста не читает вовсе.
  SCOPE="$TEAM"
# Имя сервиса пишется ровно так, как в манифесте, — `rocketChat`.
# Проба ищет коннектор по этому имени, и «rocketchat» строчными она не
# знает: сервис поднялся бы, наполнился и не нашёлся.
elif [ "$SERVICE" = rocketChat ]; then
  # Второй мессенджер. База своя, и не просто рядом: Rocket.Chat требует от
  # MongoDB НАБОРА РЕПЛИК — он читает oplog, а одиночный сервер его не ведёт.
  # Отсюда лишний шаг с rs.initiate, которого нет ни у кого выше.
  PORT=3991
  docker network create "${NAME}-net" >/dev/null
  docker run -d --name "${NAME}-db" --network "${NAME}-net" \
    mongo:8.0 --replSet rs0 --bind_ip_all >/dev/null
  for _ in $(seq 1 30); do
    docker exec "${NAME}-db" mongosh --quiet --eval \
      'try { rs.status().ok } catch (e) { rs.initiate({_id:"rs0",members:[{_id:0,host:"'"${NAME}"'-db:27017"}]}).ok }' \
      >/dev/null 2>&1 && break
    sleep 2
  done
  docker run -d --name "$NAME" --network "${NAME}-net" -p "$PORT:3000" \
    -e "MONGO_URL=mongodb://${NAME}-db:27017/rocketchat?replicaSet=rs0" \
    -e "MONGO_OPLOG_URL=mongodb://${NAME}-db:27017/local?replicaSet=rs0" \
    -e "ROOT_URL=http://localhost:$PORT" \
    -e OVERWRITE_SETTING_Show_Setup_Wizard=completed \
    -e ADMIN_USERNAME=proba -e ADMIN_PASS='ПробаProba123!' \
    -e ADMIN_EMAIL=proba@example.com \
    rocketchat/rocket.chat:8.5.3 >/dev/null
  wait_for "http://localhost:$PORT/api/info" 90
  LOGIN=$(curl -s -X POST -H 'Content-Type: application/json' \
    -d "$(python3 -c "import json,sys;print(json.dumps(dict(user='proba', password=sys.argv[1])))" 'ПробаProba123!')" \
    "http://localhost:$PORT/api/v1/login")
  AUTH=$(printf '%s' "$LOGIN" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['data']['authToken'])")
  UID_=$(printf '%s' "$LOGIN" | python3 -c "import sys,json;d=json.load(sys.stdin);print(d['data']['userId'])")
  [ -n "$AUTH" ] || { echo "!! вход не дал токена" >&2; exit 1; }
  rc() { curl -s -X POST -H "X-Auth-Token: $AUTH" -H "X-User-Id: $UID_" \
    -H 'Content-Type: application/json' -d "$2" "http://localhost:$PORT$1"; }
  ROOM=$(rc /api/v1/channels.create '{"name":"dogovory"}' \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['channel']['_id'])")
  for t in "${TASKS[@]}"; do
    rc /api/v1/chat.postMessage "$(python3 -c "import json,sys;print(json.dumps(dict(roomId=sys.argv[1], text=sys.argv[2])))" "$ROOM" "$t")" >/dev/null
  done
  # Два значения одной строкой через двоеточие — так же, как их вписывает
  # человек: манифест делит её на {tokenHead} и {tokenTail}.
  TOKEN="$AUTH:$UID_"
  SCOPE="$ROOM"
elif [ "$SERVICE" = matrix ]; then
  # Третий мессенджер, и единственный, где сервер сначала СЕБЯ настраивает:
  # Synapse генерирует ключи и файл настроек отдельным запуском, и только потом
  # умеет стартовать. Отсюда том — общий для обоих запусков.
  PORT=3990
  docker volume create "${NAME}-data" >/dev/null
  docker run --rm -v "${NAME}-data:/data" \
    -e SYNAPSE_SERVER_NAME=proba.local -e SYNAPSE_REPORT_STATS=no \
    matrixdotorg/synapse:latest generate >/dev/null 2>&1
  docker run -d --name "$NAME" -v "${NAME}-data:/data" -p "$PORT:8008" \
    matrixdotorg/synapse:latest >/dev/null
  wait_for "http://localhost:$PORT/_matrix/client/versions" 60
  PASS='ПробаProba123!'
  # Регистрация общим секретом, а не открытая: сервер остаётся закрытым, как у
  # людей, и проверяем мы коннектор, а не гостеприимство сервера.
  docker exec "$NAME" register_new_matrix_user -u proba -p "$PASS" -a \
    -c /data/homeserver.yaml "http://localhost:8008" >/dev/null 2>&1
  TOKEN=$(curl -s -X POST -H 'Content-Type: application/json' \
    -d "$(python3 -c "import json,sys;print(json.dumps(dict(type='m.login.password', user='proba', password=sys.argv[1])))" "$PASS")" \
    "http://localhost:$PORT/_matrix/client/v3/login" \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['access_token'])")
  [ -n "$TOKEN" ] || { echo "!! вход не дал токена" >&2; exit 1; }
  ROOM=$(curl -s -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    -d '{"name":"Договоры","preset":"private_chat"}' \
    "http://localhost:$PORT/_matrix/client/v3/createRoom" \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['room_id'])")
  n=0
  for t in "${TASKS[@]}"; do
    n=$((n+1))
    curl -s -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d "$(python3 -c "import json,sys;print(json.dumps(dict(msgtype='m.text', body=sys.argv[1])))" "$t")" \
      "http://localhost:$PORT/_matrix/client/v3/rooms/$ROOM/send/m.room.message/proba$n" >/dev/null
  done
elif [ "$SERVICE" = gitlab ]; then
  PORT=3993
  # Двадцать минут на подъём — и это не преувеличение: официального образа под
  # arm64 у GitLab CE нет, на этой машине он идёт через эмуляцию. Проба всё
  # равно нужна: GitLab — самый частый свой сервер у западных команд, а его
  # манифест был собран по документации.
  #
  # Порт снаружи и внутри ОДИН И ТОТ ЖЕ: nginx слушает тот, что стоит в
  # external_url, поэтому «-p 3993:80» даёт контейнер, который здоров и молчит.
  docker run -d --name "$NAME" --shm-size 256m -p "$PORT:$PORT" \
    -e GITLAB_OMNIBUS_CONFIG="external_url 'http://localhost:$PORT'; gitlab_rails['initial_root_password']='ProbaProba123!'; puma['worker_processes']=2; sidekiq['max_concurrency']=5; prometheus_monitoring['enable']=false; gitlab_rails['gitlab_shell_ssh_port']=2222" \
    gitlab/gitlab-ce:17.5.1-ce.0 >/dev/null
  echo ">> gitlab поднимается, это долго"
  for _ in $(seq 1 100); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "http://localhost:$PORT/api/v4/version" || true)
    [ "$code" = "401" ] && break
    sleep 20
  done
  [ "$code" = "401" ] || { echo "!! gitlab не поднялся" >&2; exit 1; }

  # Токен только на чтение: коннектор обязан работать с наименьшими правами.
  TOKEN=probaprobaprobaproba
  docker exec "$NAME" gitlab-rails runner "
    u = User.find_by_username('root')
    t = u.personal_access_tokens.find_by(name: 'proba') ||
        u.personal_access_tokens.create!(name: 'proba', scopes: ['read_api'], expires_at: 1.year.from_now)
    t.set_token('$TOKEN'); t.save!
    p = Project.find_by(path: 'dogovory') ||
        Projects::CreateService.new(u, name: 'Договоры', path: 'dogovory',
          namespace_id: u.namespace.id, visibility_level: 0, initialize_with_readme: false).execute
    ['${TASKS[0]}', '${TASKS[1]}', '${TASKS[2]}', '${TASKS[3]}'].each do |title|
      next if p.issues.find_by(title: title)
      Issues::CreateService.new(container: p, current_user: u,
        params: {title: title, description: 'обсудили на звонке'}, perform_spam_check: false).execute
    end
  " >/dev/null 2>&1
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
    ['${TASKS[0]}', '${TASKS[1]}', '${TASKS[2]}', '${TASKS[3]}'].each do |s|
      Issue.create!(project: p, subject: s, tracker: tracker, author: u, status: status, priority: prio, description: 'обсудили на звонке')
    end
    puts u.api_key
  \"" | tail -1)
fi

echo ">> ${SERVICE} поднят на localhost:$PORT, спрашиваем «${QUERY}»"
OUT=$(mktemp)
env ${FIELDS[@]+"${FIELDS[@]}"} \
  ORAKUL_PROBE_SERVICE="$SERVICE" \
  ORAKUL_PROBE_TOKEN="$TOKEN" \
  ORAKUL_PROBE_HOST="http://localhost:$PORT" \
  ORAKUL_PROBE_QUERY="$QUERY" \
  ORAKUL_PROBE_SCOPE="${SCOPE:-}" \
  swift test --package-path app --filter LiveConnectorProbe 2>&1 \
  | grep -E '^  — |✔ Test "коннектор|✘' > "$OUT" || true
cat "$OUT"

# Пустая выдача здесь — поломка, и скрипт обязан об этом сказать кодом возврата.
#
# Проба считает ответ сервиса успехом независимо от числа находок: она проверяет,
# что коннектор доехал. Но данные сюда клали мы сами, и две записи из трёх
# содержат слово. Ноль находок значит, что сломан коннектор, запрос или
# наполнение, — а печать предупреждения при нулевом коде возврата и есть тот
# самый сторож, который не может сработать.
if ! grep -q '^  — ' "$OUT"; then
  echo "!! коннектор ответил пустотой, хотя две записи из четырёх содержат «${QUERY}»" >&2
  rm -f "$OUT"
  exit 1
fi

# Косвенная форма — отдельная проверка, и печать без кода возврата была бы тем
# самым сторожем, который не может сработать. «Смету» ищется по слову, которого
# в вопросе нет: найтись она может только вопросом основой.
#
# Кроме Gitea. Там поиск сравнивает слова ЦЕЛИКОМ, и это измерено на живой
# установке 2026-08-19: «тарифы» нашли две задачи, «тариф» — ноль. Требовать от
# него косвенную форму значило бы требовать невозможного, а сторож, который
# нельзя удовлетворить, отключают целиком — вместе с проверкой остальных.
# -i обязателен: у Nextcloud имя файла начинается с прописной «Смета», и
# строчный образец её не находил — сторож объявлял пропажу того, что доехало.
# Освобождённые — списком с измерением у каждого, а не цепочкой сравнений.
#
# Общее у всех троих одно: слова сравниваются ЦЕЛИКОМ, и знака подстановки нет.
# Требовать от них косвенную форму значит требовать невозможного, а сторож,
# который нельзя удовлетворить, отключают целиком — вместе с проверкой
# остальных.
#
#   gitea      — измерено 2026-08-19: «тарифы» нашли две задачи, «тариф» ноль.
#   rocketChat — измерено 2026-08-20: «тарифы» 2, «тарифами» 1, «тариф» 0,
#                «тариф*» тоже 0.
#   matrix     — измерено 2026-08-20: «тариф» 0 и «тариф*» 0. Там же выяснилось
#                другое: поиск РАЗЛИЧАЕТ РЕГИСТР на кириллице — «тарифы» находит
#                одно сообщение, «Тарифы» другое, «ТАРИФЫ» ни одного. Ровно то,
#                ради чего задаётся второй вопрос: коннектор находит два, а любое
#                одиночное написание — одно.
#
# У Mattermost знак подстановки работает, поэтому он не здесь: там основа
# объявлена в манифесте (stemSuffix) и косвенная форма доезжает.
case "$SERVICE" in
  gitea|rocketChat|matrix) STEM_EXPECTED=0 ;;
  *) STEM_EXPECTED=1 ;;
esac
if [ "$STEM_EXPECTED" = 1 ] && ! grep -qi 'смет' "$OUT"; then
  echo "!! запись со словом «тарифами» не доехала: вопрос основой не сработал" >&2
  rm -f "$OUT"
  exit 1
fi
rm -f "$OUT"
