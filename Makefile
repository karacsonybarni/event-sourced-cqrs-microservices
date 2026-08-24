.PHONY: build test up down smoke logs clean

build:
	./mvnw clean verify

test:
	./mvnw test

up:
	./mvnw -DskipTests package
	docker compose up --build -d --wait

down:
	docker compose down --volumes --remove-orphans

smoke:
	./scripts/smoke-test.sh

logs:
	docker compose logs -f api-gateway order-command-service order-query-service debezium

clean:
	./mvnw clean
