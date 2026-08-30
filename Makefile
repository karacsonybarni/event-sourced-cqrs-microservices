.PHONY: build test up down smoke ui-smoke scale-smoke kubernetes-validate cloud-config cloud-provision cloud-destroy logs clean

build:
	./mvnw clean verify

test:
	./mvnw test

up:
	./scripts/local/runtime-up.sh

down:
	./scripts/local/runtime-down.sh

smoke:
	EXPECTED_COMMAND_INSTANCES=2 EXPECTED_QUERY_INSTANCES=2 EXPECTED_INVENTORY_INSTANCES=1 ./scripts/smoke-test.sh

ui-smoke:
	./scripts/ui-smoke-test.sh
	GATEWAY_URL=http://localhost:3000 VERIFY_PLATFORM=false ./scripts/smoke-test.sh

scale-smoke:
	./scripts/scaling-test.sh

kubernetes-validate:
	./scripts/validate-kubernetes.sh

cloud-config:
	COMMAND_DB_PASSWORD=validation \
	QUERY_DB_PASSWORD=validation \
	INVENTORY_DB_PASSWORD=validation \
	AWS_REGION=eu-central-1 \
	CLOUDWATCH_LOG_GROUP=/validation/containers \
		docker compose --file compose.yml --file compose.cloud.yml config --quiet

cloud-provision:
	./scripts/aws/provision.sh

cloud-destroy:
	./scripts/aws/destroy-runtime.sh

logs:
	docker compose --profile ui logs -f frontend discovery-server api-gateway order-command-service inventory-service order-projection-worker order-query-service debezium

clean:
	./mvnw clean
