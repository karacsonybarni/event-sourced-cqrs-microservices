#!/usr/bin/env bash
set -Eeuo pipefail
reader="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/read-log-directory.sh"

for directory in /tmp/kafka-logs /custom/data; do
  response="$(jq -nc --arg path "${directory}" '{brokers:[{broker:1,logDirs:[{error:null,logDir:$path}]}]}')"
  actual="$(printf 'Querying brokers\nReceived log directory information\n%s\n' "${response}" | bash "${reader}")"
  [[ "${actual}" == "${directory}" ]]
done

for response in \
  '' \
  '{"brokers":[]}' \
  '{"brokers":[{"broker":2,"logDirs":[{"error":null,"logDir":"/data"}]}]}' \
  '{"brokers":[{"broker":1,"logDirs":[]}]}' \
  '{"brokers":[{"broker":1,"logDirs":[{"error":"offline","logDir":"/data"}]}]}' \
  '{"brokers":[{"broker":1,"logDirs":[{"error":null,"logDir":"/one"},{"error":null,"logDir":"/two"}]}]}' \
  '{"brokers":[{"broker":1,"logDirs":[{"error":null,"logDir":"/"}]}]}' \
  '{"brokers":[{"broker":1,"logDirs":[{"error":null,"logDir":"relative"}]}]}'; do
  if printf '%s\n' "${response}" | bash "${reader}" >/dev/null 2>&1; then
    echo "Accepted invalid log directory response: ${response}" >&2
    exit 1
  fi
done
echo 'Kafka log-directory discovery tests passed'
