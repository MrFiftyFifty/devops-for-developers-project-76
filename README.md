### Hexlet tests and linter status:
[![Actions Status](https://github.com/MrFiftyFifty/devops-for-developers-project-76/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/MrFiftyFifty/devops-for-developers-project-76/actions/workflows/hexlet-check.yml)

Это мой учебный проект по DevOps. Я собрал небольшой стенд: nginx с TLS в роли балансировщика, за ним два контейнера [Redmine](https://hub.docker.com/_/redmine) и один общий PostgreSQL. Ansible сначала ставит на машины Docker и нужные пакеты, потом раскатывает само приложение — env-файлы, конфиг nginx, самоподписанный сертификат и `docker-compose` в каталоге `infra/`. В инвентаре сейчас два хоста на `127.0.0.1` с `ansible_connection=local`, то есть всё крутится локально, но те же плейбуки можно направить на обычные серверы по SSH, если поменять `inventory.ini`.

## Куда заходить

Когда стек поднят, в `/etc/hosts` (или в своём DNS) нужно, чтобы `devops.example` указывал на ваш хост — как именно, я расписал в `infra/LOCAL_DOMAIN.txt`. После этого в браузере открывается [https://devops.example/](https://devops.example/). Сертификат самоподписанный, поэтому браузер будет ругаться: для локалки это нормально, на проде обычно вешают нормальный сертификат на балансировщик, а суть та же.

Проверить с терминала можно так:

```bash
curl -skI -H "Host: devops.example" https://127.0.0.1/
```

## Что нужно на машине

Ставил у себя Ansible (можно `ansible-core`), Python 3, Docker и `docker-compose` — либо отдельной утилитой, либо через `docker compose`. Ещё пригодятся `openssl` и `make`. Там, где в плейбуке стоит `become: true`, Ansible попросит права root, так что `sudo` должен быть доступен.

Роли и коллекции тянутся из Galaxy по `requirements.yml`. Я не коммичу каталоги `roles/` и `collections/` — они в `.gitignore`, их один раз подтягивает `make prepare-servers`. Если хочется вручную: `ansible-galaxy role install …` и `ansible-galaxy collection install …` с `-r requirements.yml`, как в [документации Ansible](https://docs.ansible.com/ansible/latest/galaxy/user_guide.html). Как Docker подставляет переменные в compose, хорошо объясняют в [доках Docker](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) про интерполяцию и env-файлы.

## Как я запускаю

Файл `group_vars/all/vault.yml` в репозитории лежит **открытым текстом** с учебными заглушками — так автопроверки Hexlet могут гонять Ansible без пароля Vault. Для своих паролей и ключей правьте этот файл локально; если хотите хранить его в [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html), выполните `ansible-vault encrypt group_vars/all/vault.yml` и дальше держите `.vault_pass` в корне (он в `.gitignore`) и вызывайте `ansible-playbook` с `--vault-password-file` — у `make prepare-servers` / `deploy` / `check` это подхватывается через `$(VAULT_OPT)`, если `.vault_pass` есть. `make vault-view` смотрит, зашифрован ли файл, и либо вызывает `ansible-vault view`, либо просто печатает содержимое. Потом `make prepare-servers` — подтянет Galaxy и прогонит плейбук с тегом `setup`. Дальше `make deploy` — это уже только приложение. Если нужен Datadog, после того как положил нормальный API-ключ в Vault, вызываю `make monitoring` — агент ставится только на группу `webservers`, как и задумано.

Когда env и nginx уже собраны деплоем, иногда удобно просто поднять compose без Ansible: `make up` и `make down`. Для быстрой проверки DNS и ответа по HTTPS есть `make dns-test`.

## Плейбук

Всё лежит в одном `playbook.yml`, я разнес сценарии по [тегам](https://docs.ansible.com/ansible/latest/user_guide/playbooks_tags.html). С `setup` идут роли `geerlingguy.pip` и `geerlingguy.docker` — ставится pip-пакет `docker` и сам Docker. С `deploy` ничего из пакетов не ставится: шаблонами собираются `infra/env/db.env`, `infra/env/web1.env` и `infra/env/web2.env`, конфиг `infra/nginx/nginx.conf`, генерируется ключ и сертификат под домен из переменных, и в `infra/` выполняется `docker-compose down` и `up -d`. Оба этих куска идут на `hosts: all`, чтобы автопроверкам было проще.

Отдельно вынес тег `monitoring`: он крутится только на **`webservers`**. Там подключается роль из коллекции [datadog.dd](https://galaxy.ansible.com/ui/repo/published/datadog/dd/) ([как описано у Datadog](https://docs.datadoghq.com/agent/basic_agent_usage/ansible/)). Пока в Vault лежит не настоящий hex-ключ API, роль я сознательно пропускаю — иначе бы ломались сценарии без аккаунта в Datadog. Когда ключ настоящий, агент поднимается и шлёт данные; для проверки доступности приложения я настроил [HTTP check](https://docs.datadoghq.com/integrations/http_check/) на `https://127.0.0.1/` с заголовком `Host` как у Redmine, TLS-проверку отключил под самоподписанный сертификат.

Первый запуск Redmine после смены образа иногда тянется до минуты — там миграции в Postgres. Если сразу после деплоя nginx отдаёт 502, я обычно подожду немного и обновляю страницу.

## Переменные и секреты

И публичные настройки, и ссылки на секреты лежат в `group_vars/all/vars.yml`: порт, домен, pip-пакеты, `postgres_password` и `redmine_secret_key_base` через `vault_*`, настройки Datadog и `datadog_checks`. Сами значения `vault_*` — в `group_vars/all/vault.yml` (в git открытым текстом для CI; при желании зашифруйте у себя Vault’ом). Так сделано не только для порядка: в автопроверках Hexlet плейбук гоняют с инвентарём на один хост `localhost`, без группы `webservers`, и тогда переменные из `group_vars/webservers/` просто не подхватились бы. Сам плей с тегом `monitoring` по-прежнему только для `webservers` из вашего `inventory.ini`, то есть агент Datadog на реальном стенде ставится не на каждый хост подряд.

Инвентарь — `inventory.ini`, в группе `webservers` два хоста, `web1` и `web2`. Оба Redmine ходят в один Postgres в docker-сети и делят один `SECRET_KEY_BASE` из Vault, чтобы сессии за балансировщиком не рассыпались.

## Проверки

На каждый пуш GitHub запускает [hexlet-check](https://github.com/MrFiftyFifty/devops-for-developers-project-76/actions/workflows/hexlet-check.yml) через [hexlet/project-action](https://github.com/hexlet/project-action) — этот workflow трогать не нужно, он для платформы.

Локально я иногда гоняю `make check` (это же, что `make test`) — там `ansible-playbook` с `--syntax-check` и с Vault, если рядом лежит `.vault_pass`. Без файла можно вызвать `ansible-playbook playbook.yml --syntax-check` и ввести пароль вручную.

## Makefile

В `Makefile` у меня зашито следующее: `prepare-servers` и `deploy` — основной цикл; `monitoring` — Datadog; `check` / `test` — синтаксис плейбука; `vault-edit` и `vault-view` — работа с зашифрованным vault; `up`, `down`, `logs`, `ps` — обёртка над compose в `infra/`; `dns-test` — быстрая проверка DNS и HTTPS.

Если что-то из имён и резолва на локалке не сходится, смотрите `infra/LOCAL_DOMAIN.txt`.
