.PHONY: up down logs ps dns-test

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
	@curl -s -o /dev/null -w "HTTP devops.example: %{http_code}\n" -H "Host: devops.example" http://127.0.0.1/
