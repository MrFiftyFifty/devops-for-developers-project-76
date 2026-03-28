### Hexlet tests and linter status:
[![Actions Status](https://github.com/MrFiftyFifty/devops-for-developers-project-76/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/MrFiftyFifty/devops-for-developers-project-76/actions/workflows/hexlet-check.yml)

Это учебный проект по DevOps. Здесь поднят небольшой стенд: nginx в роли балансировщика с TLS, за ним два контейнера [Redmine](https://hub.docker.com/_/redmine), плюс Ansible — сначала для установки Docker и зависимостей на «серверах», потом для деплоя самого приложения. Облако нигде не захардкожено: в `inventory.ini` сейчас два хоста на `127.0.0.1` с `ansible_connection=local`, но те же плейбуки можно направить на обычные машины по SSH, если поменять инвентарь.

## Куда заходить после деплоя

Если в `/etc/hosts` (или в своём DNS) прописан `devops.example` на `127.0.0.1`, в браузере можно открыть **[https://devops.example/](https://devops.example/)**. Сертификат самоподписанный, браузер будет ругаться — для локалки это ожидаемо. На проде на балансировщике обычно вешают нормальный сертификат, но идея та же: TLS обрывается на nginx, до бэкендов идёт уже HTTP внутри сети.

## Что поставить себе на машину

Нужны Ansible (или `ansible-core`), Python 3, Docker и `docker-compose` (либо плагин Compose для `docker compose`). Ещё `openssl` и `make`. Роли и коллекции из Galaxy один раз подтягиваются так:

```bash
ansible-galaxy role install -r requirements.yml -p roles
ansible-galaxy collection install -r requirements.yml -p collections
```

Удобнее просто вызвать `make prepare-servers` — там это уже зашито.

Про подстановку переменных в compose-файлах можно почитать у Docker: [интерполяция](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) и [env-файлы](https://docs.docker.com/compose/env-file/). При деплое Ansible собирает `infra/env/db.env` (пароль Postgres для сервиса `db`) и `infra/env/web1.env` / `infra/env/web2.env` для контейнеров [Redmine](https://hub.docker.com/_/redmine) из шаблонов в `templates/` — вручную их трогать не нужно.

Redmine ходит в один общий Postgres в Docker-сети `backend` (хост `db` в compose, переменные `REDMINE_DB_POSTGRES` и остальные — как в официальной документации образа). Два контейнера приложения за балансировщиком делят одну БД и один и тот же `SECRET_KEY_BASE` из Vault, чтобы сессии за nginx не ломались.

## Как устроен плейбук

В корне лежит один `playbook.yml`, оба сценария идут на `hosts: all` (так удобнее автопроверкам). Я разделил их [тегами](https://docs.ansible.com/ansible/latest/user_guide/playbooks_tags.html):

С тегом `setup` крутятся роли `geerlingguy.pip` и `geerlingguy.docker` — ставится pip-пакет `docker` и сам Docker Engine. Запуск: `make prepare-servers` или `ansible-playbook playbook.yml --tags setup`. Здесь почти наверняка понадобится `sudo` (в плейбуке `become: true`).

С тегом `monitoring` на хостах группы **`webservers`** ставится агент [Datadog](https://www.datadoghq.com/) через официальную коллекцию Ansible [`datadog.dd`](https://galaxy.ansible.com/ui/repo/published/datadog/dd/) (см. [документацию Datadog по Ansible](https://docs.datadoghq.com/agent/basic_agent_usage/ansible/)). API-ключ и сайт (`datadoghq.com` или, например, `datadoghq.eu`) лежат в Vault как `vault_datadog_api_key` и `vault_datadog_site`. Пока в Vault стоит заглушка вместо настоящего 32-символьного hex-ключа, плейбук **пропускает** установку агента, чтобы `make prepare-servers` и CI не ломались. После регистрации в Datadog подставьте ключ через `make vault-edit` и выполните `make monitoring` (или `ansible-playbook playbook.yml --tags monitoring`). Для проверки доступности Redmine через балансировщик на той же машине настроен интеграционный [HTTP check](https://docs.datadoghq.com/integrations/http_check): запрос на `https://127.0.0.1/` с заголовком `Host: devops.example`, проверка TLS отключена под самоподписанный сертификат.

С тегом `deploy` серверы «не трогаем» в смысле установки пакетов — только приложение: через [модуль template](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html) собираются env-файлы (включая доступ к БД) и `infra/nginx/nginx.conf`, генерируется сертификат под домен из `redmine_domain`, затем в каталоге `infra/` выполняется `docker-compose down` и `docker-compose up -d`. Это `make deploy` или `ansible-playbook playbook.yml --tags deploy`.

Первый запуск Redmine после смены образа иногда тянется до минуты — там миграции БД. Если сразу после деплоя nginx отдаёт 502, подождите немного и обновите страницу.

## Переменные, Vault и инвентарь

Обычные переменные группы лежат в `group_vars/webservers/vars.yml`: там же, например, `postgres_password: "{{ vault_postgres_password }}"` и `redmine_secret_key_base: "{{ vault_redmine_secret_key_base }}"` — то есть ссылки на секреты из Vault.

Сами секреты — в `group_vars/webservers/vault.yml`. Файл целиком зашифрован [Ansible Vault](https://docs.ansible.com/ansible/latest/user_guide/vault.html#encrypting-content-with-ansible-vault); править его удобно через `make vault-edit` или вручную `ansible-vault edit` / `view` ([справка по ansible-vault](https://docs.ansible.com/ansible/latest/cli/ansible-vault.html)). Чтобы не вводить пароль каждый раз, положите в корень проекта файл `.vault_pass` с одной строкой — паролем (в репозиторий он не попадает). Для быстрого старта можно скопировать `vault_pass.example` в `.vault_pass`: там пароль для учебного зашифрованного файла в этом репозитории. В проде — свой пароль, `ansible-vault rekey` и никаких паролей в git.

Пароль от БД и Rails-секрет лежат в Vault как `vault_postgres_password` и `vault_redmine_secret_key_base`. Для мониторинга там же `vault_datadog_api_key` и `vault_datadog_site` (по умолчанию в репозитории зашит `datadoghq.com`). Публичные настройки вроде `redmine_port` (по умолчанию 3000) и `redmine_domain` остаются в `vars.yml`.

В `inventory.ini` по-прежнему группа `webservers` с `web1` и `web2`; для боевых серверов — свои `ansible_host` и SSH.

## Make-цели, которыми я пользуюсь

`make prepare-servers` — Galaxy и только `setup` (нужен расшифрованный Vault, иначе Ansible не прочитает `group_vars`).  
`make deploy` — только деплой приложения.  
`make monitoring` — установка и настройка агента Datadog на `webservers` (нужен валидный API-ключ в Vault).  
`make vault-edit` / `make vault-view` — правка или просмотр зашифрованного `vault.yml` (если есть `.vault_pass`, он подставится сам; иначе Vault спросит пароль в интерактиве).  
`make up` и `make down` — поднять или остановить compose в `infra/`, когда `infra/env/*.env` и nginx уже собраны деплоем.  
`make dns-test` — проверка DNS и ответа по HTTPS.

Порядок у меня обычно такой: `cp vault_pass.example .vault_pass` (или свой пароль в `.vault_pass`), затем `make prepare-servers`, потом `make deploy`.

## Имена и DNS на локалке

Как прописать хосты и как проверить резолв, расписано в `infra/LOCAL_DOMAIN.txt`. Для ручной проверки HTTPS можно так: `curl -skI -H "Host: devops.example" https://127.0.0.1/`.
