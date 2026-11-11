"""Phase 2 mockups as static HTML (libadwaita-like layout), filled with the app's real texts and counts.
usage: gen.py DATA.json OUTDIR"""
import json, re, sys, html
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
out = Path(sys.argv[2]); out.mkdir(parents=True, exist_ok=True)
E = html.escape

def icon(name):
    for p in Path("/usr/share/icons/Adwaita/symbolic").rglob(name + ".svg"):
        svg = p.read_text()
        svg = re.sub(r"<\?xml[^>]*\?>", "", svg)
        svg = re.sub(r'fill="(?!none)[^"]*"', 'fill="currentColor"', svg)
        svg = re.sub(r"fill:#[0-9a-fA-F]{3,6}", "fill:currentColor", svg)
        svg = re.sub(r"<svg ", '<svg class="i" ', svg, count=1)
        return svg
    return ""

# Palettes mapped onto libadwaita's named colours (the Phase 2 theme mapping).
FLEXOKI = dict(name="Omarchy · Flexoki Light", bg="#FFFCF0", fg="#100F0F", sidebar="#F2EFE4", card="#FFFCF0", border="rgba(16,15,15,.11)",
               dim="#5d5b57", accent="#205EA6", accent_fg="#FFFCF0", hl_yellow="rgba(208,162,21,.30)", hl_green="rgba(135,154,57,.28)",
               hl_blue="rgba(32,94,166,.18)", hl_magenta="rgba(206,93,151,.22)", selected="rgba(16,15,15,.075)", hover="rgba(16,15,15,.05)", shade="rgba(0,0,0,.06)")
DARK = dict(name="Dark", bg="#161b19", fg="#e6e1d3", sidebar="#1c2220", card="#1d2321", border="rgba(230,225,211,.12)", dim="#a9a597",
            accent="#c9ab70", accent_fg="#161b19", hl_yellow="rgba(201,171,112,.30)", hl_green="rgba(140,170,110,.28)", hl_blue="rgba(110,150,200,.25)",
            hl_magenta="rgba(200,120,160,.25)", selected="rgba(230,225,211,.09)", hover="rgba(230,225,211,.06)", shade="rgba(0,0,0,.35)")

