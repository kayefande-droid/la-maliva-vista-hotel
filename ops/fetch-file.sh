#!/usr/bin/env bash
# Resumable, retrying download for unreliable connections.
#
# This network drops roughly half of its TLS connections (see
# docs/NETWORK_FIXES.md), so a single `curl` call dies part-way through a large
# file. This loop resumes from where it stopped instead of starting over, and
# gives up only after real, repeated lack of progress.
#
# Usage:
#   ops/fetch-file.sh <url> <output-path> [expected-bytes] [max-attempts]
#
# Exit codes: 0 = complete file, 1 = gave up / wrong size.

set -uo pipefail

URL="${1:?usage: fetch-file.sh <url> <output-path> [expected-bytes] [max-attempts]}"
OUT="${2:?usage: fetch-file.sh <url> <output-path> [expected-bytes] [max-attempts]}"
EXPECTED="${3:-0}"
MAX_ATTEMPTS="${4:-400}"

mkdir -p "$(dirname "$OUT")"

size() { stat -c %s "$OUT" 2>/dev/null || echo 0; }

attempt=0
stalled=0
last=0

while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  attempt=$((attempt + 1))
  have=$(size)

  if [ "$EXPECTED" -gt 0 ] && [ "$have" -ge "$EXPECTED" ]; then
    break
  fi

  # -C - resumes; --max-time bounds a wedged socket so the loop can retry.
  curl -L -C - --retry 3 --retry-all-errors --retry-delay 1 \
       --connect-timeout 10 --max-time 180 \
       -o "$OUT" "$URL" >/dev/null 2>&1

  now=$(size)
  if [ "$now" -le "$last" ]; then
    stalled=$((stalled + 1))
    # Three consecutive attempts with no forward progress means the server or
    # the route is refusing us; stop rather than spin forever.
    if [ "$stalled" -ge 3 ]; then
      printf 'stalled at %s bytes after %s attempts\n' "$now" "$attempt" >&2
      return_code=1
      break
    fi
    sleep $((stalled * 3))
  else
    stalled=0
    printf '\r%8s / %8s bytes (attempt %s)   ' "$now" "$EXPECTED" "$attempt" >&2
  fi
  last="$now"
done

final=$(size)
printf '\n' >&2

if [ "$EXPECTED" -gt 0 ] && [ "$final" -ne "$EXPECTED" ]; then
  printf 'INCOMPLETE: %s of %s bytes\n' "$final" "$EXPECTED" >&2
  exit 1
fi

printf 'OK: %s (%s bytes)\n' "$OUT" "$final"
exit 0
