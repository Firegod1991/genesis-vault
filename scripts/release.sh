#!/usr/bin/env bash
# Publish what the build made as the release for this month.
#
# Reads  OUT (the built files), GH_REPO and GH_TOKEN (for gh), REHEARSAL_URL (optional).
# Writes $OUT/SHA256SUMS, $OUT/notes.md and $OUT/release.json
#
# A rehearsal goes through the same steps under the tag "rehearsal", checks that the files
# arrived, then removes that release again so nothing mistakes it for real data.
set -euo pipefail

: "${OUT:?set OUT to the folder with the built files}" "${GH_REPO:?set GH_REPO to owner/name}"
here="$(cd "$(dirname "$0")" && pwd)"
cd "$OUT"

if [ -n "${REHEARSAL_URL:-}" ]; then
  tag="rehearsal"
  title="Rehearsal build (not for use)"
else
  tag="$(date -u +%Y.%m)"
  title="Genesis vault $(date -u +'%B %Y')"
fi

if [ ! -s survival.sqlite.gz ] || [ ! -s stats.json ]; then
  echo "There are no survival layers to publish."
  exit 1
fi

files=()
for f in survival.sqlite.gz world_overview.pmtiles scripture_public_domain.zip *.csv.gz; do
  [ -s "$f" ] || continue
  # GitHub refuses release files of 2 GiB and more.
  [ "$(stat -c %s "$f")" -lt 2000000000 ] || { echo "$f is over the 2 GB release file limit."; exit 1; }
  files+=("$f")
done

whole=yes
if [ ! -s world_overview.pmtiles ] || [ ! -s scripture_public_domain.zip ]; then whole=no; fi
sha256sum "${files[@]}" > SHA256SUMS
WHOLE="$whole" python3 "$here/notes.py" > notes.md
cat notes.md

# An incomplete build is published as a preview, so the last complete one stays the latest.
if [ "$whole" = "yes" ] && [ "$tag" != "rehearsal" ]; then kind=(--prerelease=false --latest); else kind=(--prerelease); fi
if gh release view "$tag" > /dev/null 2>&1; then
  gh release upload "$tag" "${files[@]}" SHA256SUMS --clobber
  gh release edit "$tag" --title "$title" --notes-file notes.md "${kind[@]}"
else
  gh release create "$tag" "${files[@]}" SHA256SUMS --title "$title" --notes-file notes.md "${kind[@]}"
fi

# Ask GitHub what it holds now and compare with what was sent.
gh release view "$tag" --json assets --jq '.assets[] | "\(.name) \(.size)"' | sort > published.txt
cat published.txt
for f in "${files[@]}" SHA256SUMS; do
  grep -qxF "$f $(stat -c %s "$f")" published.txt || { echo "$f did not arrive whole in release $tag."; exit 1; }
done

TAG="$tag" WHOLE="$whole" python3 - << 'EOF'
import json, os
assets = dict((n, int(s)) for n, s in (line.split() for line in open("published.txt")))
with open("release.json", "w") as f:
    json.dump({"tag": os.environ["TAG"], "whole": os.environ["WHOLE"] == "yes", "assets": assets}, f, indent=1)
    f.write("\n")
EOF

if [ "$tag" = "rehearsal" ]; then
  gh release delete "$tag" --yes --cleanup-tag
  echo "Rehearsal release removed again."
fi
