.PHONY: build test up down smoke scale-smoke cloud-config cloud-provision cloud-destroy logs clean

build:
	./mvnw clean verify

test:
	./mvnw test

up:
	./mvnw -DskipTests package
	docker compose up --build -d --wait --scale order-command-service=2 --scale order-query-service=2

down:
	docker compose down --volumes --remove-orphans

smoke:
	EXPECTED_COMMAND_INSTANCES=2 EXPECTED_QUERY_INSTANCES=2 ./scripts/smoke-test.sh

scale-smoke:
	./scripts/scaling-test.sh

cloud-config:
	COMMAND_DB_PASSWORD=validation \
	QUERY_DB_PASSWORD=validation \
	AWS_REGION=eu-central-1 \
	CLOUDWATCH_LOG_GROUP=/validation/containers \
		docker compose --file compose.yml --file compose.cloud.yml config --quiet

cloud-provision:
	./scripts/aws/provision.sh

cloud-destroy:
	./scripts/aws/destroy-runtime.sh

logs:
	docker compose logs -f discovery-server api-gateway order-command-service order-query-service debezium

clean:
	./mvnw clean
