"""Saved passages and collections."""
from gi.repository import Gtk, Gdk

from . import marks
from .library import load_library
from .settings import UNSORTED, collection_name

class SavedMixin:
    """Reader methods: saved passages and collections."""
    # ----- stored ids in the current language -----
    def passage_of(self,key):
        """The current library's passage for a stored id (a saved passage, a collection entry or a highlight), following an id
        from another language to the passage numbered the same here; None when this library has no counterpart."""
        cache=getattr(self,"follow_cache",None)
        if cache is None or cache[0] is not self.items:
            items=self.items
            cache=self.follow_cache=(items,{i["id"]:i for i in items},{i["match"]:i for i in items if i["match"]},{})
        _,by_id,by_match,known=cache
        if key not in known: known[key]=marks.follow(key,by_id,by_match,self.matches_in)
        return known[key]

    def matches_in(self,language):
        """{passage id: alignment key} of a language's library, read once; empty if that language is not downloaded."""
        known=getattr(self,"match_ids",None)
        if known is None: known=self.match_ids={}
        if language not in known:
            if language==self.language: items=self.items
            else:
                try: items=load_library(language)
                except (OSError,ValueError,KeyError,TypeError): items=[]
            known[language]={i["id"]:i["match"] for i in items if i["match"]}
        return known[language]

    def saved_keys(self,item=None):
        """The stored ids under which a passage is saved: its own id, or the id of the same passage in another language."""
        item=item or self.current
        if not item: return []
        return [k for k in self.prefs.get("saved",[]) if k==item["id"] or (self.passage_of(k) or {}).get("id")==item["id"]]

    def saved_key(self,item=None):
        keys=self.saved_keys(item)
        return keys[0] if keys else None

    def filed(self):
        """{collection name: saved passages in it} for this language, then Unsorted. Passages saved in another language are
        shown as this language's passage of the same number, once."""
        groups={}; seen=set()
        def passages(keys):
            result=[]
            for key in keys:
                item=self.passage_of(key)
                if item is not None and item["id"] not in seen: seen.add(item["id"]); result.append(item)
            return result
        for collection in self.prefs.get("collections",[]): groups[collection["name"]]=passages(collection["items"])
        groups[UNSORTED]=passages(self.prefs.get("saved",[]))
        return groups

    def collection_of(self,key):
        return next((c["name"] for c in self.prefs.get("collections",[]) if key in c["items"]),None)

    def show_filing(self):
        key=self.saved_key() if self.current else None
        self.filing.set_visible(key is not None)
        if key is None: return
        self.filling=True
        self.collection.remove_all(); self.collection.append("",UNSORTED)
        for collection in self.prefs.get("collections",[]): self.collection.append(collection["name"],collection["name"])
        self.collection.set_active_id(self.collection_of(key) or "")
        self.filling=False

    def file_current(self,choice):
        if self.filling or not self.current or choice.get_active_id() is None: return
        key=self.saved_key()
        if key is not None: self.move_passage(key,choice.get_active_id() or None)

    def move_passage(self,key,name):
        """Files a saved passage in the named collection, or in none (Unsorted)."""
        if key not in self.prefs.get("saved",[]) or name==self.collection_of(key): return
        for collection in self.prefs.get("collections",[]):
            if key in collection["items"]: collection["items"].remove(key)
            if collection["name"]==name: collection["items"].append(key)
        self.save()
        if self.section=="saved": self.rebuild()

    def name_problem(self,name,current=None):
        if not name: return "Type a name for the collection."
        if name.casefold()==UNSORTED.casefold(): return f"“{UNSORTED}” is where passages outside a collection go; choose another name."
        if any(c["name"].casefold()==name.casefold() and c["name"]!=current for c in self.prefs.get("collections",[])): return f"There is already a collection called “{name}”."
        return None

    def create_collection(self,name):
        """Returns a problem to show, or None once created."""
        name=collection_name(name); problem=self.name_problem(name)
        if problem: return problem
        self.prefs.setdefault("collections",[]).append({"name":name,"items":[]}); self.collections_changed(); return None

    def rename_collection(self,old,new):
        new=collection_name(new); problem=self.name_problem(new,current=old)
        if problem: return problem
        for collection in self.prefs.get("collections",[]):
            if collection["name"]==old: collection["name"]=new
        expanded=self.prefs.get("expanded",{})
        if f"saved/{old}" in expanded: expanded[f"saved/{new}"]=expanded.pop(f"saved/{old}")
        self.collections_changed(); return None

    def delete_collection(self,name):
        """Removes the collection only; its passages stay saved, under Unsorted."""
        self.prefs["collections"]=[c for c in self.prefs.get("collections",[]) if c["name"]!=name]
        self.prefs.get("expanded",{}).pop(f"saved/{name}",None); self.collections_changed()

    def collections_changed(self):
        self.save(); self.show_filing()
        if self.section=="saved": self.rebuild()
        if getattr(self,"collections_window",None): self.collections_window.refresh()

    def collections_dialog(self,*_):
        if getattr(self,"collections_window",None):
            self.collections_window.present(); return
        if self.adwaita: window,box=self.settings_window("collections_window","Collections","folder-symbolic",width=460)
        else:
            window=Gtk.Window(title="Collections",transient_for=self.window,modal=True,default_width=460)
            self.collections_window=window
            keys=Gtk.EventControllerKey(); keys.connect("key-pressed",self.quit_key); window.add_controller(keys)
            keys=Gtk.EventControllerKey(); keys.connect("key-pressed",lambda _c,key,*_: key==Gdk.KEY_Escape and (window.close() or True)); window.add_controller(keys)
            box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=12)
            for edge in ("top","bottom","start","end"): getattr(box,"set_margin_"+edge)(20)
            window.set_child(box)
        box.append(Gtk.Label(label=f"Group saved passages into collections. Deleting a collection keeps its passages saved, under {UNSORTED}.",wrap=True,xalign=0,max_width_chars=52))
        rows=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=8); box.append(rows)
        message=Gtk.Label(wrap=True,xalign=0,max_width_chars=52); message.add_css_class("dim-label"); box.append(message)
        create=Gtk.Box(spacing=8); box.append(create)
        entry=Gtk.Entry(placeholder_text="New collection name",hexpand=True); create.append(entry)
        def add(*_):
            problem=self.create_collection(entry.get_text())
            message.set_text(problem or "")
            if not problem: entry.set_text("")
        entry.connect("activate",add); create.append(self.button("Create",add))
        close=self.button("Close",lambda *_: window.close()); close.set_halign(Gtk.Align.END); box.append(close)
        def refresh():
            while child:=rows.get_first_child(): rows.remove(child)
            if not self.prefs.get("collections"): rows.append(Gtk.Label(label="No collections yet.",xalign=0))
            for collection in self.prefs.get("collections",[]):
                line=Gtk.Box(spacing=8); rows.append(line)
                name=Gtk.Entry(text=collection["name"],hexpand=True); line.append(name)
                count=len(collection["items"]); total=Gtk.Label(label=f"{count} passage{'s' if count!=1 else ''}"); total.add_css_class("dim-label"); line.append(total)
                def rename(*_,old=collection["name"],field=name):
                    problem=self.rename_collection(old,field.get_text()); message.set_text(problem or "")
                name.connect("activate",rename)
                line.append(self.button("Rename",rename))
                line.append(self.button("Delete",lambda *_,n=collection["name"]: (self.delete_collection(n),message.set_text(f"Deleted “{n}”; its passages are under {UNSORTED}."))))
        window.refresh=refresh; refresh()
        def closed(*_):
            self.collections_window=None; return False
        window.connect("close-request",closed); window.present(); entry.grab_focus()
