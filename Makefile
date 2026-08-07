.PHONY: docker-build docker-up docker-down

docker-build:
	docker compose build

docker-up:
	docker compose up -d

docker-down:
	docker compose down
