#!/usr/bin/env bash
# Survival layers for the whole world, from the OpenStreetMap planet file.
#
# One planet download a month, taken from the OpenStreetMap bucket on Amazon S3. That is where
# OpenStreetMap sends bulk downloads. Regional mirrors such as Geofabrik ask people not to piece
# the planet together from their extracts, and they block machines that do.
#
# Needs  osmium, python3, curl (aria2c is used when present), a Genesis checkout.
# Reads  WORK (scratch disk), OUT (results), GENESIS (checkout), NOTE (facts file, optional),
#        REHEARSAL_URL (a small extract to rehearse with, optional), MIN_PLACES (optional).
# Writes $OUT/survival.sqlite.gz, $OUT/<layer>.csv.gz, $OUT/stats.json, $OUT/source.json
set -euo pipefail

: "${WORK:?set WORK to a scratch folder}" "${OUT:?set OUT to the results folder}" "${GENESIS:?set GENESIS to a Genesis checkout}"
AGENT="GenesisVault/1 (+https://github.com/Firegod1991/genesis-vault)"
PLANET_URL="${PLANET_URL:-https://planet.openstreetmap.org/pbf/planet-latest.osm.pbf}"
REHEARSAL_URL="${REHEARSAL_URL:-}"
SPARE_BYTES="${SPARE_BYTES:-8589934592}"   # room kept beside the planet for the filtered copy

mkdir -p "$WORK" "$OUT"
fact() { echo "$1"; if [ -n "${NOTE:-}" ]; then echo "$1" >> "$NOTE"; fi; }
ask() { curl -fsS -A "$AGENT" --connect-timeout 30 --retry 5 --retry-delay 15 --retry-all-errors "$@"; }
bytes() { stat -c %s "$1" 2>/dev/null || echo 0; }

if [ -n "$REHEARSAL_URL" ]; then
  source_url="$REHEARSAL_URL"
  min_places="${MIN_PLACES:-100}"
  fact "mode=rehearsal"
else
  source_url="$PLANET_URL"
  min_places="${MIN_PLACES:-5000000}"
  fact "mode=planet"
fi

# ---------------------------------------------------------------- which file

# The "latest" link answers with the dated file. A dated file never changes, so a broken
# download can pick up where it stopped and the checksum always belongs to the same bytes.
final="$(ask -IL -o /dev/null -w '%{url_effective}' "$source_url")"
name="$(basename "${final%%\?*}")"
size="$(ask -IL "$final" | tr -d '\r' | awk 'tolower($1) == "content-length:" { n = $2 } END { print n + 0 }')"
want="$(curl -fsSL -A "$AGENT" --connect-timeout 30 --retry 3 --retry-delay 10 "$final.md5" 2> /dev/null | awk 'NR == 1 { print tolower($1) }' || true)"
case "$name" in *.osm.pbf) ;; *) echo "Unexpected file name from $source_url: $name"; exit 1 ;; esac
[ "$size" -gt 0 ] || { echo "The server did not say how large $name is."; exit 1; }
if ! [[ "$want" =~ ^[0-9a-f]{32}$ ]]; then
  # Only a rehearsal may run without a published checksum.
  [ -n "$REHEARSAL_URL" ] || { echo "No MD5 is published for $name."; exit 1; }
  want=""
fi
fact "source=$name"
fact "source_bytes=$size"

free="$(df --output=avail -B1 "$WORK" | tail -1 | tr -d ' ')"
fact "disk_free_before=$free"
if [ "$free" -lt "$((size + SPARE_BYTES))" ]; then
  echo "$name is $size bytes and $WORK has $free free. It needs the file plus $SPARE_BYTES spare."
  exit 1
fi

# ---------------------------------------------------------------- download

full="$WORK/full.osm.pbf"

