#!/usr/bin/env bash
set -Eeuo pipefail

# kafka-log-dirs prints two informational lines before its JSON response.
# Fail closed on missing/ambiguous brokers, offline storage, or multiple paths.
sed -n '/^{/,$p' | jq -ers '
  if length == 1 and (.[0].brokers | length) == 1 then .[0].brokers[0]
  else error("Expected one broker log-directory response") end
  | if .broker == 1 and (.logDirs | length) == 1 then .logDirs[0]
    else error("Expected exactly one log directory for broker 1") end
  | if .error == null and (.logDir | type) == "string"
       and (.logDir | startswith("/")) and .logDir != "/"
       and (.logDir | test("[\\r\\n]") | not) then .logDir
    else error("Kafka log directory is unavailable or invalid") end
'
