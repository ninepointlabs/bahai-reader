#!/usr/bin/python3
"""Rebuilds data/cities.json from GeoNames dumps: cities15000.zip, admin1CodesASCII.txt and countryInfo.txt.
Usage: scripts/build-cities.py <folder holding the three files>. Cities are kept in order of population, largest first,
so a search can show the largest match first without storing the population."""
import datetime
import json
import sys
import zipfile
from pathlib import Path

source=Path(sys.argv[1])
countries={line.split("\t")[0]:line.split("\t")[4] for line in (source/"countryInfo.txt").read_text().splitlines() if line and not line.startswith("#")}
regions={line.split("\t")[0]:line.split("\t")[1] for line in (source/"admin1CodesASCII.txt").read_text().splitlines() if line}
rows=[line.split("\t") for line in zipfile.ZipFile(source/"cities15000.zip").read("cities15000.txt").decode().splitlines()]
rows.sort(key=lambda r:(-int(r[14] or 0),r[1]))
assert not any(c in r[1]+r[2] for r in rows for c in "|;")
region_names=sorted({regions.get(f"{r[8]}.{r[10]}","") for r in rows}); zones=sorted({r[17] for r in rows})
region_index={n:i for i,n in enumerate(region_names)}; zone_index={n:i for i,n in enumerate(zones)}
# One string of ;-separated rows of |-separated fields (neither appears in a name), about 250 KB smaller than nested JSON lists:
# name, ASCII name (empty when the same), country code, region number, latitude, longitude, time zone number.
cities=";".join("|".join((r[1],"" if r[2]==r[1] else r[2],r[8],str(region_index[regions.get(f"{r[8]}.{r[10]}","")]),str(round(float(r[4]),2)),str(round(float(r[5]),2)),str(zone_index[r[17]]))) for r in rows)
used={r[8] for r in rows}
data=dict(source="GeoNames cities15000, trimmed to name, ASCII name, country, region, latitude, longitude and time zone; coordinates rounded to 2 decimals",
          credit="City data © GeoNames (https://www.geonames.org/), CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/)",
          retrieved=datetime.date.today().isoformat(),countries={k:countries.get(k,k) for k in sorted(used)},regions=region_names,zones=zones,cities=cities)
Path(__file__).resolve().parents[1].joinpath("data/cities.json").write_text(json.dumps(data,ensure_ascii=False,separators=(",",":")))
print(len(rows),"cities")
