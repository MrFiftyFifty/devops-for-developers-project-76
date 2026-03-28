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

Про подстановку переменных в compose-файлах можно почитать у Docker: [интерполяция](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/) и [env-файлы](https://docs.docker.com/compose/env-file/). Переменные для контейнеров Redmine лежат в `infra/env/web1.env` и `infra/env/web2.env`; эти файлы не редактирую руками — их рисует Ansible из `templates/redmine.env.j2` при деплое.

## Как устроен плейбук

В корне лежит один `playbook.yml`, оба сценария идут на `hosts: all` (так удобнее автопроверкам). Я разделил их [тегами](https://docs.ansible.com/ansible/latest/user_guide/playbooks_tags.html):

С тегом `setup` крутятся роли `geerlingguy.pip` и `geerlingguy.docker` — ставится pip-пакет `docker` и сам Docker Engine. Запуск: `make prepare-servers` или `ansible-playbook playbook.yml --tags setup`. Здесь почти наверняка понадобится `sudo` (в плейбуке `become: true`).

С тегом `deploy` серверы «не трогаем» в смысле установки пакетов — только приложение: через [модуль template](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html) собираются env-файлы и `infra/nginx/nginx.conf`, генерируется сертификат под домен из `redmine_domain`, затем в каталоге `infra/` выполняется `docker-compose down` и `docker-compose up -d`. Это `make deploy` или `ansible-playbook playbook.yml --tags deploy`.

Первый запуск Redmine после смены образа иногда тянется до минуты — там миграции БД. Если сразу после деплоя nginx отдаёт 502, подождите немного и обновите страницу.

## Переменные и инвентарь

Основные вещи лежат в `group_vars/webservers.yml`: `redmine_port` (по умолчанию 3000 — это порт Redmine внутри контейнера и то, куда смотрит upstream в nginx) и `redmine_domain` (имя для сертификата и `server_name`). Для `SECRET_KEY_BASE` у каждого хоста свои значения в `host_vars/web1.yml` и `host_vars/web2.yml` — на проде их, конечно, лучше заменить на что-то случайное.

В `inventory.ini` группа `webservers` с алиасами `web1` и `web2`. Для настоящих серверов имеет смысл прописать их IP, `ansible_connection=ssh` и пользователя деплоя с ключом.

## Make-цели, которыми я пользуюсь

`make prepare-servers` — Galaxy и только `setup`.  
`make deploy` — только деплой приложения.  
`make up` и `make down` — просто поднять или остановить compose в `infra/`, если конфиги уже сгенерированы деплоем.  
`make dns-test` — быстро глянуть, что DNS отвечает и что по HTTPS что-то отдаётся.

Порядок у меня обычно такой: сначала `make prepare-servers`, потом `make deploy`.

## Имена и DNS на локалке

Как прописать хосты и как проверить резолв, расписано в `infra/LOCAL_DOMAIN.txt`. Для ручной проверки HTTPS можно так: `curl -skI -H "Host: devops.example" https://127.0.0.1/`.
