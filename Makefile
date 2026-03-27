.PHONY: up down logs ps

up:
	cd infra && test -f .env || cp .env.example .env
	cd infra && docker-compose up -d

down:
	cd infra && docker-compose down

logs:
	cd infra && docker-compose logs -f

ps:
	cd infra && docker-compose ps