def css(p, width):
    return f"""
*{{box-sizing:border-box;margin:0;padding:0}}
:root{{--bg:{p['bg']};--fg:{p['fg']};--sidebar:{p['sidebar']};--card:{p['card']};--border:{p['border']};--dim:{p['dim']};--accent:{p['accent']};
--accent-fg:{p['accent_fg']};--selected:{p['selected']};--hover:{p['hover']};--shade:{p['shade']}}}
html,body{{width:{width}px;height:800px;overflow:hidden;background:var(--bg);color:var(--fg);font-family:"Adwaita Sans","Cantarell",sans-serif;font-size:14.5px;-webkit-font-smoothing:antialiased}}
.i{{width:16px;height:16px;flex:none;vertical-align:middle}}
.win{{display:flex;height:800px;width:{width}px}}
.side{{width:272px;flex:none;background:var(--sidebar);border-right:1px solid var(--border);display:flex;flex-direction:column}}
.hb{{height:47px;flex:none;display:flex;align-items:center;gap:6px;padding:0 7px;border-bottom:1px solid var(--border)}}
.hb .title{{flex:1;text-align:center;font-weight:700;font-size:14.5px;line-height:1.15;overflow:hidden;white-space:nowrap;text-overflow:ellipsis}}
.hb .title small{{display:block;font-weight:400;font-size:12px;color:var(--dim)}}
.btn{{height:34px;min-width:34px;border-radius:6px;display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:0 9px;color:var(--fg)}}
.btn.text{{font-weight:600}}
.btn.on{{background:var(--selected)}}
.btn.raised{{background:var(--selected)}}
.btn.pill{{border-radius:99px;padding:0 18px;height:36px}}
.btn.suggested{{background:var(--accent);color:var(--accent-fg);font-weight:600}}
.kbd{{font-size:11.5px;color:var(--dim);border:1px solid var(--border);border-radius:4px;padding:1px 5px}}
.nav{{padding:6px}}
.row{{display:flex;align-items:center;gap:12px;height:38px;padding:0 10px;border-radius:6px;margin:1px 0}}
.row.sel{{background:var(--selected);font-weight:600}}
.row .n{{margin-left:auto;color:var(--dim);font-size:12.5px;font-feature-settings:"tnum"}}
.sec{{font-size:12px;font-weight:700;color:var(--dim);padding:14px 12px 4px;letter-spacing:.02em}}
.main{{flex:1;display:flex;flex-direction:column;min-width:0;background:var(--bg)}}
.scroll{{flex:1;overflow:hidden;position:relative}}
.col{{max-width:880px;margin:0 auto;padding:22px 36px}}
h1{{font-size:24px;font-weight:800;margin:8px 0 2px}}
h2{{font-size:15px;font-weight:700;margin:22px 0 10px}}
.dim{{color:var(--dim)}} .small{{font-size:12.5px}}
.card{{background:var(--card);border:1px solid var(--border);border-radius:12px;box-shadow:0 1px 2px var(--shade)}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(176px,1fr));gap:12px}}
.book{{padding:14px 14px 12px;height:128px;display:flex;flex-direction:column;position:relative;overflow:hidden}}
.book .t{{font-family:"DejaVu Serif",serif;font-size:15px;line-height:1.3;font-weight:600}}
.book .m{{margin-top:auto;font-size:12px;color:var(--dim)}}
.book .spine{{position:absolute;left:0;top:0;bottom:0;width:4px;background:var(--accent);opacity:.55}}
.bar{{height:4px;border-radius:2px;background:var(--selected);overflow:hidden}} .bar>i{{display:block;height:100%;background:var(--accent)}}
.reading{{font-family:"DejaVu Serif",serif;font-size:22px;line-height:1.56;color:var(--fg)}}
.reading p{{margin:0 0 18px}}
.eyebrow{{font-size:12.5px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--dim)}}
.rtitle{{font-size:26px;font-weight:800;color:var(--accent);margin:6px 0 4px;font-family:"Adwaita Sans",sans-serif}}
.cite{{font-family:"DejaVu Serif",serif;font-style:italic;font-size:18px;color:var(--dim);margin-top:6px}}
mark{{color:inherit;border-radius:3px;padding:1px 0}}
.hl-y{{background:{p['hl_yellow']}}} .hl-g{{background:{p['hl_green']}}} .hl-b{{background:{p['hl_blue']}}} .hl-m{{background:{p['hl_magenta']}}}
.fade{{position:absolute;left:0;right:0;bottom:0;height:34px;background:linear-gradient(to bottom,transparent,var(--bg));pointer-events:none}}
.foot{{flex:none;border-top:1px solid var(--border);padding:8px 18px 10px;display:flex;align-items:center;gap:14px}}
.foot .prog{{flex:1}}
.foot .lbl{{display:flex;justify-content:space-between;font-size:12.5px;color:var(--dim);margin-bottom:6px;font-feature-settings:"tnum"}}
.note{{position:absolute;width:250px;padding:12px 14px;font-size:13.5px;line-height:1.4}}
.pin{{display:inline-flex;vertical-align:super;width:18px;height:18px;border-radius:9px;background:var(--accent);color:var(--accent-fg);font:700 11px "Adwaita Sans";align-items:center;justify-content:center;margin-left:2px}}
.toc .row{{height:auto;min-height:36px;padding:7px 10px;align-items:flex-start;font-size:13.5px;line-height:1.3}}
.toc .row .n{{padding-top:1px}}
.chip{{display:inline-flex;align-items:center;gap:6px;height:28px;padding:0 12px;border-radius:99px;background:var(--selected);font-size:13px;font-weight:600}}
.chip.on{{background:var(--accent);color:var(--accent-fg)}}
.swatch{{width:18px;height:18px;border-radius:9px;display:inline-block;border:1px solid var(--border)}}
.tag{{font-size:11.5px;font-weight:700;color:var(--accent);text-transform:uppercase;letter-spacing:.05em}}
.annot{{position:absolute;font:600 12.5px "Adwaita Sans";background:#fff3b0;color:#3b3200;border:1px solid #e0c95a;border-radius:8px;padding:6px 9px;max-width:230px;line-height:1.35;box-shadow:0 2px 6px rgba(0,0,0,.12);z-index:9}}
"""

