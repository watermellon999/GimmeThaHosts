#!/usr/bin/env bash

set -u
set -o pipefail

OUT="hosts.blocked"
TMP="$(mktemp -d)"
SOURCES="sources.txt"
WHITELIST="whitelist.txt"
LOG="hosts-build.log"

trap 'rm -rf "$TMP"' EXIT

log() {
  printf "[%s] %s\n" "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2
}

fetch() {
  local src="$1" dst="$2"

  if [[ "$src" =~ ^https?:// ]]; then
    if ! curl -fLs --connect-timeout 10 --max-time 60 "$src" -o "$dst"; then
      log "WARN: failed to fetch $src"
      return 1
    fi
  else
    if ! cp "$src" "$dst" 2>/dev/null; then
      log "WARN: failed to read local file $src"
      return 1
    fi
  fi

  log "OK: fetched $src"
  return 0
}

normalize() {
  sed -E '
    s/#.*$//;
    s/^[[:space:]]+//;
    s/[[:space:]]+$//;
    /^$/d;
    s/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]+//;
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/d;
    s/\r$//;
  '
}

extract_domains() {
  grep -Eo '([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}'
}

> "$TMP/all.domains"
fetched=0

while read -r src || [[ -n "$src" ]]; do
  [[ -z "$src" || "$src" =~ ^# ]] && continue

  file="$TMP/$(basename "$src")"
  if fetch "$src" "$file"; then
    normalize < "$file" | extract_domains >> "$TMP/all.domains"
    fetched=$((fetched + 1))
  fi
done < "$SOURCES"

if [[ "$fetched" -eq 0 ]]; then
  log "ERROR: no sources could be fetched"
  exit 1
fi

log "INFO: processed $fetched source(s)"

sort -u "$TMP/all.domains" > "$TMP/unique.domains"

# Whitelist removal (including subdomains)
if [[ -f "$WHITELIST" ]]; then
  log "INFO: applying whitelist"
  awk '
    NR==FNR { wl[$1]=1; next }
    {
      d=$1
      should_skip=0
      
      # Check exact match
      if (d in wl) should_skip=1
      
      # Check parents (if parent is whitelisted, child is whitelisted)
      p=d
      while (should_skip == 0 && sub(/^[^.]+\./, "", p)) {
        if (p in wl) {
          should_skip=1
        }
      }
      
      if (should_skip == 0) print d
    }
  ' "$WHITELIST" "$TMP/unique.domains" > "$TMP/filtered.domains"
else
  log "INFO: no whitelist found"
  cp "$TMP/unique.domains" "$TMP/filtered.domains"
fi

# MODIFIED SECTION:
# Simply sort the list. Do not collapse subdomains.
log "INFO: sorting final list"
sort "$TMP/filtered.domains" > "$TMP/final.domains"

{
  echo "127.0.0.1 localhost"
  echo "127.0.0.1 local"
  echo "127.0.0.1 localhost.localdomain"
  echo "::1 localhost"
  echo "::1 ip6-localhost"
  echo "::1 ip6-loopback"
  echo "255.255.255.255 broadcasthost"
  echo "fe80::1%lo0 localhost"
  echo "ff00::0 ip6-localnet"
  echo "ff00::0 ip6-mcastprefix"
  echo "ff02::1 ip6-allnodes"
  echo "ff02::2 ip6-allrouters"
  echo "ff02::3 ip6-allhosts"
  echo "0.0.0.0 0.0.0.0"
  echo
  echo "# Blocked domains"
  while read -r d; do
    printf "0.0.0.0 %s\n" "$d"
  done < "$TMP/final.domains"
} > "$OUT"

log "DONE: generated $OUT with $(wc -l < "$TMP/final.domains") domains"
