#!/usr/bin/env bash

set -u
set -o pipefail

OUT="hosts.blocked"
TMP="$(mktemp -d)"
SOURCES="sources.txt"
WHITELIST="whitelist.txt"
BLACKLIST="blacklist.txt"
LOG="hosts-build.log"
ARCHIVE="./archive"
OFFLINE=0

mkdir -p "$ARCHIVE"

trap 'rm -rf "$TMP"' EXIT

log() {
  printf "[%s] %s\n" "$(date '+%F %T')" "$*" | tee -a "$LOG" >&2
}

###############################################################################
# fetch():
# - Supports HTTP(S) and local files
# - Archives remote sources using SHA256(url) as filename
# - Validation order:
#   1) Prefer ETag (If-None-Match, 304 = unchanged)
#   2) Fallback to Content-Length comparison (only if no ETag available)
#   3) If neither available → always fetch
# - If fetch fails → fall back to archive if available
#   --offline => never touch the network; use archive if present.
###############################################################################
fetch() {
  local src="$1" dst="$2"

  if [[ "$src" =~ ^https?:// ]]; then
    local hash archive_file etag_file size_file
    local headers etag remote_size local_size http_code

    # Hash URL to generate deterministic archive filenames
    hash="$(printf "%s" "$src" | sha256sum | awk '{print $1}')"
    archive_file="$ARCHIVE/$hash"
    etag_file="$ARCHIVE/$hash.etag"
    size_file="$ARCHIVE/$hash.size"

    ###########################################################################
    # OFFLINE: use archive only, never wait on network
    ###########################################################################
    if (( OFFLINE )); then
      if [[ -f "$archive_file" ]]; then
        cp "$archive_file" "$dst"
        log "OK: [offline] using archived copy for $src"
        return 0
      fi
      log "WARN: [offline] no archive for $src, skipping"
      return 1
    fi

    ###########################################################################
    # Headers (single request) — portable header value extraction
    ###########################################################################
    headers="$(curl -fsI "$src" 2>/dev/null || true)"

    etag="$(printf "%s\n" "$headers" \
      | awk 'tolower($0) ~ /^etag:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' \
      | tr -d '\r')"

    remote_size="$(printf "%s\n" "$headers" \
      | awk 'tolower($0) ~ /^content-length:/ { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' \
      | tr -d '\r')"

    ###########################################################################
    # 1) ETag validation
    ###########################################################################
    if [[ -n "$etag" && -f "$etag_file" && -f "$archive_file" ]]; then
      http_code="$(curl -sS -o /dev/null -w '%{http_code}' \
        -H "If-None-Match: $(cat "$etag_file")" "$src" 2>/dev/null || true)"
      if [[ "$http_code" == "304" ]]; then
        log "OK: using cached archive (ETag match) for $src"
        cp "$archive_file" "$dst"
        return 0
      fi
    fi

    ###########################################################################
    # 2) Size-based validation (fallback) — only when no ETag available,
    #    so a changed ETag is never silently served stale from archive.
    ###########################################################################
    if [[ -z "$etag" && -n "$remote_size" && -f "$archive_file" ]]; then
      local_size="$(stat -c%s "$archive_file" 2>/dev/null || true)"
      if [[ "$local_size" == "$remote_size" ]]; then
        log "OK: using cached archive (size match) for $src"
        cp "$archive_file" "$dst"
        return 0
      fi
    fi

    ###########################################################################
    # 3) Fetch
    ###########################################################################
    local rc=0
    # aria2c writes directly to $dst; use --allow-overwrite so re-runs work.
    aria2c \
      --no-conf \
      --no-netrc=true \
      --allow-overwrite=true \
      --auto-file-renaming=false \
      --connect-timeout=10 \
      --timeout=60 \
      --max-tries=3 \
      --retry-wait=2 \
      --dir="$(dirname -- "$dst")" \
      --out="$(basename -- "$dst")" \
      "$src" 1>/dev/null 2>&1 || rc=$?

    if [[ $rc -eq 0 && -s "$dst" ]]; then
      if cp "$dst" "$archive_file"; then
        [[ -n "$etag" ]]        && printf "%s" "$etag"        > "$etag_file"
        [[ -n "$remote_size" ]] && printf "%s" "$remote_size" > "$size_file"
        log "OK: fetched $src"
        return 0
      else
        log "WARN: failed to archive $src (continuing with downloaded file)"
        return 0
      fi
    fi

    log "WARN: failed to fetch $src (aria2c rc=$rc)"
    if [[ -f "$archive_file" ]]; then
      log "INFO: using archived copy for $src"
      cp "$archive_file" "$dst"
      return 0
    fi
    return 1
  else
    if cp "$src" "$dst" 2>/dev/null; then
      log "OK: read local file $src"
      return 0
    else
      log "WARN: failed to read local file $src"
      return 1
    fi
  fi
}

###############################################################################
# normalize():
# - Removes comments (# or //)
# - Trims whitespace
# - Removes IP prefixes (0.0.0.0 / 127.0.0.1)
# - Drops raw IP-only lines
# - Skips blank or malformed lines safely
###############################################################################
normalize() {
  sed -E '
    s@(//|#).*@@;                     # remove comments
    s/^[[:space:]]+//;                # trim leading whitespace
    s/[[:space:]]+$//;                # trim trailing whitespace
    /^$/d;                            # drop empty lines
    s/^(0\.0\.0\.0|127\.0\.0\.1)[[:space:]]+//;
    /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/d;
    s/\r$//;
  '
}

###############################################################################
# extract_domains():
# Regex explanation:
# ([a-zA-Z0-9-]+\.)+   -> one or more domain labels ending with a dot
# [a-zA-Z]{2,}        -> TLD (min length 2)
###############################################################################
extract_domains() {
  grep -Eo '([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}'
}

###############################################################################
# Parse CLI args
###############################################################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    --offline) OFFLINE=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--offline]"; exit 0 ;;
    *) log "ERROR: unknown argument: $1"; exit 2 ;;
  esac
done

###############################################################################
# Dependency check (only when we may actually download)
###############################################################################
if (( OFFLINE == 0 )) && ! command -v aria2c >/dev/null 2>&1; then
  log "ERROR: aria2c not found in PATH"
  exit 1
fi

###############################################################################
# Blacklist
###############################################################################
> "$TMP/all.domains"

if [[ -f "$BLACKLIST" ]]; then
  log "INFO: loading blacklist"
  normalize < "$BLACKLIST" | extract_domains >> "$TMP/all.domains"
fi

###############################################################################
# Sources
###############################################################################
fetched=0
while read -r src || [[ -n "$src" ]]; do
  [[ -z "$src" || "$src" =~ ^[[:space:]]*(#|//) ]] && continue

  # Hashed temp name avoids collisions between sources sharing a basename
  file="$TMP/src.$(printf "%s" "$src" | sha256sum | awk '{print $1}')"
  if fetch "$src" "$file"; then
    normalize < "$file" | extract_domains >> "$TMP/all.domains"
    fetched=$((fetched + 1))
  fi
done < "$SOURCES"

if [[ "$fetched" -eq 0 && ! -f "$BLACKLIST" ]]; then
  log "ERROR: no sources or blacklist could be processed"
  exit 1
fi

log "INFO: processed $fetched source(s)"

LC_ALL=C sort -u "$TMP/all.domains" > "$TMP/unique.domains"

###############################################################################
# Whitelist: exact + regex
#   IMPORTANT: split regex lines BEFORE normalize/extract so anchors survive.
###############################################################################
if [[ -f "$WHITELIST" ]]; then
  log "INFO: applying whitelist (exact + regex support)"

  # Separate exact domains (normalized) from raw regex patterns
  normalize < "$WHITELIST" \
    | grep -v '^regex:' \
    | extract_domains > "$TMP/wl.exact" || true

  grep -E '^[[:space:]]*regex:' "$WHITELIST" \
    | sed -E 's/^[[:space:]]*regex:[[:space:]]*//; s/[[:space:]]+$//; s/\r$//' \
    > "$TMP/wl.regex" || true

  awk -v exactfile="$TMP/wl.exact" -v regexfile="$TMP/wl.regex" '
    BEGIN {
      while ((getline line < exactfile) > 0) { if (line != "") exact[line]=1 }
      close(exactfile)
      r=0
      while ((getline line < regexfile) > 0) {
        if (line != "") regex[++r]=line
      }
      close(regexfile)
    }
    {
      domain=$1
      if (domain in exact) next
      for (i=1;i<=r;i++) if (domain ~ regex[i]) next
      print domain
    }
  ' "$TMP/unique.domains" > "$TMP/filtered.domains"
else
  log "INFO: no whitelist found"
  cp "$TMP/unique.domains" "$TMP/filtered.domains"
fi

###############################################################################
# Final sort
###############################################################################
log "INFO: sorting final list"
LC_ALL=C sort "$TMP/filtered.domains" > "$TMP/final.domains"

###############################################################################
# Generate hosts file
###############################################################################
{
  if [[ -f headers.txt ]]; then
    cat headers.txt
  fi
  echo
  echo "# Blocked domains"
  while read -r d; do
    printf "0.0.0.0 %s\n" "$d"
  done < "$TMP/final.domains"
} > "$OUT"

log "DONE: generated $OUT with $(wc -l < "$TMP/final.domains") domains"

###############################################################################
# Prompt before replacing /etc/hosts
###############################################################################
read -rp "Replace /etc/hosts with generated file? [y/N]: " ans || true
if [[ "${ans:-}" =~ ^[Yy]$ ]]; then
  if [[ $EUID -ne 0 ]]; then
    log "INFO: escalating privileges"
    sudo cp "$OUT" /etc/hosts
  else
    cp "$OUT" /etc/hosts
  fi
  log "INFO: /etc/hosts updated"
else
  log "INFO: /etc/hosts not modified"
fi