"""Pull the real texts and counts the mockups show out of the bundled library (nothing is invented or reworded).
usage: python3 design/mockups/phase2/extract.py OUTDIR   (writes OUTDIR/mockdata.json and OUTDIR/search.json)"""
import collections, html, json, re, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import reader

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
items = reader.load_library(1); byid = {i["id"]: i for i in items}
text = reader.unnumbered
gl = [i for i in items if "Gleanings from the Writings of Bahá’u’lláh" in i["tags"]]
gpb = [i for i in items if "God Passes By" in i["tags"]]
hw = [i for i in items if i["section"] == "hidden"]
healing = next(i for i in items if i["section"] == "prayers" and i["tags"] == ["Healing"])
json.dump(dict(
    gleanings1=dict(text=text(gl[0]), citation=gl[0]["citation"], title=gl[0]["title"], n=len(gl), words=[i["word_count"] for i in gl]),
    gleanings_titles=[i["title"] for i in gl[:12]],
    gpb=[dict(title=i["title"], sub=i["subgroup"], words=i["word_count"]) for i in gpb],
    gpb2=dict(text=text(gpb[2])[:3000], title=gpb[2]["title"], heading=reader.heading(gpb[2]), citation=gpb[2]["citation"]),
    hw2=dict(text=text(hw[1]), citation=hw[1]["citation"]), hw5=dict(text=text(hw[4]), citation=hw[4]["citation"]),
    healing=dict(text=text(healing)[:900], citation=healing["citation"]),
    prayer_cats=sorted(collections.Counter(t for i in items if i["section"] == "prayers" for t in i["tags"]).items()),
), open(out / "mockdata.json", "w"), ensure_ascii=False)

def snip(i, word="justice"):
    t = " ".join(text(i).split()); m = re.search(word, t, re.I); k = m.start(); a = max(0, k - 70); b = min(len(t), k + 90)
    a = t.rfind(" ", 0, a) + 1 if a else 0; b = t.find(" ", b) if t.find(" ", b) > 0 else len(t)
    return ("…" if a else "") + html.escape(t[a:k]) + "<b>" + html.escape(t[k:m.end()]) + "</b>" + html.escape(t[m.end():b]) + ("…" if b < len(t) else "")
matches = [i for i in items if reader.fold("justice") in reader.fold(text(i))]
prayer = next(i for i in items if i["section"] == "prayers" and re.search("justice", i["text"], re.I))
vi = next(i for i in gl if reader.heading(i) == "VI")
json.dump(dict(total=len(matches), gleanings=sum("Gleanings from the Writings of Bahá’u’lláh" in i["tags"] for i in matches),
               rows=[("Gleanings from the Writings of Bahá’u’lláh", "I", snip(byid["gleanings:1"])), ("Gleanings from the Writings of Bahá’u’lláh", "VI", snip(vi)),
                     ("The Hidden Words", "Arabic no. 2", snip(byid["hidden:2"])), ("Prayers · " + prayer["tags"][0], reader.subtitle(prayer), snip(prayer))]),
          open(out / "search.json", "w"), ensure_ascii=False)
print("wrote", out / "mockdata.json", out / "search.json")