def page(name, body, p=FLEXOKI, width=1280, note=None):
    notes = f'<div class="annot" style="{note[0]}">{note[1]}</div>' if note else ""
    (out / f"{name}.html").write_text(f'<!doctype html><meta charset="utf-8"><style>{css(p,width)}</style><body>{body}{notes}</body>')

def sidebar(sel, extra="", counts=True):
    rows = [("home", "go-home-symbolic", "Home", ""), ("prayers", "emoji-nature-symbolic", "Prayers", "472"),
            ("writings", "accessories-dictionary-symbolic", "Writings", "18 books"), ("saved", "starred-symbolic", "Saved", "12")]
    r = "".join(f'<div class="row{" sel" if k==sel else ""}">{icon(i)}<span>{t}</span><span class="n">{n if counts else ""}</span></div>' for k, i, t, n in rows)
    return f'''<div class="side"><div class="hb"><span class="btn">{icon("system-search-symbolic")}</span><div class="title">Bahá’í Reader</div><span class="btn">{icon("open-menu-symbolic")}</span></div>
<div class="nav">{r}</div>{extra}</div>'''

def paras(text, limit=None):
    ps = [x.strip() for x in text.split("\n\n") if x.strip()]
    return ps[:limit] if limit else ps

# ---------- Home / library ----------
AUTHORS = [("Bahá’u’lláh", [("The Hidden Words", "153 passages"), ("Gleanings from the Writings of Bahá’u’lláh", "166 passages"),
                            ("The Kitáb-i-Íqán", "2 parts · 287 ¶"), ("The Kitáb-i-Aqdas", "Text, Q&A, Notes"), ("Prayers and Meditations", "184 passages"),
                            ("Tablets of Bahá’u’lláh", "19 tablets"), ("Epistle to the Son of the Wolf", "1 work · 46k words"), ("Days of Remembrance", "45 selections")]),
           ("‘Abdu’l‑Bahá", [("Some Answered Questions", "5 parts · 84 chapters")]),
           ("Shoghi Effendi", [("God Passes By", "4 periods · 27 chapters"), ("The World Order of Bahá’u’lláh", "10 letters"), ("The Advent of Divine Justice", "57 passages"),
                               ("The Promised Day Is Come", "34 passages"), ("Bahá’í Administration", "55 letters"), ("Citadel of Faith", "120 passages"), ("This Decisive Hour", "165 messages")]),
           ("The Universal House of Justice", [("Riḍván Messages", "65 messages"), ("Messages of the Universal House of Justice", "450 messages")])]

def library(cols=None):
    s = ""
    for author, books in AUTHORS:
        cards = "".join(f'<div class="card book"><span class="spine"></span><div class="t">{E(t)}</div><div class="m">{E(m)}</div></div>' for t, m in books)
        s += f'<h2>{E(author)} <span class="dim small" style="font-weight:400">· {len(books)}</span></h2><div class="grid"{cols or ""}>{cards}</div>'
    return s

today_strip = f'''<div style="display:grid;grid-template-columns:1.25fr 1fr 1fr;gap:12px">
<div class="card" style="padding:14px 16px"><div class="tag">Today</div><div style="font-family:DejaVu Serif;font-size:22px;color:var(--accent);margin:6px 0 2px">8 Qudrat 183 B.E.</div>
<div class="small dim">Wednesday 11 November 2026 · Month of Power</div><div class="small" style="margin-top:8px"><b>Birth of Bahá’u’lláh</b> · work is suspended</div></div>
<div class="card" style="padding:14px 16px"><div class="tag">Short Obligatory Prayer</div><div style="margin:8px 0 4px;font-weight:600">Opens at 11:34, until 16:33</div>
<div class="small dim">Not yet said today</div><div style="margin-top:10px;display:flex;gap:8px"><span class="btn raised">{icon("object-select-symbolic")} Mark as said</span></div></div>
<div class="card" style="padding:14px 16px"><div class="tag">Passage of the day</div><div style="font-family:DejaVu Serif;font-size:15px;line-height:1.45;margin-top:8px">“O SON OF SPIRIT! The best beloved of all things in My sight is Justice…”</div>
<div class="small dim" style="margin-top:6px">The Hidden Words, Arabic no. 2</div></div></div>'''

