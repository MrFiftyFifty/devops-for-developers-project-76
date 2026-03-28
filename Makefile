.PHONY: up down logs ps dns-test prepare-servers deploy monitoring vault-edit vault-view

VAULT_OPT := $(shell test -f .vault_pass && printf '%s' '--vault-password-file .vault_pass')

up:
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
	ansible-playbook playbook.yml --tags setup $(VAULT_OPT)

deploy:
	ansible-playbook playbook.yml --tags deploy $(VAULT_OPT)

monitoring:
	ansible-playbook playbook.yml --tags monitoring $(VAULT_OPT)

vault-edit:
	ansible-vault edit group_vars/webservers/vault.yml $(VAULT_OPT)

vault-view:
	ansible-vault view group_vars/webservers/vault.yml $(VAULT_OPT)
