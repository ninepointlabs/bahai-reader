#!/usr/bin/env python3
"""Expected answers from the GTK app's own badi.py and library.py, for test/calendar_test.dart.

    TZ=America/Chicago python3 scripts/calendar_fixtures.py [--gtk ../bahai-reader]

The GTK checkout is only read (bytecode writing is off). Times are written as ISO strings with their offset.
"""
import argparse, datetime, json, sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent.parent

def main():
    p = argparse.ArgumentParser(); p.add_argument("--gtk", default=str(HERE.parent / "bahai-reader")); args = p.parse_args()
    sys.path.insert(0, args.gtk)
    import badi
    from bahai_reader import config, library
    config.CACHE = Path("/nonexistent-bahai-reader-cache"); config.LIBRARY = Path("/nonexistent-bahai-reader-packs")
    iso = lambda m: m.isoformat() if m else None
    places = {"haifa": {"label": "Haifa", "lat": 32.82, "lon": 34.99, "tz": "Asia/Jerusalem"},
              "chicago": {"label": "Chicago", "lat": 41.85, "lon": -87.65, "tz": "America/Chicago"},
              "tromso": {"label": "Tromsø", "lat": 69.65, "lon": 18.96, "tz": "Europe/Oslo"},
              "kiritimati": {"label": "Kiritimati", "lat": 1.87, "lon": -157.4, "tz": "Pacific/Kiritimati"},
              "clock": badi.clock_place(None, {"sunrise": 360, "noon": 750, "sunset": 1140})}
    dates = [datetime.date(2015, 3, 21), datetime.date(2016, 2, 29), datetime.date(2024, 3, 19), datetime.date(2024, 3, 20),
             datetime.date(2026, 2, 25), datetime.date(2026, 3, 2), datetime.date(2026, 6, 21), datetime.date(2026, 11, 15),
             datetime.date(2026, 12, 21), datetime.date(2065, 3, 19), datetime.date(2066, 6, 1), datetime.date(2014, 1, 1)]
    out = {"dates": [], "sun": [], "observed": [], "windows": [], "long": [], "daily": []}
    for d in dates:
        b = badi.from_gregorian(d)
        out["dates"].append({"date": d.isoformat(), "badi": str(b) if b else None,
                             "upcoming": [[e.name, e.date.isoformat(), e.kind] for e in badi.upcoming(d, 120)],
                             "fast": [s.day, s.date.isoformat()] if (s := badi.fast_state(d)) else None,
                             "ayyam": badi.next_ayyam_i_ha(d).first.isoformat() if badi.next_ayyam_i_ha(d) else None,
                             "months": [[m.name, m.first.isoformat(), m.last.isoformat()] for m in badi.year_months(b.year)] if b else []})
        for name, place in places.items():
            s = badi.place_sun(place, d)
            out["sun"].append({"place": name, "date": d.isoformat(), "sunrise": iso(s.sunrise), "noon": iso(s.noon), "sunset": iso(s.sunset), "polar": s.polar})
    for name, place in places.items():
        for d in dates[4:9]:
            for hour in (0, 1, 6, 12, 17, 18, 19, 20, 23):
                zone = badi.ZoneInfo(place["tz"]) if place.get("tz") else None
                moment = datetime.datetime(d.year, d.month, d.day, hour, 30, tzinfo=zone) if zone else datetime.datetime(d.year, d.month, d.day, hour, 30).astimezone()
                out["observed"].append({"place": name, "moment": moment.isoformat(), "observed": badi.observed_date(moment, place).isoformat()})
                for prayer in ("short", "medium"):
                    w = badi.current_window(prayer, moment, place)
                    out["windows"].append({"place": name, "prayer": prayer, "moment": moment.isoformat(),
                                           "window": [w.key, w.opens.isoformat(), w.closes.isoformat()] if w else None})
                for period in ("sunset", "noon", "midnight"):
                    w = badi.long_window({"long_period": period}, moment, place)
                    out["long"].append({"place": name, "period": period, "moment": moment.isoformat(), "window": [w.key, w.opens.isoformat(), w.closes.isoformat()]})
    items = library.load_library(1)
    for d in dates[:9]:
        out["daily"].append([d.isoformat(), library.passage_of_the_day(items, d)["id"]])
    (HERE / "test/fixtures/calendar.json").write_text(json.dumps(out, ensure_ascii=False, indent=0))
    print(len(out["sun"]), "sun rows,", len(out["windows"]), "windows")

if __name__ == "__main__":
    main()
