"""A stand-in second-language library for tests, built from the bundled English data (no network)."""
import json
from pathlib import Path

def write_pack(library,language=4,books=("prayers","hidden","iqan"),id_offset=0):
    """Writes library/<language>.json with every text prefixed "[<language>] " and the language ids changed.
    id_offset shifts the passage ids, as a real translation's ids differ from English; the numbering stays."""
    data=Path(__file__).resolve().parents[1]/"data"; pack={}
    for key in books:
        feed=json.loads((data/f"{key}.json").read_text())
        rows=feed["Prayers"] if key=="prayers" else feed
        for row in rows:
            row["LanguageId"]=language; row["Text"]=f"[{language}] "+row["Text"]
            if id_offset and isinstance(row.get("Id"),int): row["Id"]+=id_offset
        pack[key]=feed
    library.mkdir(parents=True,exist_ok=True); (library/f"{language}.json").write_text(json.dumps(pack))