continue_reading = f'''<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px">
{"".join(f'<div class="card" style="padding:12px 14px"><div class="small dim">{a}</div><div style="font-weight:700;margin:3px 0 8px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{b}</div><div class="bar"><i style="width:{w}%"></i></div><div class="small dim" style="margin-top:6px;display:flex;justify-content:space-between"><span>{c}</span><span>{w}%</span></div></div>' for a,b,c,w in [("God Passes By","II. The Báb’s Captivity in Ádhirbáyján","Chapter 3 of 27",9),("Gleanings","XXVII","Passage 27 of 166",16),("The Kitáb-i-Íqán","Part 1, ¶ 48","¶ 48 of 287",17)])}</div>'''

home = f'''<div class="win">{sidebar("home")}<div class="main"><div class="hb"><div class="title">Home</div><span class="btn">{icon("system-search-symbolic")}<span class="kbd">Ctrl+K</span></span><span class="btn text">Aa</span><span class="btn">{icon("view-more-symbolic")}</span></div>
<div class="scroll"><div class="col">{today_strip}<h2>Continue reading</h2>{continue_reading}<h2 style="margin-top:26px;font-size:18px">Library</h2>{library()}</div><div class="fade"></div></div></div></div>'''
page("1-home", home, note=("left:16px;bottom:16px;max-width:240px", "Home replaces “Today” and the 2,901-row A–Z Writings list: the day at a glance, Continue reading, then the books as books, grouped by author. The full Today page opens from the first card."))

# ---------- Reader: Gleanings I with a highlight and a note ----------
g = data["gleanings1"]; ps = paras(g["text"], 3)
ps[0] = ps[0].replace("no tongue, however deep its wisdom, can befittingly magnify Thy name", '<mark class="hl-y">no tongue, however deep its wisdom, can befittingly magnify Thy name</mark><span class="pin">1</span>')
gl_toc = "".join(f'<div class="row{" sel" if k==0 else ""}"><span>{E(t.split(" · ")[0])}</span><span class="dim" style="overflow:hidden;white-space:nowrap;text-overflow:ellipsis;flex:1">{E(t.split(" · ",1)[1][:38])}</span></div>' for k, t in enumerate(data["gleanings_titles"][:13]))
reader_side = f'''<div class="side"><div class="hb"><span class="btn">{icon("go-previous-symbolic")}</span><div class="title">Gleanings<small>Bahá’u’lláh · 166 passages</small></div><span class="btn">{icon("system-search-symbolic")}</span></div>
<div class="sec">CONTENTS</div><div class="nav toc">{gl_toc}</div></div>'''
words = g["words"]; done = round(100 * words[0] / sum(words))
reader_main = f'''<div class="main"><div class="hb"><span class="btn">{icon("sidebar-show-symbolic")}</span><div class="title">Gleanings from the Writings of Bahá’u’lláh<small>I · Bahá’u’lláh</small></div>
<span class="btn">{icon("system-search-symbolic")}</span><span class="btn text">Aa</span><span class="btn">{icon("starred-symbolic")}</span><span class="btn">{icon("edit-copy-symbolic")}</span><span class="btn">{icon("view-fullscreen-symbolic")}</span><span class="btn">{icon("view-more-symbolic")}</span></div>
<div class="scroll"><div class="col" style="max-width:780px;padding-top:30px"><div class="eyebrow">Gleanings from the Writings of Bahá’u’lláh</div><div class="rtitle">I</div><div class="small dim" style="margin-bottom:22px">Passage 1 of 166 · about 2 minutes</div>
<div class="reading">{"".join(f"<p>{x}</p>" for x in ps)}</div></div>
<div class="card note" style="left:640px;top:270px;box-shadow:0 8px 28px rgba(0,0,0,.18)"><div style="position:absolute;top:-7px;left:118px;width:12px;height:12px;background:var(--card);border-left:1px solid var(--border);border-top:1px solid var(--border);transform:rotate(45deg)"></div><div class="tag" style="margin-bottom:4px">Note 1 · highlighted</div>Read with the Long Obligatory Prayer: “Too high art Thou for the praise of those who are nigh unto Thee…”<div class="dim small" style="margin-top:8px;display:flex;gap:8px;align-items:center"><span class="swatch" style="background:{FLEXOKI['hl_yellow']}"></span><span class="swatch" style="background:{FLEXOKI['hl_green']}"></span><span class="swatch" style="background:{FLEXOKI['hl_blue']}"></span><span class="swatch" style="background:{FLEXOKI['hl_magenta']}"></span><span style="margin-left:auto">Edit · Remove</span></div></div>
<div class="fade"></div></div>
<div class="foot"><span class="btn raised">{icon("go-previous-symbolic")}</span><div class="prog"><div class="lbl"><span>Gleanings · Passage 1 of 166</span><span>{done}% of the book</span></div><div class="bar"><i style="width:{max(done,1)}%"></i></div></div><span class="btn suggested pill">Next {icon("go-next-symbolic")}</span></div></div>'''
page("2-reader", f'<div class="win">{reader_side}{reader_main}</div>', note=("left:16px;bottom:16px;max-width:240px", "The sidebar becomes the book’s contents while a book is open (← back to the library). Footer: progress through the whole book by words, not just “1 of 166”. Highlights in four theme colours; a numbered pin opens the note."))

