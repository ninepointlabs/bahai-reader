#!/usr/bin/env python3
"""Writes a fixture for test/packs_test.dart: the English BahaiPrayers.net feeds bundled with the GTK app, as a pack, and
what the GTK app's own load_bahaiprayers(1) makes of them, in this app's library format. Reads the GTK checkout only.

    python3 scripts/pack_fixtures.py OUT.json [--gtk ../bahai-reader]
    GTK_ENGLISH_PACK=OUT.json flutter test test/packs_test.dart
"""
import argparse, json, random, sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent.parent

def main():
    p = argparse.ArgumentParser(); p.add_argument("out"); p.add_argument("--gtk", default=str(HERE.parent / "bahai-reader"))
    args = p.parse_args()
    sys.path.insert(0, args.gtk)
    from bahai_reader import config, library
    config.CACHE = Path("/nonexistent-bahai-reader-cache"); config.LIBRARY = Path("/nonexistent-bahai-reader-packs")
    pack = {key: json.loads((Path(args.gtk) / "data" / f"{key}.json").read_text()) for key in config.FEEDS}
    items = library.load_bahaiprayers(1)
    rows = []
    for i in items:
        row = {"id": i["id"], "t": i["title"], "a": i.get("author"), "s": i["section"], "g": i["tags"], "sg": i.get("subgroup"),
               "x": i["text"], "m": i.get("match"), "c": i.get("citation") or "", "w": i["word_count"]}
        if i.get("references"): row["r"] = [list(r) for r in i["references"]]
        d = library.directions(i)
        if d: row["d"] = [list(x) for x in d]
        rows.append({k: v for k, v in row.items() if v is not None})
    pool = library.reflections(items); order = list(range(len(pool))); random.Random(1844).shuffle(order)
    expected = {"language": 1, "items": rows, "daily": [pool[k]["id"] for k in order],
                "obligatory": [[g, [x["id"] for x in ps]] for g, ps in library.obligatory(items).items()]}
    Path(args.out).write_text(json.dumps({"pack": pack, "expected": expected}, ensure_ascii=False))
    print(f"{len(rows)} passages")

if __name__ == "__main__":
    main()
