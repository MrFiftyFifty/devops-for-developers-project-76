### Hexlet tests and linter status:
[![Actions Status](https://github.com/MrFiftyFifty/devops-for-developers-project-76/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/MrFiftyFifty/devops-for-developers-project-76/actions/workflows/hexlet-check.yml)

Учебный проект по DevOps: поднимаем стек в Docker Compose и готовим «сервера» через Ansible. Облако в репозитории не зашито — инвентарь заточен под локальную отладку, но его же можно подставить под настоящие машины, если поменять хосты и способ подключения.

## Что понадобится

Ansible (или `ansible-core`), Python 3 и `make`. Роли и коллекции тянутся через `ansible-galaxy`; пути к ним прописаны в `ansible.cfg`, ставятся в каталоги `roles/` и `collections/` рядом с проектом (их нет в git — подтягиваются командой ниже).

Сначала зависимости Galaxy:

```bash
ansible-galaxy role install -r requirements.yml -p roles
ansible-galaxy collection install -r requirements.yml -p collections
```

Или короче:

```bash
make prepare-servers
```

Эта цель ставит роли `geerlingguy.pip` и `geerlingguy.docker`, коллекцию `community.docker` и сразу гоняет `playbook.yml`. Плейбук нацелен на `hosts: all` и подтягивает переменные для группы `webservers` из `group_vars/`. Через pip ставится пакет `docker` — он нужен Ansible для работы с Docker через модули. Сам Docker Engine ставит роль `geerlingguy.docker`.

Про смысл конфигурации «как код» есть короткий [гайд Хекслета](https://guides.hexlet.io/ru/configuration-management/). [Документация Ansible](https://docs.ansible.com/ansible/latest/index.html) и коллекция [community.docker](https://docs.ansible.com/ansible/latest/collections/community/docker/index.html) обычно открываются по мере того, как плейбук разрастается.

Запуск с повышением прав (`become: true`) обычно требует `sudo`. Если система просит пароль, варианты такие: `NOPASSWD` для пользователя, под которым идёт Ansible, или разовый запуск `ansible-playbook` с ключом `-K`.

## Инвентарь

В `inventory.ini` лежит группа `webservers`: два алиаса, `web1` и `web2`, оба смотрят на `127.0.0.1`, подключение `local`, пользователь в инвентаре указан как `deploy`. Так можно имитировать два сервера на одной машине. На проде имеет смысл прописать реальные IP в `ansible_host`, перейти на `ansible_connection=ssh`, выдать доступ по ключу и заранее создать пользователя `deploy` с рабочим `sudo` — иначе плейбук упрётся в права.

Если нужно сразу пускать кого-то в группу `docker`, смотри переменные роли [geerlingguy.docker на Galaxy](https://galaxy.ansible.com/ui/standalone/roles/geerlingguy/docker/).

## Docker Compose

Локальный балансировщик, заглушки приложений, Postgres и DNS-сервис лежат в `infra/`. Поднять:

```bash
make up
```

Остановить — `make down`. Быстрая проверка резолва и ответа по HTTP: `make dns-test`. Детали по именам вроде `devops.example` — в `infra/LOCAL_DOMAIN.txt`.