# ---------- Reader with contents for a long work: God Passes By ----------
gp = data["gpb2"]; gps = paras(gp["text"], 6)
gpb = data["gpb"]; total = sum(c["words"] for c in gpb); before = sum(c["words"] for c in gpb[:2]); pct = round(100 * before / total)
toc = ""; cur = None
for k, c in enumerate(gpb):
    if c["sub"] != cur:
        cur = c["sub"]
        if cur: toc += f'<div class="sec" style="padding-top:10px;text-transform:none;letter-spacing:0">{E(cur)}</div>'
    toc += f'<div class="row{" sel" if k==2 else ""}"><span style="flex:1">{E(c["title"])}</span><span class="n">{round(c["words"]/250)} min</span></div>'
    if k > 9: break
gpb_side = f'''<div class="side" style="width:300px"><div class="hb"><span class="btn">{icon("go-previous-symbolic")}</span><div class="title">God Passes By<small>Shoghi Effendi · 27 chapters</small></div><span class="btn">{icon("system-search-symbolic")}</span></div>
<div class="nav toc" style="overflow:hidden">{toc}</div></div>'''
gpb_main = f'''<div class="main"><div class="hb"><span class="btn">{icon("sidebar-show-symbolic")}</span><div class="title">God Passes By<small>First Period · Chapter II</small></div>
<span class="btn">{icon("system-search-symbolic")}</span><span class="btn text">Aa</span><span class="btn">{icon("starred-symbolic")}</span><span class="btn">{icon("edit-copy-symbolic")}</span><span class="btn">{icon("view-fullscreen-symbolic")}</span><span class="btn">{icon("view-more-symbolic")}</span></div>
<div class="scroll"><div class="col" style="max-width:780px;padding-top:30px"><div class="eyebrow">God Passes By · First Period: The Ministry of the Báb 1844–1853</div><div class="rtitle">II. The Báb’s Captivity in Ádhirbáyján</div><div class="small dim" style="margin-bottom:22px">Chapter 3 of 27 · about {round(gpb[2]["words"]/250)} minutes</div>
<div class="reading">{"".join(f"<p>{E(x)}</p>" for x in gps)}</div></div><div class="fade"></div></div>
<div class="foot"><span class="btn raised">{icon("go-previous-symbolic")}</span><div class="prog"><div class="lbl"><span>Chapter 3 of 27 · 4% through this chapter</span><span>{pct}% of the book</span></div><div class="bar" style="position:relative"><i style="width:{pct+1}%"></i></div></div><span class="btn suggested pill">Next {icon("go-next-symbolic")}</span></div></div>'''
page("3-reader-contents", f'<div class="win">{gpb_side}{gpb_main}</div>', note=("left:16px;bottom:16px;max-width:265px", "Long works get real contents: parts and chapters with reading time, the current chapter selected, and both chapter and book progress in the footer."))

