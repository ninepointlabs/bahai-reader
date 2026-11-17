#!/usr/bin/env python3
"""Expected reminders from the GTK app's own badi.py, for test/reminders_test.dart.

    TZ=America/Chicago python3 scripts/reminder_fixtures.py [--gtk ../bahai-reader]

The GTK checkout is only read (bytecode writing is off). Clock text is always HH:MM so both sides agree.
"""
import argparse, datetime, json, sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent.parent

def main():
    p = argparse.ArgumentParser(); p.add_argument("--gtk", default=str(HERE.parent / "bahai-reader")); args = p.parse_args()
    sys.path.insert(0, args.gtk)
    import badi
    clock = lambda m: m.strftime("%H:%M")
    places = {"haifa": {"label": "Haifa", "lat": 32.82, "lon": 34.99, "tz": "Asia/Jerusalem"},
              "chicago": {"label": "Chicago", "lat": 41.85, "lon": -87.65, "tz": "America/Chicago"},
              "clock": badi.clock_place(None, {"sunrise": 360, "noon": 750, "sunset": 1140}),
              "none": None}
    all_on = {k: True for k in ("prayer", "long", "feast", "holy", "fast", "fast_daily")}
    settings = {"short": {"prayer": "short", "reminders": all_on},
                "medium": {"prayer": "medium", "reminders": all_on},
                "medium-prayer-only": {"prayer": "medium", "reminders": {"prayer": True}},
                "long-sunset": {"prayer": "long", "reminders": all_on},
                "long-noon-5": {"prayer": "long", "long_period": "noon", "long_lead_hours": 5, "reminders": all_on},
                "long-midnight": {"prayer": "long", "long_period": "midnight", "reminders": all_on},
                "long-rolling": {"prayer": "long", "long_period": "rolling", "reminders": all_on},
                "none": {"prayer": "none", "reminders": {"feast": True, "holy": True}}}
    days = [datetime.date(2026, 2, 25), datetime.date(2026, 3, 1), datetime.date(2026, 3, 2), datetime.date(2026, 3, 20),
            datetime.date(2026, 11, 9), datetime.date(2026, 11, 10), datetime.date(2026, 11, 15), datetime.date(2026, 11, 22),
            datetime.date(2026, 12, 21)]
    iso = lambda m: m.isoformat() if m else None
    out = []
    for pname, place in places.items():
        for sname, s in settings.items():
            for d in days:
                for hour in (5, 13, 18, 21):
                    zone = badi.ZoneInfo(place["tz"]) if place and place.get("tz") else None
                    moment = datetime.datetime(d.year, d.month, d.day, hour, 10, tzinfo=zone) if zone else datetime.datetime(d.year, d.month, d.day, hour, 10).astimezone()
                    said = []
                    if sname == "long-rolling" and hour >= 13:
                        said = [f"{d.isoformat()}:long:at:{int(moment.timestamp()) - 3 * 3600}"]
                    if sname == "medium" and hour == 13:
                        said = [f"{d.isoformat()}:medium:noon"]
                    found = badi.candidate_reminders(s, moment, place, clock, said)
                    sent = [r.id for r in found][:1] if hour == 18 else []
                    due, marked = badi.due_reminders(s, moment, place, clock, sent, said)
                    out.append({"place": pname, "settings": sname, "moment": moment.isoformat(), "said": said, "sent": sent,
                                "candidates": [[r.id, r.group, r.title, r.body, iso(r.at), iso(r.until), r.said, r.opens] for r in found],
                                "due": [r.id for r in due], "marked": marked})
    (HERE / "test/fixtures/reminders.json").write_text(json.dumps({"settings": settings, "cases": out}, ensure_ascii=False))
    print(len(out), "cases,", sum(len(c["candidates"]) for c in out), "candidates,", sum(len(c["due"]) for c in out), "due")

if __name__ == "__main__":
    main()