download() {
  if command -v aria2c > /dev/null; then
    # Eight ranges at once. The bucket is built for this and OpenStreetMap's own guide uses parallel tools.
    for try in 1 2 3; do
      if aria2c --console-log-level=warn --summary-interval=180 --show-console-readout=false \
           --user-agent="$AGENT" --file-allocation=none --max-connection-per-server=8 --split=8 \
           --min-split-size=64M --max-tries=30 --retry-wait=20 --timeout=60 --connect-timeout=30 \
           --lowest-speed-limit=20K --continue=true --auto-file-renaming=false --allow-overwrite=true \
           --dir="$WORK" --out="full.osm.pbf" "$final" \
         && [ ! -e "$full.aria2" ] && [ "$(bytes "$full")" -eq "$size" ]; then
        return 0
      fi
      echo "aria2c try $try did not finish."
      sleep 30
    done
    # A file that aria2c left half written has holes in it. curl has to start clean.
    rm -f "$full" "$full.aria2"
  fi
  for try in $(seq 1 40); do
    [ "$(bytes "$full")" -lt "$size" ] || return 0
    curl -fL -sS -A "$AGENT" --connect-timeout 30 --speed-limit 20000 --speed-time 120 -C - -o "$full" "$final" \
      || echo "curl try $try stopped at $(bytes "$full") of $size bytes."
    [ "$(bytes "$full")" -lt "$size" ] || return 0
    sleep 20
  done
  return 1
}

started=$SECONDS
download || { echo "The download of $name did not finish."; exit 1; }
fact "download_seconds=$((SECONDS - started))"
[ "$(bytes "$full")" -eq "$size" ] || { echo "$name arrived as $(bytes "$full") bytes, expected $size."; exit 1; }

started=$SECONDS
if [ -n "$want" ]; then
  have="$(md5sum "$full" | cut -d' ' -f1)"
  [ "$have" = "$want" ] || { echo "MD5 mismatch for $name: wanted $want, got $have."; rm -f "$full"; exit 1; }
  fact "checksum=md5 verified"
else
  fact "checksum=none published (rehearsal)"
fi
fact "checksum_seconds=$((SECONDS - started))"

# ---------------------------------------------------------------- filter

# Keep only the survival layers and the points they are drawn from. After this the planet can go.
read -r -a rules <<< "$(cd "$GENESIS" && python3 -c "from genesis import poi; print(' '.join(poi.filter_expressions()))")"
[ "${#rules[@]}" -gt 0 ] || { echo "Genesis gave no filter rules."; exit 1; }
filtered="$WORK/$name"
started=$SECONDS
osmium tags-filter "$full" "${rules[@]}" -o "$filtered" --overwrite --verbose
rm -f "$full"
fact "filter_seconds=$((SECONDS - started))"
fact "filtered_bytes=$(bytes "$filtered")"

# ---------------------------------------------------------------- database

export GENESIS_VAULT="${GENESIS_VAULT:-$WORK/vault}"
db="$WORK/survival.sqlite"
started=$SECONDS
(
  cd "$GENESIS"
  # Fuel type and capacity for power plants. The layers are still worth publishing without it.
  python3 -m genesis fetch --id global_power_plants || echo "The power plant database did not download."
  python3 -m genesis poi build --pbf "$filtered" --db "$db" --replace
  python3 -m genesis poi stats --db "$db" > "$OUT/stats.json"
)
rm -f "$filtered"
places="$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['total'])" "$OUT/stats.json")"
fact "build_seconds=$((SECONDS - started))"
fact "places=$places"
fact "database_bytes=$(bytes "$db")"
if [ "$places" -lt "$min_places" ]; then
  echo "Only $places places were found, fewer than the $min_places a sound build has."
  exit 1
fi

# ---------------------------------------------------------------- files to publish

started=$SECONDS
(
  cd "$GENESIS"
  for layer in $(python3 -c "from genesis import poi; print(' '.join(poi.categories()))"); do
    python3 -m genesis poi export --db "$db" --format csv --cat "$layer" --out "$OUT/$layer.csv"
    gzip -9 -f "$OUT/$layer.csv"
  done
)
gzip -6 -c "$db" > "$OUT/survival.sqlite.gz"
rm -f "$db"
fact "pack_seconds=$((SECONDS - started))"
fact "survival_sqlite_gz_bytes=$(bytes "$OUT/survival.sqlite.gz")"

# What the release notes say about where the data came from.
stamp="$(echo "$name" | sed -n 's/^planet-\([0-9][0-9]\)\([0-9][0-9]\)\([0-9][0-9]\)\.osm\.pbf$/20\1-\2-\3/p')"
python3 - "$OUT/source.json" "$name" "$size" "${stamp:-}" "${REHEARSAL_URL:+rehearsal}" << 'EOF'
import json, sys
path, name, size, stamp, rehearsal = sys.argv[1:6]
with open(path, "w") as f:
    json.dump({"file": name, "bytes": int(size), "planet_date": stamp or None, "rehearsal": bool(rehearsal)}, f, indent=1)
    f.write("\n")
EOF
ls -l "$OUT"