# ---------- Today ----------
def tcard(tag, inner, style=""): return f'<div class="card" style="padding:16px 18px;{style}"><div class="tag">{tag}</div>{inner}</div>'
up = [("Birth of Bahá’u’lláh", "Today · work is suspended", "Readings"), ("Feast of Qawl (Speech)", "23 November · begins at sunset on 22 November", ""),
      ("Day of the Covenant", "26 November", "Readings"), ("Ascension of ‘Abdu’l‑Bahá", "28 November · work is suspended", "Readings")]
uprows = "".join(f'<div style="display:flex;align-items:center;padding:9px 0;border-top:1px solid var(--border)"><div><div style="font-weight:600">{a}</div><div class="small dim">{b}</div></div>{f"<span class=\"btn raised\" style=\"margin-left:auto\">{c}</span>" if c else ""}</div>' for a, b, c in up)
today = f'''<div class="win">{sidebar("home")}<div class="main"><div class="hb"><span class="btn">{icon("go-previous-symbolic")}</span><div class="title">Today<small>Chicago, United States</small></div><span class="btn">{icon("system-search-symbolic")}<span class="kbd">Ctrl+K</span></span><span class="btn">{icon("view-more-symbolic")}</span></div>
<div class="scroll"><div class="col" style="max-width:760px;display:flex;flex-direction:column;gap:12px">
{tcard("Badí‘ date", '<div style="font-family:DejaVu Serif;font-size:30px;color:var(--accent);margin:6px 0 4px">8 Qudrat 183 B.E.</div><div class="dim">Wednesday 11 November 2026 · the month of Qudrat, Power. The Badí‘ day began at sunset.</div>')}
<div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
{tcard("Short Obligatory Prayer", f'<div style="font-size:17px;font-weight:700;margin:8px 0 2px">Open from 11:34 until 16:33</div><div class="small dim">Said today? Mark it here or under the prayer; reminders stop once it is marked.</div><div style="display:flex;gap:8px;margin-top:12px"><span class="btn suggested">Open the prayer</span><span class="btn raised">{icon("object-select-symbolic")} Mark as said</span></div>')}
{tcard("Sun", f'<div style="display:grid;grid-template-columns:repeat(3,1fr);margin-top:10px;text-align:center"><div><div style="font-size:20px;font-weight:700;font-feature-settings:tnum">06:35</div><div class="small dim">Sunrise</div></div><div><div style="font-size:20px;font-weight:700">11:34</div><div class="small dim">Noon</div></div><div><div style="font-size:20px;font-weight:700">16:33</div><div class="small dim">Sunset</div></div></div>')}
</div>
{tcard("Holy Days and Feasts", f'<div style="margin-top:6px">{uprows}</div>')}
{tcard("Passage of the day", f'<div class="reading" style="font-size:19px;margin-top:8px">{E(paras(data["hw2"]["text"])[0])}</div><div class="cite" style="font-size:15px">— {E(data["hw2"]["citation"].split(". Copyright")[0])}</div>')}
</div><div class="fade"></div></div></div></div>'''
page("4-today", today, note=("left:16px;bottom:16px;max-width:240px", "The full Today page opens from Home’s first card. “Said today” now says what it does and where else it can be set."))

# ---------- Saved: collections + highlights & notes ----------
hl = [("y", "no tongue, however deep its wisdom, can befittingly magnify Thy name", "Gleanings, I", "Read with the Long Obligatory Prayer."),
      ("g", "The best beloved of all things in My sight is Justice", "The Hidden Words, Arabic no. 2", ""),
      ("b", "O God, my God! I beg of Thee by the ocean of Thy healing", "Prayers · Healing", "For Mum, every evening."),
      ("m", "Free thyself from the fetters of this world", "The Hidden Words, Persian no. 40", "")]
