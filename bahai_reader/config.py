"""Where the app keeps its files, what it is called, and the collections it knows about."""
import json
import os
import tempfile
from pathlib import Path

APP_NAME = "Bahá’í Reader"

TAGLINE = "A quiet, native Linux reader for Bahá’í prayers and writings."

ORGANIZATION = "Nine Point Labs"

SUPPORT_EMAIL = "help@ninepointlabs.com"

CREATED = "September 13, 2026"  # first commit

LICENSE_NAME = "MIT License"

COPYRIGHT = "© 2026 Nine Point Labs"  # matches LICENSE

ROOT = Path(__file__).resolve().parent.parent  # the folder with reader.py, data/ and VERSION

STATE = Path(os.environ.get("XDG_CONFIG_HOME", Path.home()/".config"))/"bahai-reader"/"settings.json"

CACHE = Path(os.environ.get("XDG_CACHE_HOME", Path.home()/".cache"))/"bahai-reader"

FEEDS = {"prayers": "prayersystembylanguage?html=true&languageid=1", "hidden": "HiddensByLanguage?languageid=1", "gleanings": "GleaningsByLanguage?languageid=1"}

BOOKS = {"gleanings": "Gleanings from the Writings of Bahá’u’lláh", "meditations": "Prayers and Meditations", "tablets": "Tablets of Bahá’u’lláh", "iqan": "The Kitáb-i-Íqán"}

PRAYER_FEED_BOOKS = {"Epistle to the Son of the Wolf"}

FEEDS.update({"meditations": "PMsByLanguage?languageid=1", "tablets": "TabsByLanguage?languageid=1", "iqan": "IqansByLanguage?languageid=1"})

BOOKS.update({"aqdas":"The Kitáb-i-Aqdas", "saq":"Some Answered Questions", "days":"Days of Remembrance", "ridvan":"Riḍván Messages"})

FEEDS.update({"aqdas":"AqdasByLanguage?languageid=1&html=true", "saq":"SaqTopicsByLanguage?languageid=1", "days":"DaysRemembersByLanguage?languageid=1", "ridvan":"RidvansByLanguage?languageid=1"})

AUTOSTART = Path(os.environ.get("XDG_CONFIG_HOME", Path.home()/".config"))/"autostart"/"org.bahai.Reader-reminders.desktop"

LIBRARY = Path(os.environ.get("XDG_DATA_HOME", Path.home()/".local/share"))/"bahai-reader"/"libraries"

LANGUAGE_ENDPOINTS = {"prayers":"Languages", "hidden":"HiddenLanguages", "gleanings":"GleaningLanguages", "meditations":"PMLanguages", "tablets":"TabLanguages", "iqan":"IqanLanguages"}

LANGUAGE_ENDPOINTS.update({"aqdas":"AqdasLanguages", "saq":"SaqLanguages", "days":"DaysRememberLanguages", "ridvan":"RidvanLanguages"})

HOLY_DAYS={"NAWRUZ":"Naw-Rúz", "RIDVAN":"Riḍván", "DECLARATIONBAB":"Declaration of the Báb", "MARTYRDOMBAB":"Martyrdom of the Báb", "ASCENSIONBAHAULLAH":"Ascension of Bahá’u’lláh", "BIRTHBAB":"Birth of the Báb", "BIRTHBAHAULLAH":"Birth of Bahá’u’lláh"}

AQDAS_SECTIONS={"Paragraphs":"Text", "QAs":"Questions and Answers", "Notes":"Notes"}

SECTION_NAMES = {"prayers":"Prayers", "hidden":"The Hidden Words", **BOOKS}

PRAYER_AUTHORS={1:"The Báb", 2:"Bahá’u’lláh", 3:"‘Abdu’l‑Bahá"}

BOOK_AUTHORS={"hidden":"Bahá’u’lláh", "gleanings":"Bahá’u’lláh", "meditations":"Bahá’u’lláh", "tablets":"Bahá’u’lláh", "iqan":"Bahá’u’lláh", "aqdas":"Bahá’u’lláh", "saq":"‘Abdu’l‑Bahá", "days":"Bahá’u’lláh", "ridvan":"The Universal House of Justice"}

def shipped(*names):
    # Checkout, native package (/usr/share/licenses, icons) and AppImage layouts.
    for name in names:
        for path in (ROOT/name, ROOT.parent/name):
            if path.is_file(): return path
    return None

def version():
    path=shipped("VERSION")
    return path.read_text().strip() if path else "unknown"

def short_path(path):
    home=str(Path.home())
    return str(path).replace(home,"~",1) if str(path).startswith(home) else str(path)

def atomic_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name=tempfile.mkstemp(dir=path.parent, prefix=".download-")
    try:
        with os.fdopen(fd,"w") as file:
            json.dump(data,file,ensure_ascii=False); file.flush(); os.fsync(file.fileno())
        os.replace(name,path)
    finally:
        if os.path.exists(name): os.unlink(name)
