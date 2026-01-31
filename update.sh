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
#   2) Fallback to Content-Length comparison
#   3) If neither available → always fetch
# - If fetch fails → fall back to archive if available
###############################################################################
fetch() {
  local src="$1" dst="$2"

  if [[ "$src" =~ ^https?:// ]]; then
    local hash archive_file etag_file size_file
    local headers etag remote_size local_size

    # Hash URL to generate deterministic archive filenames
    hash="$(printf "%s" "$src" | sha256sum | awk '{print $1}')"
    archive_file="$ARCHIVE/$hash"
    etag_file="$ARCHIVE/$hash.etag"
    size_file="$ARCHIVE/$hash.size"

    # Fetch headers once (used for both ETag and size detection)
    headers="$(curl -fsI "$src" 2>/dev/null || true)"

    # Extract ETag if present
    etag="$(printf "%s\n" "$headers" \
      | awk -F': ' 'tolower($1)=="etag"{print $2}' \
      | tr -d '\r')"

    # Extract Content-Length if present
    remote_size="$(printf "%s\n" "$headers" \
      | awk -F': ' 'tolower($1)=="content-length"{print $2}' \
      | tr -d '\r')"

    ###########################################################################
    # 1) ETag validation (preferred)
    ###########################################################################
    if [[ -n "$etag" && -f "$etag_file" && -f "$archive_file" ]]; then
      if curl -fsI -H "If-None-Match: $(cat "$etag_file")" "$src" \
        | grep -q "304 Not Modified"; then
        log "OK: using cached archive (ETag match) for $src"
        cp "$archive_file" "$dst"
        return 0
      fi
    fi

    ###########################################################################
    # 2) Size-based validation (fallback)
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
    # 3) Fetch (mandatory if validation unavailable or failed)
    ###########################################################################
    if curl -fLs --connect-timeout 10 --max-time 60 "$src" -o "$dst"; then
      cp "$dst" "$archive_file"
      [[ -n "$etag" ]] && printf "%s" "$etag" > "$etag_file"
      [[ -n "$remote_size" ]] && printf "%s" "$remote_size" > "$size_file"
      log "OK: fetched $src"
      return 0
    else
      log "WARN: failed to fetch $src"
      if [[ -f "$archive_file" ]]; then
        log "INFO: using archived copy for $src"
        cp "$archive_file" "$dst"
        return 0
      fi
      return 1
    fi
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
# Load blacklist first (highest priority)
###############################################################################
> "$TMP/all.domains"

if [[ -f "$BLACKLIST" ]]; then
  log "INFO: loading blacklist"
  normalize < "$BLACKLIST" | extract_domains >> "$TMP/all.domains"
fi

###############################################################################
# Process sources.txt (supports blank lines and comments)
###############################################################################
fetched=0
while read -r src || [[ -n "$src" ]]; do
  [[ -z "$src" || "$src" =~ ^[[:space:]]*(#|//) ]] && continue

  file="$TMP/$(basename "$src")"
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

sort -u "$TMP/all.domains" > "$TMP/unique.domains"

###############################################################################
# Whitelist filtering:
# IMPORTANT CHANGE:
# - Whitelist now matches ONLY exact domains
# - Subdomains are NOT removed unless explicitly listed
###############################################################################
if [[ -f "$WHITELIST" ]]; then
  log "INFO: applying whitelist (exact match only)"
  awk '
    NR==FNR { wl[$1]=1; next }
    {
      if (!($1 in wl)) print $1
    }
  ' <(normalize < "$WHITELIST" | extract_domains) "$TMP/unique.domains" > "$TMP/filtered.domains"
else
  log "INFO: no whitelist found"
  cp "$TMP/unique.domains" "$TMP/filtered.domains"
fi

###############################################################################
# Final sorting (no subdomain collapsing)
###############################################################################
log "INFO: sorting final list"
sort "$TMP/filtered.domains" > "$TMP/final.domains"

###############################################################################
# Generate hosts file
###############################################################################
{
  cat headers.txt
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
read -rp "Replace /etc/hosts with generated file? [y/N]: " ans
if [[ "$ans" =~ ^[Yy]$ ]]; then
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

