# Contributing

## Local checks

Run before opening a pull request:

```bash
./mvnw clean verify
docker compose config --quiet
make up
make smoke
make down
```

Keep domain-event changes backward compatible. Use a new event type version for breaking changes and add projection tests for duplicate delivery, ordering, and replay behavior.

Never commit real credentials. Values embedded in Compose are local-only defaults; local overrides, private keys, and `secrets/` directories are excluded from both Git and AI-assisted inspection.
