"""Release notes for a vault build. Run it inside the folder that holds the built files."""

import datetime
import json
import os


def main():
    stats = json.load(open("stats.json"))
    source = json.load(open("source.json")) if os.path.exists("source.json") else {}
    today = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    if source.get("rehearsal"):
        print("**Rehearsal build from a small extract (%s). Not for use.**\n" % source.get("file"))
    elif source.get("planet_date"):
        print("Built %s from the OpenStreetMap planet file of %s.\n" % (today, source["planet_date"]))
    else:
        print("Built %s from OpenStreetMap.\n" % today)
    if os.environ.get("WHOLE") != "yes":
        missing = [n for n in ("world_overview.pmtiles", "scripture_public_domain.zip") if not os.path.exists(n)]
        print("**This build is incomplete.** Not built this time: %s.\n" % ", ".join(missing))
    print("| Layer | Places |\n|---|---|")
    for name, c in stats["categories"].items():
        print("| %s | %s |" % (name, format(c["total"], ",")))
    print("| **All** | **%s** |\n" % format(stats["total"], ","))
    if os.path.exists("scripture_count.txt"):
        print("%s public domain Bible translations in `scripture_public_domain.zip`.\n"
              % open("scripture_count.txt").read().strip())
    print("Use it with Genesis: `genesis fetch --id survival_layers_world --id world_overview`\n")
    print("Map data and survival layers: © OpenStreetMap contributors, Open Database License. "
          "Power plants: World Resources Institute Global Power Plant Database, CC BY 4.0. "
          "Scripture: public domain texts from eBible.org.")


if __name__ == "__main__":
    main()