hlrows = "".join(f'<div class="card" style="padding:14px 16px;margin-bottom:10px"><div class="reading" style="font-size:17px;line-height:1.5"><mark class="hl-{c}">{E(t)}</mark></div><div class="small dim" style="margin-top:6px">{E(s)}</div>{f"<div style=\"margin-top:8px;font-size:14px;border-left:3px solid var(--accent);padding-left:10px\">{E(n)}</div>" if n else ""}</div>' for c, t, s, n in hl)
cols = [("Morning", 4), ("For the Fast", 3), ("Unsorted", 5)]
side_saved = sidebar("saved", f'<div class="sec">COLLECTIONS</div><div class="nav">{"".join(f"<div class=\"row{" sel" if i==0 else ""}\">{icon("folder-symbolic")}<span>{a}</span><span class=\"n\">{b}</span></div>" for i,(a,b) in enumerate(cols))}<div class="row dim">{icon("bookmark-new-symbolic")}<span>New collection…</span></div></div>')
saved = f'''<div class="win">{side_saved}<div class="main"><div class="hb"><div class="title">Saved</div><span class="btn">{icon("system-search-symbolic")}<span class="kbd">Ctrl+K</span></span><span class="btn">{icon("view-more-symbolic")}</span></div>
<div class="scroll"><div class="col" style="max-width:820px"><div style="display:flex;gap:8px;margin:4px 0 18px"><span class="chip">Passages · 12</span><span class="chip on">Highlights &amp; notes · 4</span></div>
<div style="display:flex;gap:8px;margin-bottom:14px;align-items:center"><span class="small dim">Colour</span><span class="swatch" style="background:{FLEXOKI['hl_yellow']}"></span><span class="swatch" style="background:{FLEXOKI['hl_green']}"></span><span class="swatch" style="background:{FLEXOKI['hl_blue']}"></span><span class="swatch" style="background:{FLEXOKI['hl_magenta']}"></span><span class="small dim" style="margin-left:auto">Newest first</span></div>
{hlrows}</div><div class="fade"></div></div></div></div>'''
page("5-saved", saved, note=("left:16px;bottom:16px;max-width:240px", "Saved is a first-class sidebar tab: collections in the sidebar, and every highlight and note in one place, each opening its passage."))

# ---------- Ctrl+K search ----------
SR = json.loads((Path(sys.argv[1]).parent/"search.json").read_text())
res = {}
for book, title, snippet in SR["rows"]: res.setdefault(book, []).append((E(title), snippet))
res = list(res.items())
rr = "".join(f'<div class="sec" style="padding-left:16px">{E(b)}</div>' + "".join(f'<div class="row{" sel" if (i==0 and j==0) else ""}" style="height:auto;padding:9px 16px;flex-direction:column;align-items:flex-start;gap:2px;margin:0 6px"><span style="font-weight:600">{t}</span><span class="small dim" style="line-height:1.4">{s}</span></div>' for j, (t, s) in enumerate(items)) for i, (b, items) in enumerate(res))
search = f'''<div class="win" style="filter:saturate(.9)">{reader_side}{reader_main}</div><div style="position:absolute;inset:0;background:rgba(0,0,0,.28)"></div>
<div class="card" style="position:absolute;left:50%;top:70px;transform:translateX(-50%);width:640px;background:var(--bg);box-shadow:0 12px 40px rgba(0,0,0,.25);overflow:hidden">
<div style="display:flex;align-items:center;gap:10px;padding:14px 16px;border-bottom:1px solid var(--border)">{icon("system-search-symbolic")}<span style="font-size:17px;flex:1">justice<span style="border-left:2px solid var(--accent);margin-left:1px"></span></span><span class="kbd">Esc</span></div>
<div style="display:flex;gap:8px;padding:10px 16px;border-bottom:1px solid var(--border);align-items:center"><span class="chip">This book · {SR["gleanings"]}</span><span class="chip on">Everything · {SR["total"]}</span><span class="small dim" style="margin-left:auto">Ignores accents and apostrophes · offline</span></div>
<div style="padding:4px 0 10px">{rr}</div><div class="small dim" style="padding:8px 16px;border-top:1px solid var(--border);display:flex;gap:16px"><span>↑↓ choose</span><span>Enter open</span><span>Tab switch scope</span></div></div>'''
page("6-search", search, note=("left:24px;bottom:24px", "Ctrl+K from anywhere: one search over everything, or only the open book. Results are grouped by book; Enter opens the passage at the match. (Not Super: no clash with Omarchy.)"))

