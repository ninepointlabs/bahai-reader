#!/usr/bin/env python3
"""Convert the GTK Bahá’í Reader's bundled library into this app's asset format.

Uses the GTK app's own loader (bahai_reader/library.py, load_library) read-only, so passage ids, cross-language
`match` keys, bahai.org replacements and citations are exactly the GTK app's. Nothing is downloaded and nothing in the
GTK checkout is written (bytecode writing is turned off; its cache and pack paths are redirected).

    python3 scripts/convert_library.py [--gtk ../bahai-reader] [--packs ~/.local/share/bahai-reader/libraries]
                                       [--without-bahai-org]

Output (assets/library/):
    manifest.json   bundled languages, in display order, with names and direction
    languages.json  the BahaiPrayers.net language catalog, copied unchanged from the GTK app's data/
    fold.json       search folding for every BMP character (GTK fold() per character, where it differs from lower())
    <id>.json       one library per language: {"language": id, "items": [...], "daily": [...], "obligatory": [...]}
    (assets/calendar/) badi-dates.json and cities.json, copied unchanged from the GTK app's data/

"daily" is the passage-of-the-day order (GTK passage_of_the_day(): the reflections, shuffled with random.Random(1844)), so
the app picks daily[date.toordinal() % len] and shows the same passage as the GTK app. "obligatory" is the Obligatory
prayers section's contents (GTK obligatory()) as [[group, [ids]], ...].

Item keys: id, t (title), h (heading, official texts only), a (author), s (section: prayers|hidden|writings),
g (tags), sg (subgroup), x (text), sp (spans [[start,end,kind],...]), m (match), c (citation),
r (references [[id,label],...]), w (word count), o (true if the text is bahai.org's), src (bahai.org page URL),
ob (the bahai.org book an official prayer was taken from), d (an obligatory prayer's directions [[start,end],...],
shown in italics: GTK directions()).
Offsets are code points into x; the converter checks that x has no characters outside the BMP, so they are also
UTF-16 offsets in Dart.
"""
import argparse, json, random, shutil, sys
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent.parent

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--gtk", default=str(HERE.parent / "bahai-reader"))
    p.add_argument("--packs", default=str(Path.home() / ".local/share/bahai-reader/libraries"))
    p.add_argument("--out", default=str(HERE / "assets/library"))
    p.add_argument("--without-bahai-org", action="store_true",
                   help="English from BahaiPrayers.net only (no bahai.org official texts)")
    args = p.parse_args()
    sys.path.insert(0, args.gtk)
    from bahai_reader import config, library
    config.CACHE = Path("/nonexistent-bahai-reader-cache")  # never prefer a stale cached feed over data/
    out = Path(args.out); out.mkdir(parents=True, exist_ok=True)
    catalog = json.loads((Path(args.gtk) / "data/languages.json").read_text())
    names = {r["Id"]: r for r in catalog["prayers"]}

    def convert(language):
        items = library.load_bahaiprayers(language) if (language == 1 and args.without_bahai_org) else library.load_library(language)
        rows = []
        for i in items:
            text = i["text"]
            if any(ord(c) > 0xFFFF for c in text):
                raise SystemExit(f"{i['id']}: text has characters outside the BMP; offsets would need conversion")
            row = {"id": i["id"], "t": i["title"], "a": i.get("author"), "s": i["section"], "g": i["tags"],
                   "sg": i.get("subgroup"), "x": text, "m": i.get("match"), "c": i.get("citation") or "",
                   "w": i["word_count"]}
            if i.get("heading"): row["h"] = i["heading"]
            if i.get("spans"): row["sp"] = [list(s) for s in i["spans"]]
            if i.get("references"): row["r"] = [list(r) for r in i["references"]]
            if i.get("official_id"): row["o"] = True
            if i.get("official_book"): row["ob"] = i["official_book"]
            if i.get("source"): row["src"] = i["source"]
            directions = library.directions(i)
            if directions: row["d"] = [list(d) for d in directions]
            rows.append({k: v for k, v in row.items() if v is not None})
        ids = [r["id"] for r in rows]
        if len(ids) != len(set(ids)): raise SystemExit(f"duplicate ids in language {language}")
        pool = library.reflections(items)
        order = list(range(len(pool))); random.Random(1844).shuffle(order)
        daily = [pool[k]["id"] for k in order]
        obligatory = [[group, [p["id"] for p in passages]] for group, passages in library.obligatory(items).items()]
        (out / f"{language}.json").write_text(json.dumps({"language": language, "items": rows, "daily": daily, "obligatory": obligatory},
                                                         ensure_ascii=False, separators=(",", ":")))
        return len(rows)

    bundled = []
    config.LIBRARY = Path("/nonexistent-bahai-reader-packs")  # English always from the shipped data/
    bundled.append((1, convert(1)))
    config.LIBRARY = Path(args.packs)
    for pack in sorted(Path(args.packs).glob("*.json")) if Path(args.packs).is_dir() else []:
        if not pack.stem.isdigit() or int(pack.stem) == 1: continue
        language = int(pack.stem)
        if library.local_pack(language) is None:
            print(f"skipping {pack}: not a valid pack", file=sys.stderr); continue
        bundled.append((language, convert(language)))
    manifest = [{"id": l, "name": names.get(l, {}).get("Name", str(l)).rstrip("."), "english": names.get(l, {}).get("English", str(l)),
                 "rtl": not names.get(l, {}).get("IsLeftToRight", True), "passages": n} for l, n in bundled]
    # Search folding: for every character in the bundled texts (plus Latin accented letters a query may use), what the GTK
    # app's search.fold() turns it into, where that differs. Dart applies it per character, which is what fold_map() does.
    from bahai_reader.search import fold
    # Every character of the Basic Multilingual Plane, so a language downloaded later folds exactly as in the GTK app.
    chars = {c for c in range(0x20, 0x10000) if not 0xD800 <= c < 0xE000}
    table = {chr(c): fold(chr(c)) for c in sorted(chars) if fold(chr(c)) != chr(c).lower()}
    (out / "fold.json").write_text(json.dumps(table, ensure_ascii=False, separators=(",", ":"), sort_keys=True))
    (out / "manifest.json").write_text(json.dumps({"languages": manifest, "bahaiOrg": not args.without_bahai_org}, ensure_ascii=False, indent=1))
    calendar = out.parent / "calendar"; calendar.mkdir(exist_ok=True)
    for name in ("badi-dates.json", "cities.json"): shutil.copyfile(Path(args.gtk) / "data" / name, calendar / name)
    # The language catalog (which languages offer which collections), for Languages & offline libraries.
    shutil.copyfile(Path(args.gtk) / "data" / "languages.json", out / "languages.json")
    for m in manifest: print(f"{m['id']:>4} {m['english']}: {m['passages']} passages")

if __name__ == "__main__":
    main()
