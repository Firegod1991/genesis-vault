#!/usr/bin/env bash
# The two smaller parts of a release: the world overview map and the public domain scripture bundle.
#
#   extras.sh map         cut zoom 0 to 6 of the whole world from the newest Protomaps build
#   extras.sh scripture   gather every public domain Bible translation in the Genesis catalog
#
# Reads  OUT (results), GENESIS (checkout), GENESIS_VAULT (scratch vault), NOTE (facts file, optional),
#        REHEARSAL_URL (set during a rehearsal), MAP_MAXZOOM, SCRIPTURE_LIMIT and SCRIPTURE_MIN (optional).
set -euo pipefail

: "${OUT:?set OUT to the results folder}" "${GENESIS:?set GENESIS to a Genesis checkout}" "${GENESIS_VAULT:?set GENESIS_VAULT to a scratch vault}"
export GENESIS_VAULT
mkdir -p "$OUT"
fact() { echo "$1"; if [ -n "${NOTE:-}" ]; then echo "$1" >> "$NOTE"; fi; }
bytes() { stat -c %s "$1" 2>/dev/null || echo 0; }

case "${1:-}" in
  map)
    cd "$GENESIS"
    started=$SECONDS
    python3 -m genesis maps world --maxzoom "${MAP_MAXZOOM:-6}"
    mv "$GENESIS_VAULT/maps/world_overview.pmtiles" "$OUT/world_overview.pmtiles"
    fact "map_seconds=$((SECONDS - started))"
    fact "world_overview_bytes=$(bytes "$OUT/world_overview.pmtiles")"
    [ "$(bytes "$OUT/world_overview.pmtiles")" -gt 100000 ] || { echo "The map came out almost empty."; exit 1; }
    ;;

  scripture)
    cd "$GENESIS"
    # A rehearsal takes a handful of translations. A real build takes them all (limit 0).
    limit="${SCRIPTURE_LIMIT:-$([ -n "${REHEARSAL_URL:-}" ] && echo 6 || echo 0)}"
    mapfile -t ids < <(python3 -c "
import json, sys
lock = json.load(open('catalog/lock/scripture.json'))['items']
ids = [k for k, e in sorted(lock.items()) if e.get('license') == 'Public domain' and e.get('files')]
limit = int(sys.argv[1])
print('\n'.join(ids[:limit] if limit else ids))" "$limit")
    [ "${#ids[@]}" -gt 0 ] || { echo "The catalog lists no public domain scripture."; exit 1; }
    fact "scripture_listed=${#ids[@]}"
    # At least half must arrive. Fewer means the source is down, not that a few files moved.
    least="${SCRIPTURE_MIN:-$(( ${#ids[@]} / 2 ))}"
    args=()
    for id in "${ids[@]}"; do args+=(--id "$id"); done
    started=$SECONDS
    # One translation that will not download must not sink the whole bundle.
    python3 -m genesis fetch "${args[@]}" --yes --keep-going || true
    count="$(find "$GENESIS_VAULT/scripture" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    fact "scripture_seconds=$((SECONDS - started))"
    fact "scripture_translations=$count"
    if [ "$count" -lt "$least" ] || [ "$count" -eq 0 ]; then
      echo "Only $count of ${#ids[@]} translations arrived."
      exit 1
    fi
    rm -f "$OUT/scripture_public_domain.zip"
    (cd "$GENESIS_VAULT/scripture" && zip -q -r "$OUT/scripture_public_domain.zip" .)
    echo "$count" > "$OUT/scripture_count.txt"
    fact "scripture_zip_bytes=$(bytes "$OUT/scripture_public_domain.zip")"
    ;;

  *)
    echo "usage: extras.sh map|scripture"
    exit 2
    ;;
esac