# ---------- Focus mode ----------
focus = f'''<div class="main" style="height:800px"><div class="scroll"><div class="col" style="max-width:760px;padding-top:70px"><div class="eyebrow" style="opacity:.6">Gleanings · I</div>
<div class="reading" style="margin-top:22px">{"".join(f"<p>{x}</p>" for x in paras(g["text"], 4))}</div></div><div class="fade" style="height:60px"></div></div>
<div style="height:3px;background:var(--selected)"><div style="height:3px;width:2%;background:var(--accent)"></div></div></div>'''
page("7-focus", focus, note=("right:24px;top:24px", "Focus mode (F11 or the ⛶ button): sidebar and header hide; only the text and a 3 px progress line remain. Mouse to the top edge or Esc brings the chrome back."))

# ---------- Narrow (420 px): library, then reader ----------
narrow_home = f'''<div class="main" style="height:800px"><div class="hb"><span class="btn">{icon("sidebar-show-symbolic")}</span><div class="title">Home</div><span class="btn">{icon("system-search-symbolic")}</span><span class="btn">{icon("view-more-symbolic")}</span></div>
<div class="scroll"><div class="col" style="padding:14px 14px">
<div class="card" style="padding:12px 14px;margin-bottom:10px"><div class="tag">Today</div><div style="font-family:DejaVu Serif;font-size:20px;color:var(--accent);margin:4px 0 2px">8 Qudrat 183 B.E.</div><div class="small dim">Birth of Bahá’u’lláh · Short prayer opens 11:34</div></div>
<div class="card" style="padding:12px 14px"><div class="small dim">Continue · God Passes By</div><div style="font-weight:700;margin:3px 0 8px">II. The Báb’s Captivity in Ádhirbáyján</div><div class="bar"><i style="width:9%"></i></div></div>
{library(' style="grid-template-columns:1fr 1fr"')}</div><div class="fade"></div></div></div>'''
page("8-narrow-home", narrow_home, width=420, note=("left:12px;bottom:12px", "Narrow window: the split view collapses; the sidebar slides over and Home is one column with two-up book cards."))
narrow_reader = f'''<div class="main" style="height:800px"><div class="hb"><span class="btn">{icon("go-previous-symbolic")}</span><div class="title">Gleanings<small>I</small></div><span class="btn text">Aa</span><span class="btn">{icon("view-more-symbolic")}</span></div>
<div class="scroll"><div class="col" style="padding:22px 22px"><div class="eyebrow">Gleanings</div><div class="rtitle" style="font-size:22px">I</div><div class="reading" style="font-size:20px;margin-top:14px">{"".join(f"<p>{x}</p>" for x in ps[:2])}</div></div><div class="fade"></div></div>
<div class="foot" style="padding:8px 12px"><span class="btn raised">{icon("go-previous-symbolic")}</span><div class="prog"><div class="lbl"><span>1 of 166</span><span>{done}%</span></div><div class="bar"><i style="width:2%"></i></div></div><span class="btn suggested">{icon("go-next-symbolic")}</span></div></div>'''
page("9-narrow-reader", narrow_reader, width=420, note=("left:12px;bottom:62px", "Reader at 420 px: back goes to the contents; the footer keeps book progress."))

# ---------- Dark: the reader in the app's Dark palette ----------
page("10-reader-dark", f'<div class="win">{reader_side}{reader_main}</div>'.replace(FLEXOKI["hl_yellow"], DARK["hl_yellow"]), p=DARK,
     note=("left:16px;bottom:16px;max-width:240px", "The same reader on the Dark palette: the theme maps onto libadwaita’s named colours, so every widget follows without per-widget CSS."))
print("written", sorted(x.name for x in out.glob("*.html")))
