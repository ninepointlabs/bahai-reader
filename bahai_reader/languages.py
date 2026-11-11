"""Languages & offline libraries window."""
import threading
from gi.repository import Gtk, GLib

from . import config
from .config import FEEDS, LANGUAGE_ENDPOINTS, SECTION_NAMES, atomic_json
from .library import download_language, download_problem, fetch_json, load_library, local_pack
from .widgets import Choice

class LanguagesMixin:
    """Reader methods: languages & offline libraries window."""
    def language_info(self,language=None):
        language=self.language if language is None else language
        return next((r for r in self.languages["prayers"] if r["Id"]==language), {"Name":str(language)})

    def update_status(self):
        self.status.set_text(f"{self.language_info()['Name']} · Available offline · Texts: BahaiPrayers.net"+(", bahai.org" if self.language==1 else ""))

    def use_language(self,language):
        items=load_library(language)
        if not items: raise ValueError("Download this language before switching")
        self.language=language; self.items=items; self.prefs["language"]=language; self.save(); self.compare_cache=(None,{})
        self.rebuild(); self.update_status(); self.refresh_today()

    def language_dialog(self,*_):
        if hasattr(self,"language_window") and self.language_window:
            self.language_window.present(); return
        if self.adwaita: window,box=self.settings_window("language_window","Languages & offline libraries","preferences-desktop-locale-symbolic",width=490,spacing=14)
        else:
            window=Gtk.Window(title="Languages & offline libraries",transient_for=self.window,modal=True,default_width=490)
            self.language_window=window
            keys=Gtk.EventControllerKey(); keys.connect("key-pressed",self.quit_key); window.add_controller(keys)
            box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=14)
            for edge in ("top","bottom","start","end"): getattr(box,"set_margin_"+edge)(20)
            window.set_child(box)
        intro=Gtk.Label(label="English is included. Download another language once to read it offline. Your choice is remembered.",wrap=True,xalign=0,max_width_chars=52); box.append(intro)
        choice=Choice(search=True); box.append(choice)
        info=Gtk.Label(wrap=True,xalign=0,max_width_chars=52); box.append(info)
        progress=Gtk.Label(wrap=True,xalign=0,max_width_chars=52); box.append(progress)
        action=self.row_button(lambda *_: start(False)); box.append(action)
        refresh=self.button("Update downloaded content",lambda *_: start(True)); box.append(refresh)
        update_catalog=self.button("Check available languages",lambda *_: check_catalog()); box.append(update_catalog)
        def populate(selected):
            choice.remove_all()
            available={r["Id"] for r in self.languages["prayers"] if r["Id"]==1 or local_pack(r["Id"]) is not None}
            for row in sorted(self.languages["prayers"],key=lambda r:(r["Id"] not in available,r["Id"]!=1,r.get("English",r["Name"]).casefold())):
                name=row["Name"]; english=row.get("English",name)
                label=name if name==english else f"{name} — {english}"
                if row["Id"] in available:label+=" · Offline"
                choice.append(str(row["Id"]),label)
            choice.set_active_id(str(selected))
        def details(*_):
            if choice.get_active_id() is None:return
            language=int(choice.get_active_id()); available=language==1 or local_pack(language) is not None
            books=[SECTION_NAMES[k] for k in FEEDS if any(r["Id"]==language for r in self.languages[k])]
            stored=local_pack(language)
            missing=[SECTION_NAMES[k] for k in FEEDS if language!=1 and stored is not None and k not in stored and any(r["Id"]==language for r in self.languages[k])]
            offline_state="Available offline" if available else "Download needed"
            if missing:offline_state+=" — update to add: "+", ".join(missing)
            info.set_text(offline_state+"\n\nContent offered in this language:\n"+"\n".join(books))
            action.set_label("Use this language" if available else "Download & use")
            refresh.set_sensitive(available and not self.downloading)
        def busy(value):
            self.downloading=value
            for widget in (choice,action,refresh,update_catalog):widget.set_sensitive(not value)
            if not value:details()
        def report(message):
            GLib.idle_add(progress.set_text,message)
        def start(force):
            if self.downloading:return
            language=int(choice.get_active_id())
            if not force and (language==1 or local_pack(language) is not None):
                self.use_language(language); progress.set_text("Ready to read offline."); return
            busy(True); progress.set_text("Starting download…")
            def worker():
                error=None
                try: download_language(language,self.languages,report)
                except Exception as exc:error=download_problem(exc)
                def done():
                    busy(False)
                    if error:progress.set_text("Download failed. Existing offline content is unchanged.\n"+error)
                    else:self.use_language(language); populate(language); progress.set_text("Downloaded and ready to read offline.")
                GLib.idle_add(done)
            threading.Thread(target=worker,daemon=True).start()
        def check_catalog():
            if self.downloading:return
            selected=int(choice.get_active_id()); busy(True); progress.set_text("Checking available languages…")
            def worker():
                error=None; fresh=None
                try:
                    fresh={key:fetch_json(endpoint) for key,endpoint in LANGUAGE_ENDPOINTS.items()}
                    if not all(isinstance(rows,list) and rows and all(isinstance(r,dict) and isinstance(r.get("Id"),int) and isinstance(r.get("Name"),str) for r in rows) for rows in fresh.values()):raise ValueError("Invalid language catalog")
                    atomic_json(config.LIBRARY/"languages.json",fresh)
                except Exception as exc:error=download_problem(exc)
                def done():
                    if not error:self.languages=fresh; populate(selected)
                    busy(False); progress.set_text(f"Could not update the language list. The saved list is still available.\n{error}" if error else "Language list updated.")
                GLib.idle_add(done)
            threading.Thread(target=worker,daemon=True).start()
        def close(*_):
            if self.downloading:
                progress.set_text("Please wait for the download to finish."); return True
            self.language_window=None; return False
        window.connect("close-request",close); choice.connect("changed",details)
        populate(self.language); details(); window.present()
