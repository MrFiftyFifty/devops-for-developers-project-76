.PHONY: up down logs ps dns-test prepare-servers deploy

up:
	cd infra && test -f .env || cp .env.example .env
	cd infra && docker-compose up -d

down:
	cd infra && docker-compose down

logs:
	cd infra && docker-compose logs -f

ps:
	cd infra && docker-compose ps

dns-test:
	@command -v dig >/dev/null && dig @127.0.0.1 -p 5353 devops.example A +short || true
	@command -v dig >/dev/null && dig @127.0.0.1 -p 5353 example.local A +short || true
	@curl -sk -o /dev/null -w "HTTPS devops.example: %{http_code}\n" -H "Host: devops.example" https://127.0.0.1/

prepare-servers:
	ansible-galaxy role install -r requirements.yml -p roles
	ansible-galaxy collection install -r requirements.yml -p collections
	ansible-playbook playbook.yml --tags setup

deploy:
	ansible-playbook playbook.yml --tags deploy
