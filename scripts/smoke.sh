#!/usr/bin/env bash
# Smoke test the running stack. Run after `docker compose up -d` from the repo.
#
#   1. Wait for every service to answer (up to SMOKE_WAIT seconds, default 180).
#   2. Listen on MQTT topic `birdnet` for SMOKE_LISTEN seconds (default 120)
#      and print each detection.
#
# Needs: docker compose, curl, jq. mosquitto_sub runs inside the mosquitto
# container, so the host does not need the mosquitto clients.
# Exit: 0 all services answered, 1 a service did not answer, 2 setup error.
# Zero detections is not a failure (it may be night, or quiet).

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

host="${SMOKE_HOST:-localhost}"
wait_s="${SMOKE_WAIT:-180}"
listen_s="${SMOKE_LISTEN:-120}"

die() { echo "error: $*" >&2; exit 2; }

for bin in docker curl jq; do
  command -v "$bin" >/dev/null || die "$bin not found in PATH"
done
docker compose ps --status running --services >/dev/null 2>&1 \
  || die "docker compose cannot reach the daemon or read docker-compose.yml"

# name|kind|target   kind is http (any 2xx/3xx) or mqtt
checks=(
  "frigate|http|http://${host}:5000/api/version"
  "birdnet-go|http|http://${host}:8090/api/v2/health"
  "fugleramme|http|http://${host}:8080/"
  "yawamf|http|http://${host}:9852/"
  "mosquitto|mqtt|\$SYS/#"
)

check_one() {
  local kind="$1" target="$2"
  case "$kind" in
    http)
      curl -fsS -o /dev/null --connect-timeout 2 --max-time 5 "$target" 2>/dev/null
      ;;
    mqtt)
      docker compose exec -T mosquitto \
        mosquitto_sub -h localhost -C 1 -W 15 -t "$target" >/dev/null 2>&1
      ;;
  esac
}

echo "waiting up to ${wait_s}s for services on ${host}"
deadline=$((SECONDS + wait_s))
pending=("${checks[@]}")
while ((${#pending[@]})); do
  still=()
  for entry in "${pending[@]}"; do
    IFS='|' read -r name kind target <<<"$entry"
    if check_one "$kind" "$target"; then
      echo "  ok    ${name}  (${target})"
    else
      still+=("$entry")
    fi
  done
  pending=(${still[@]+"${still[@]}"})
  ((${#pending[@]})) || break
  if ((SECONDS >= deadline)); then
    echo >&2
    echo "FAIL: not answering after ${wait_s}s:" >&2
    for entry in "${pending[@]}"; do
      IFS='|' read -r name kind target <<<"$entry"
      state="$(docker compose ps --all --format '{{.State}} {{.Status}}' "$name" 2>/dev/null || true)"
      echo "  ${name}: ${target}  [container: ${state:-not created}]" >&2
      echo "    last log lines:" >&2
      docker compose logs --no-log-prefix --tail 5 "$name" 2>&1 | sed 's/^/      /' >&2 || true
    done
    exit 1
  fi
  sleep 5
done

echo
echo "listening on MQTT topic birdnet for ${listen_s}s"
count=0
# mosquitto_sub -W exits non-zero when the timeout ends the run; that is expected.
while IFS= read -r line; do
  if summary="$(jq -r '"\(.Date // "?") \(.Time // "?")  \(.CommonName // "?") (\(.ScientificName // "?"))  conf=\(.Confidence // "?")  source=\(.sourceName // "?")  id=\(.detectionId // "?")"' <<<"$line" 2>/dev/null)"; then
    count=$((count + 1))
    echo "  ${summary}"
  else
    echo "  (not JSON) ${line}"
  fi
done < <(docker compose exec -T mosquitto \
  mosquitto_sub -h localhost -t birdnet -W "$listen_s" 2>/dev/null || true)

echo "${count} detection(s) in ${listen_s}s"
echo "all services answered"
