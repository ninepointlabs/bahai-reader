"""The reading pane: showing a passage, Previous/Next, Save, Copy, smooth scrolling and side by side."""
import datetime
import math
import random
from gi.repository import Gtk, Gdk, GLib, Pango

from . import config
from .citations import clipping
from .labels import heading, subtitle
from .library import directions, load_library, passage_of_the_day, reflections
from .rendering import apply_spans
from .ui import CITATION_GAP

class ReadingMixin:
    """Reader methods: the reading pane: showing a passage, Previous/Next, Save, Copy, smooth scrolling and side by side."""
    def stop_scroll(self):
        if self.scroll_tick is not None:
            self.readscroll.remove_tick_callback(self.scroll_tick); self.scroll_tick=None
        self.scroll_time=None; self.scroll_direction=0

    def reader_scroll(self,controller,dx,dy):
        event=controller.get_current_event()
        # Preserve the compositor/GTK's native pixel-precise touchpad gestures.
        if event is None or event.get_unit()!=Gdk.ScrollUnit.WHEEL:
            self.stop_scroll(); return False
        if event.get_modifier_state() & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK):
            self.stop_scroll(); return False
        if not Gtk.Settings.get_default().get_property("gtk-enable-animations"):
            self.stop_scroll(); return False
        return self.queue_scroll(dy)

    def queue_scroll(self,dy):
        if not dy:return False
        adjustment=self.readscroll.get_vadjustment()
        direction=1 if dy>0 else -1
        if self.scroll_tick is None or direction!=self.scroll_direction:
            self.scroll_target=adjustment.get_value()
        self.scroll_direction=direction
        distance=max(32,int(self.prefs.get("size",22))*2+int(self.prefs.get("spacing",8)))
        self.scroll_target=max(adjustment.get_lower(),min(adjustment.get_upper()-adjustment.get_page_size(),self.scroll_target+dy*distance))
        if self.scroll_tick is None:
            self.scroll_time=None; self.scroll_tick=self.readscroll.add_tick_callback(self.animate_scroll)
        return True

    def animate_scroll(self,widget,clock):
        now=clock.get_frame_time()
        dt=min(0.05,(now-self.scroll_time)/1_000_000) if self.scroll_time else 1/60
        self.scroll_time=now
        adjustment=self.readscroll.get_vadjustment()
        target=max(adjustment.get_lower(),min(adjustment.get_upper()-adjustment.get_page_size(),self.scroll_target))
        current=adjustment.get_value(); difference=target-current
        if abs(difference)<0.4:
            adjustment.set_value(target); self.scroll_tick=None; self.scroll_time=None; return False
        adjustment.set_value(current+difference*(1-math.exp(-dt/0.055)))
        return True

    def show_passage(self,item,group):
        self.current=item; self.active_group=group; self.prefs["last"]=item["id"]; self.save(); self.show_view("reading")
        self.position.set_text(f"{group.index(item)+1} of {len(group)}" if item in group and len(group)>1 else "")
        # The category it was opened in: the one tag its whole group shares.
        context=next((t for t in item["tags"] if all(t in g["tags"] for g in group)),None) if item in group else None
        self.heading.set_text(heading(item,context))
        self.subtitle.set_text(subtitle(item,context))
        self.reader.set_direction(Gtk.TextDirection.LTR if self.language_info().get("IsLeftToRight",True) else Gtk.TextDirection.RTL)
        self.stop_scroll()
        buffer=self.reader.get_buffer(); buffer.set_text(item["text"])
        for start,end in directions(item):
            tag=buffer.get_tag_table().lookup("direction") or buffer.create_tag("direction",style=Pango.Style.ITALIC)
            buffer.apply_tag(tag,buffer.get_iter_at_offset(start),buffer.get_iter_at_offset(end))
        apply_spans(buffer,item)
        if item["citation"]:
            tag=buffer.get_tag_table().lookup("citation") or buffer.create_tag("citation",style=Pango.Style.ITALIC,scale=0.85,pixels_above_lines=CITATION_GAP)
            buffer.insert_with_tags(buffer.get_end_iter(),"\n— "+item["citation"],tag)
        self.readscroll.get_vadjustment().set_value(0)
        self.show_second()
        self.related.set_visible(bool(item["references"]))
        if item["references"]:
            pop=Gtk.Popover(); links=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=4)
            for target,label in item["references"]:
                def jump(_,target=target):
                    other=next((i for i in self.items if i["id"]==target),None)
                    if other:self.show_passage(other,[i for i in self.items if i["tags"]==other["tags"] and i["subgroup"]==other["subgroup"]])
                links.append(self.button(label,jump))
            scroller=Gtk.ScrolledWindow(max_content_height=320,propagate_natural_height=True,min_content_width=240)
            scroller.set_child(links); pop.set_child(scroller); self.related.set_popover(pop)
        self.star.set_sensitive(True); self.update_star()
        self.copy.set_sensitive(True)
        self.show_filing(); self.show_said()
        self.highlight()

    def on_passage(self):
        """Copy, Save and Previous/Next act on the passage on show, not one behind the counter."""
        return bool(self.current) and self.views.get_visible_child_name()=="reading"

    def update_star(self):
        saved=bool(self.current) and self.current["id"] in self.prefs.get("saved",[])
        # Narrow windows show only the star; the tooltip keeps the words.
        self.star.set_label(("★" if saved else "☆")+("" if self.narrow else (" Saved" if saved else " Save")))
        self.name_widget(self.star,"Saved" if saved else "Save")

    def step(self,delta):
        if self.on_passage() and self.current in self.active_group:
            index=self.active_group.index(self.current)+delta
            if 0<=index<len(self.active_group): self.show_passage(self.active_group[index],self.active_group)

    def bookmark(self,*_):
        if not self.on_passage(): return
        saved=self.prefs.setdefault("saved",[]); key=self.current["id"]
        saved.remove(key) if key in saved else saved.append(key)
        # Unsaving takes the passage out of its collection too.
        for collection in self.prefs.get("collections",[]):
            if key in collection["items"] and key not in saved: collection["items"].remove(key)
        self.save()
        self.update_star(); self.show_filing()
        if self.section=="saved": self.rebuild()

    def copy_passage(self,*_):
        """Copies the selected words, or the whole passage, with the citation."""
        if not self.on_passage(): return None
        buffer=self.reader.get_buffer(); bounds=buffer.get_selection_bounds()
        excerpt=buffer.get_text(*bounds,False).strip() if bounds else None
        text=clipping(self.current,excerpt or None); self.window.get_clipboard().set(text)
        self.copy.set_label("Copied")
        if getattr(self,"copy_reset",None): GLib.source_remove(self.copy_reset)
        def reset():
            self.copy_reset=None; self.copy.set_label("Copy"); return False
        self.copy_reset=GLib.timeout_add(1500,reset)
        return text

    def daily_passage(self):
        item=passage_of_the_day(self.items,datetime.date.today())
        if item: self.open_passage(item,"Passage of the day")
        return item

    def random_passage(self):
        pool=[i for i in reflections(self.items) if i is not self.current]
        item=random.choice(pool) if pool else None
        if item: self.open_passage(item,"Random passage")
        return item

    def open_passage(self,item,label):
        """Shows a passage from any section, in its place in that section's contents."""
        if self.section!=item["section"]: self.navigate(item["section"])
        elif self.search.get_text(): self.search.set_text(""); self.filter()
        self.show_passage(item,self.groups[item["id"]]); self.show_content()
        self.subtitle.set_text(label+" · "+self.subtitle.get_text())

    def compare_languages(self):
        """English and every downloaded library, except the language being read."""
        downloaded=sorted(int(p.stem) for p in config.LIBRARY.glob("*.json") if p.stem.isdigit()) if config.LIBRARY.is_dir() else []
        return [l for l in dict.fromkeys([1,*downloaded]) if l!=self.language]

    def fill_compare(self):
        self.filling_compare=True
        self.compare.remove_all(); self.compare.append("","Off")
        for language in self.compare_languages():
            info=self.language_info(language); self.compare.append(str(language),info.get("English",info["Name"]))
        self.compare.set_active_id(str(self.prefs.get("compare","")) if str(self.prefs.get("compare","")) in self.compare.ids else "")
        self.filling_compare=False

    def compare_changed(self,choice):
        if self.filling_compare or choice.get_active_id() is None: return
        if choice.get_active_id(): self.prefs["compare"]=int(choice.get_active_id())
        else: self.prefs.pop("compare",None)
        self.save(); self.show_second()

    def second_items(self,language):
        """{alignment key: passage} for a language, loaded from disk once."""
        if self.compare_cache[0]!=language:
            try: items=load_library(language)
            except (OSError,ValueError,KeyError,TypeError): items=[]
            self.compare_cache=(language,{i["match"]:i for i in items if i["match"]})
        return self.compare_cache[1]

    def show_second(self):
        language=self.prefs.get("compare")
        shown=language is not None and language!=self.language and self.current is not None
        self.secondscroll.set_visible(shown)
        if not shown: return
        info=self.language_info(language); name=info.get("English",info["Name"])
        other=self.second_items(language); match=self.current.get("match"); item=other.get(match) if match else None
        buffer=self.second.get_buffer(); buffer.set_text("")
        table=buffer.get_tag_table()
        label=table.lookup("language") or buffer.create_tag("language",scale=0.7,pixels_below_lines=12)
        note=table.lookup("note") or buffer.create_tag("note",style=Pango.Style.ITALIC,scale=0.85)
        cite=table.lookup("citation") or buffer.create_tag("citation",style=Pango.Style.ITALIC,scale=0.85,pixels_above_lines=CITATION_GAP)
        buffer.insert_with_tags(buffer.get_end_iter(),info["Name"].upper()+"\n",label)
        if item:
            self.second.set_direction(Gtk.TextDirection.LTR if info.get("IsLeftToRight",True) else Gtk.TextDirection.RTL)
            start=buffer.get_char_count(); buffer.insert(buffer.get_end_iter(),item["text"]); apply_spans(buffer,item,start)
            if item["citation"]: buffer.insert_with_tags(buffer.get_end_iter(),"\n— "+item["citation"],cite)
        else:
            self.second.set_direction(Gtk.TextDirection.LTR)
            if not other: text=f"The {name} library is not downloaded or could not be read. Download it in ⋮ → Languages & offline libraries."
            elif not match: text="Prayers, Days of Remembrance and Riḍván messages are not numbered the same way in every language, so they cannot be shown side by side."
            else: text=f"This passage is not in the downloaded {name} library."
            buffer.insert_with_tags(buffer.get_end_iter(),text,note)
        self.secondscroll.get_vadjustment().set_value(0)

    def follow_scroll(self,adjustment):
        # Keep the second language at the same point in the passage, proportionally.
        if not self.secondscroll.get_visible(): return
        other=self.secondscroll.get_vadjustment(); span=adjustment.get_upper()-adjustment.get_page_size()
        if span>0: other.set_value(adjustment.get_value()/span*(other.get_upper()-other.get_page_size()))
