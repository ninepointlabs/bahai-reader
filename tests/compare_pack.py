"""A stand-in second-language library for tests, built from the bundled English data (no network)."""
import json
from pathlib import Path

def write_pack(library,language=4,books=("prayers","hidden","iqan")):
    """Writes library/<language>.json with every text prefixed "[<language>] " and the language ids changed."""
    data=Path(__file__).resolve().parents[1]/"data"; pack={}
    for key in books:
        feed=json.loads((data/f"{key}.json").read_text())
        rows=feed["Prayers"] if key=="prayers" else feed
        for row in rows: row["LanguageId"]=language; row["Text"]=f"[{language}] "+row["Text"]
        pack[key]=feed
    library.mkdir(parents=True,exist_ok=True); (library/f"{language}.json").write_text(json.dumps(pack))
