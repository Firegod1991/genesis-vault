# Genesis vault

**The heavy data for [Genesis](https://github.com/Firegod1991/genesis), rebuilt every month and published as release files.**

Genesis is the catalog and the tools. This repository is the data factory beside it: once a month a workflow reads the whole OpenStreetMap planet file and publishes the result so a new Genesis box has a map of the world and knows where the water, care, fuel and power are within minutes of its first run.

Get the newest build from [Releases](https://github.com/Firegod1991/genesis-vault/releases/latest), or let Genesis do it:

```sh
genesis fetch --id survival_layers_world --id world_overview --id map_assets
```

## What each release holds

| File | What it is |
|---|---|
| `survival.sqlite.gz` | Survival layers for the whole world: one SQLite database of places, with a spatial index |
| `water.csv.gz`, `medical.csv.gz`, `fuel.csv.gz`, `power.csv.gz`, `shelter.csv.gz`, `supply.csv.gz`, `comms.csv.gz`, `transport.csv.gz` | The same places as plain tables, one per layer, for spreadsheets and other tools |
| `world_overview.pmtiles` | Every country at zoom 0 to 6 as one offline vector map |
| `scripture_public_domain.zip` | Every public domain Bible translation that eBible.org shares, as readable pages and USFM source |
| `SHA256SUMS` | Checksums for all of the above |

## The layers

| Layer | Places |
|---|---|
| Water | drinking water points, wells, taps, springs, water towers and works |
| Medical | hospitals, clinics, doctors, pharmacies, dentists, veterinarians, ambulance stations, defibrillators |
| Fuel | fuel stations, vehicle charging, bottled gas, marine fuel |
| Power | power plants, substations, generators (rooftop solar is left out) |
| Shelter and safety | shelters, fire stations, police, community centres, assembly points, huts, camp sites, bunkers |
| Supply | supermarkets, convenience, hardware, outdoor and farm supply stores, marketplaces |
| Communications | communications towers, emergency phones |
| Transport | airfields, helipads, ferry terminals, rail stations, marinas |

The exact tags are in [poi_categories.json](https://github.com/Firegod1991/genesis/blob/main/catalog/poi_categories.json). Power plants also come from the World Resources Institute Global Power Plant Database, which adds fuel type and capacity.

## Using the database without Genesis

It is ordinary SQLite. Any language can read it.

```sql
-- table poi: id, cat, sub, name, lat, lon, osm, tags (JSON)
-- table poi_rt: an R*Tree over the same ids (min_lon, max_lon, min_lat, max_lat)

-- every hospital in a box around Monaco
SELECT p.name, p.lat, p.lon, p.tags
FROM poi_rt r JOIN poi p ON p.id = r.id
WHERE r.min_lon >= 7.3 AND r.max_lon <= 7.5 AND r.min_lat >= 43.7 AND r.max_lat <= 43.8
  AND p.cat = 'medical' AND p.sub = 'hospital';
```

`osm` is the OpenStreetMap object the place came from: `n` for a node, `w` for a way, `r` for a relation, followed by its id. Areas are stored as the middle of their bounding box.

## How it is built

[build.yml](.github/workflows/build.yml) runs on the 27th of each month, a few days before the Genesis catalog refresh on the 1st. The work itself is in [scripts](scripts):

1. **Survival layers.** One job downloads the newest weekly [OpenStreetMap planet file](https://planet.openstreetmap.org) from the OpenStreetMap bucket on Amazon S3, checks its MD5, keeps only the survival layers with osmium and runs `genesis poi build`.
2. **World overview map.** A second job cuts zoom 0 to 6 from the newest [Protomaps](https://protomaps.com) planet build.
3. **Scripture.** A third job gathers every public domain translation in the Genesis catalog.
4. **Release.** The last job publishes all of it under a tag named for the month, then checks that GitHub holds every file whole.

The planet file is used on purpose. It is one download a month from storage that OpenStreetMap provides for bulk use. Regional mirrors such as Geofabrik ask people not to rebuild the planet from their extracts.

If the map or the scripture bundle fails, the layers are still published and the release is marked as a preview that says what is missing. The last complete release stays the one marked latest.

Every run, good or bad, writes what happened to [status.json](status.json): which planet file was used, how long each stage took, how many places were found, and the end of the log of any step that failed. A published build also rewrites [LATEST.md](LATEST.md) with its totals and checksums.

### Changing the build

* To change what the layers contain, change `poi_categories.json` in Genesis. Nothing here is edited by hand.
* To try a change to the workflow quickly, set `REHEARSAL_URL` in build.yml to a small extract. The whole workflow then runs in minutes on that extract, publishes under the tag `rehearsal`, checks the files and removes that release again.
* To fix a later step without rebuilding the layers, start the workflow by hand and give it the id of the run whose layers to reuse.

## Read this before you rely on it

* OpenStreetMap is made by volunteers. Coverage of wells, springs and small clinics varies by country. A missing place does not mean nothing is there, and a mapped place may be dry, closed or gone.
* Treat every water source as unsafe until treated.
* The data is a snapshot from the day of the build.

## Licenses

* **Survival layers and tables:** derived from OpenStreetMap. © OpenStreetMap contributors, available under the [Open Database License](https://opendatacommons.org/licenses/odbl/). If you share or adapt them, keep that credit and the same license.
* **Power plant data:** Global Power Plant Database, World Resources Institute, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
* **World overview map:** © OpenStreetMap contributors (ODbL), built by Protomaps.
* **Scripture:** public domain texts, gathered and formatted by [eBible.org](https://ebible.org). Each translation carries its own `copr.htm`.
* **The workflow in this repository:** MIT.
