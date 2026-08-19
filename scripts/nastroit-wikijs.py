import json, sys, time, urllib.request
port, password = sys.argv[1], sys.argv[2]

def gql(query, token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request("http://localhost:%s/graphql" % port,
                                 data=json.dumps({"query": query}).encode(), headers=headers)
    return json.load(urllib.request.urlopen(req))

login = ('mutation { authentication { login(username:"proba@example.com", '
         'password:"%s", strategy:"local") { jwt } } }' % password)
jwt = gql(login)["data"]["authentication"]["login"]["jwt"]

# Ключ API у Wiki.js работает только при включённом API. Создание ключа при
# выключенном проходит, а сам ключ отвечает отказом — выглядит как поломка
# коннектора, хотя коннектор ни при чём.
gql('mutation { authentication { setApiState(enabled: true) { responseResult { succeeded } } } }', jwt)
key = gql('mutation { authentication { createApiKey(name:"orakul", expiration:"1y", '
          'fullAccess:true) { key } } }', jwt)["data"]["authentication"]["createApiKey"]["key"]

# Локаль ru у Wiki.js не установлена, и страница с ней не создаётся вовсе:
# внешний ключ на locale. Текст при этом русский — проверяется поиск по слову,
# а не язык интерфейса.
# Третья страница — со словом только в косвенной форме: «тарифами» вопросом
# «тарифы» не находится, находится вопросом основой. Без такой страницы проба
# проверяла бы одно склонение из всех, а разговорная речь состоит из остальных.
pages = [("Тарифы и лимиты", "тарифы", "tarify"),
         ("Вход по SSO", "вход", "sso"),
         ("Смета на квартал", "тарифами", "smeta-kvartal")]
for title, word, path in pages:
    gql('mutation { pages { create(content:"На звонке договорились поднять %s с декабря.", '
        'description:"про %s", editor:"markdown", isPublished:true, isPrivate:false, '
        'locale:"en", path:"%s", tags:[], title:"%s") { responseResult { succeeded } } } }'
        % (word, word, path, title), key)
time.sleep(2)
print(key)
