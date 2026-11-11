"""Highlights and notes in the reading view, and the Highlights & notes page under Saved. Select words: a small bar offers four
colours and a note (Ctrl+H highlights the selection from the keyboard). Click a highlight to change its colour, write or edit
its note, or remove it. Works in both windows."""
from gi.repository import Gtk, Gdk, GLib, Pango

from . import marks
from .labels import heading
from .library import book_of

COLOR_NAMES={"yellow":"Yellow","green":"Green","blue":"Blue","magenta":"Magenta"}

class HighlightsMixin:
    """Reader methods: highlights and notes."""
    # ----- setting up -----
    def build_highlights(self):
        """Called once the reading view exists."""
        self.marks_provider=Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),self.marks_provider,Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION+1)
        buffer=self.reader.get_buffer(); table=buffer.get_tag_table()
        self.mark_tags={name:table.lookup("hl-"+name) or buffer.create_tag("hl-"+name) for name in marks.COLORS}
        self.note_tag=table.lookup("hl-note") or buffer.create_tag("hl-note",underline=Pango.Underline.SINGLE)
        self.painted=[]; self.mark_popover=None; self.selection_source=None; self.quiet_selection=None
        buffer.connect("notify::has-selection",self.selection_changed)
        click=Gtk.GestureClick(); click.connect("released",self.reader_clicked); self.reader.add_controller(click)
        self.build_marks_page()
    def recolor_highlights(self):
        for name,tag in getattr(self,"mark_tags",{}).items():
            rgba=Gdk.RGBA(); rgba.parse(self.highlight_rgba[name]); tag.set_property("background-rgba",rgba)
    def highlights(self):
        return self.prefs.setdefault("highlights",[])

    # ----- drawing -----
    def paint_highlights(self):
        """The current passage's highlights, drawn over the text."""
        if not getattr(self,"mark_tags",None): return
        buffer=self.reader.get_buffer(); start,end=buffer.get_bounds()
        for tag in [*self.mark_tags.values(),self.note_tag]: buffer.remove_tag(tag,start,end)
        self.painted=[]
        if not self.current: return
        text=self.current["text"]
        for record in marks.of_passage(self.highlights(),self.current["id"]):
            place=marks.anchor(text,record)
            if not place: continue
            if place!=(record["start"],record["end"]): record["start"],record["end"]=place  # the text moved; follow it
            a,b=buffer.get_iter_at_offset(place[0]),buffer.get_iter_at_offset(place[1])
            buffer.apply_tag(self.mark_tags[record["color"]],a,b)
            if record.get("note"): buffer.apply_tag(self.note_tag,a,b)
            self.painted.append(record)
    def highlight_at(self,offset):
        return next((r for r in self.painted if r["start"]<=offset<r["end"]),None)

    # ----- the bar on a selection -----
    def selected_span(self):
        """The selected part of the passage's own text (not its citation), or None."""
        if not self.current or not self.on_passage(): return None
        bounds=self.reader.get_buffer().get_selection_bounds()
        if not bounds: return None
        start,end=bounds[0].get_offset(),min(bounds[1].get_offset(),len(self.current["text"]))
        return (start,end) if start<end and self.current["text"][start:end].strip() else None
    def selection_changed(self,buffer,_):
        if self.selection_source: GLib.source_remove(self.selection_source); self.selection_source=None
        span=self.selected_span()
        if not span or span==self.quiet_selection: return
        def show():
            self.selection_source=None
            if self.selected_span()==span: self.show_mark_bar(span)
            return False
        # Once the selection has settled (a drag, or Shift+arrows), not on every step of it.
        self.selection_source=GLib.timeout_add(450,show)
    def popover_at(self,offset,end=None):
        """A popover pointing at the text at offset (to end), parented to the reading view."""
        if self.mark_popover: self.mark_popover.popdown()
        buffer=self.reader.get_buffer()
        start=self.reader.get_iter_location(buffer.get_iter_at_offset(offset))
        stop=self.reader.get_iter_location(buffer.get_iter_at_offset(end if end is not None else offset))
        x,y=self.reader.buffer_to_window_coords(Gtk.TextWindowType.WIDGET,start.x,start.y)
        x2,y2=self.reader.buffer_to_window_coords(Gtk.TextWindowType.WIDGET,stop.x,stop.y)
        rect=Gdk.Rectangle(); rect.x=min(x,x2) if y==y2 else x; rect.y=y; rect.height=max(start.height,1)
        rect.width=max(1,abs(x2-x)) if y==y2 else 1
        popover=Gtk.Popover(has_arrow=True,position=Gtk.PositionType.TOP); popover.set_parent(self.reader); popover.set_pointing_to(rect)
        popover.connect("closed",lambda p:GLib.idle_add(lambda:(p.unparent() if p.get_parent() else None,self.forget_popover(p),False)[-1]))
        self.mark_popover=popover; return popover
    def forget_popover(self,popover):
        if self.mark_popover is popover: self.mark_popover=None
    def swatches(self,chosen,on_choose):
        row=Gtk.Box(spacing=8)
        for name in marks.COLORS:
            button=Gtk.Button(valign=Gtk.Align.CENTER,halign=Gtk.Align.CENTER); button.add_css_class("swatch"); button.add_css_class("circular"); button.add_css_class("swatch-"+name)
            if name==chosen: button.add_css_class("chosen")
            button.set_tooltip_text(COLOR_NAMES[name]); self.name_widget(button,f"Highlight in {COLOR_NAMES[name].lower()}")
            button.connect("clicked",lambda _,n=name:on_choose(n)); row.append(button)
        return row
    def show_mark_bar(self,span):
        """The bar over selected words: four colours, Note…, Copy."""
        popover=self.popover_at(*span)
        bar=Gtk.Box(spacing=10,margin_top=6,margin_bottom=6,margin_start=8,margin_end=8)
        bar.append(self.swatches(None,lambda name:self.highlight_selection(name)))
        bar.append(Gtk.Separator(orientation=Gtk.Orientation.VERTICAL))
        note=self.button("Note…",lambda *_:self.highlight_selection(self.prefs.get("highlight_color","yellow"),edit=True)); note.add_css_class("flat"); bar.append(note)
        copy=self.button("Copy",lambda *_:(popover.popdown(),self.copy_passage())); copy.add_css_class("flat"); bar.append(copy)
        popover.set_child(bar); self.mark_bar=bar; popover.popup()
    def highlight_selection(self,color=None,edit=False):
        """Highlights the selected words; edit opens the note at once."""
        span=self.selected_span()
        if not span: return None
        color=color or self.prefs.get("highlight_color","yellow")
        record=marks.make(self.current,*span,color=color)
        if not record: return None
        self.prefs["highlights"]=marks.add(self.highlights(),record); self.prefs["highlight_color"]=color; self.save()
        if self.mark_popover: self.mark_popover.popdown()
        buffer=self.reader.get_buffer(); buffer.select_range(*([buffer.get_iter_at_offset(record["end"])]*2))
        self.paint_highlights(); self.marks_changed()
        if edit: self.edit_highlight(record,focus_note=True)
        return record

    # ----- one highlight -----
    def reader_clicked(self,gesture,presses,x,y):
        if presses!=1 or self.reader.get_buffer().get_has_selection(): return
        bx,by=self.reader.window_to_buffer_coords(Gtk.TextWindowType.WIDGET,int(x),int(y))
        found,where=self.reader.get_iter_at_location(bx,by)
        record=self.highlight_at(where.get_offset()) if found else None
        if record: self.edit_highlight(record)
    def edit_highlight(self,record,focus_note=False):
        """Colour, note and Remove for one highlight."""
        popover=self.popover_at(record["start"],record["end"])
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=10,margin_top=10,margin_bottom=10,margin_start=12,margin_end=12)
        def recolor(name):
            record["color"]=name; self.prefs["highlight_color"]=name; self.save(); self.paint_highlights(); self.marks_changed()
            for button in swatches: button.remove_css_class("chosen")
            swatches[marks.COLORS.index(name)].add_css_class("chosen")
        row=self.swatches(record["color"],recolor); box.append(row)
        swatches=[]; child=row.get_first_child()
        while child: swatches.append(child); child=child.get_next_sibling()
        label=Gtk.Label(label="Note",xalign=0); label.add_css_class("dim-label"); box.append(label)
        note=Gtk.TextView(wrap_mode=Gtk.WrapMode.WORD_CHAR,accepts_tab=False,top_margin=6,bottom_margin=6,left_margin=8,right_margin=8); note.add_css_class("note-editor")
        note.get_buffer().set_text(record.get("note",""))
        self.name_widget(note,"Note on this highlight")
        scroll=Gtk.ScrolledWindow(min_content_height=90,max_content_height=220,propagate_natural_height=True,min_content_width=300,hscrollbar_policy=Gtk.PolicyType.NEVER)
        scroll.set_child(note); scroll.add_css_class("card"); box.append(scroll)
        actions=Gtk.Box(spacing=8)
        remove=self.button("Remove highlight",lambda *_:self.remove_highlight(record)); remove.add_css_class("flat"); remove.add_css_class("destructive-action"); actions.append(remove)
        done=self.button("Done",lambda *_:popover.popdown()); done.set_hexpand(True); done.set_halign(Gtk.Align.END); done.add_css_class("suggested-action"); actions.append(done)
        box.append(actions)
        def keep_note(*_):
            buffer=note.get_buffer(); text=buffer.get_text(buffer.get_start_iter(),buffer.get_end_iter(),False).strip()[:marks.NOTE_LIMIT]
            if record in self.highlights() and text!=record.get("note",""):
                if text: record["note"]=text
                else: record.pop("note",None)
                self.save(); self.paint_highlights(); self.marks_changed()
        popover.connect("closed",keep_note)
        popover.set_child(box); self.mark_note=note; self.mark_editing=record; popover.popup()
        if focus_note: note.grab_focus()
    def remove_highlight(self,record):
        self.prefs["highlights"]=[r for r in self.highlights() if r is not record]; self.save()
        if self.mark_popover: self.mark_popover.popdown()
        self.paint_highlights(); self.marks_changed()

    # ----- Saved → Highlights & notes -----
    def build_marks_page(self):
        scroll=Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER,vexpand=True); self.views.add_named(scroll,"highlights")
        outer=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,margin_top=20,margin_bottom=28,margin_start=16,margin_end=16)
        if self.adwaita:
            clamp=self.Adw.Clamp(maximum_size=780); clamp.set_child(outer); scroll.set_child(clamp)
        else: scroll.set_child(outer)
        title=Gtk.Label(label="Highlights & notes",xalign=0); title.add_css_class("heading"); outer.append(title)
        self.marks_count=Gtk.Label(xalign=0,margin_bottom=12); self.marks_count.add_css_class("dim-label"); outer.append(self.marks_count)
        self.marks_list=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=10,width_request=-1); outer.append(self.marks_list)
        self.mark_cards=[]
    def marks_changed(self):
        if self.section=="saved": self.rebuild_marks_row()
        if self.views.get_visible_child_name()=="highlights": self.show_marks()
    def show_marks(self,*_):
        """Every highlight and note, newest first, each opening its passage at the highlight."""
        self.show_view("highlights")
        while child:=self.marks_list.get_first_child(): self.marks_list.remove(child)
        by_id={i["id"]:i for i in self.items}; records=list(reversed(self.highlights())); self.mark_cards=[]
        notes=sum(1 for r in records if r.get("note"))
        self.marks_count.set_text(f"{len(records)} highlight{'s' if len(records)!=1 else ''}, {notes} with a note" if records else
                                  "No highlights yet. Select words in a passage to highlight them in a colour or add a note; Ctrl+H highlights the selection.")
        for record in records:
            item=by_id.get(record["id"])
            card=Gtk.Button(); card.add_css_class("card"); card.add_css_class("mark-card"); card.set_sensitive(item is not None)
            line=Gtk.Box(spacing=12); bar=Gtk.Box(); bar.add_css_class("mark-bar"); bar.add_css_class("swatch-"+record["color"]); line.append(bar)
            text=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=6,hexpand=True)
            words=Gtk.Label(label=marks.excerpt(record["words"]),xalign=0,wrap=True,max_width_chars=70); words.add_css_class("today-reading"); text.append(words)
            place=" · ".join(filter(None,(book_of(item) or (item["tags"][0] if item and item["tags"] else None),heading(item)))) if item else "This passage is not in the current library."
            where=Gtk.Label(label=place,xalign=0,wrap=True); where.add_css_class("dim-label"); text.append(where)
            if record.get("note"):
                note=Gtk.Label(label=record["note"],xalign=0,wrap=True,max_width_chars=70,margin_top=2); text.append(note)
            line.append(text); card.set_child(line)
            self.name_widget(card,f"{COLOR_NAMES[record['color']]} highlight: {marks.excerpt(record['words'],120)}. {place}."+(f" Note: {record['note']}" if record.get("note") else ""))
            if item: card.connect("clicked",lambda _,r=record,i=item:self.open_highlight(r,i))
            self.marks_list.append(card); self.mark_cards.append((record,card))
        if self.adwaita: self.content_title.set_title("Highlights & notes"); self.content_title.set_subtitle(""); self.content_page.set_title("Highlights & notes")
    def open_highlight(self,record,item):
        self.open_passage(item,"Highlight")
        place=marks.anchor(item["text"],record)
        if place:
            buffer=self.reader.get_buffer(); mark=buffer.create_mark(None,buffer.get_iter_at_offset(place[0]),True)
            def scroll():
                self.reader.scroll_to_mark(mark,0.1,True,0,0.3); buffer.delete_mark(mark); return False
            GLib.idle_add(scroll)
        self.reader.grab_focus()
    def rebuild_marks_row(self):
        """The Highlights & notes row at the top of Saved's contents."""
        row=getattr(self,"marks_row",None)
        if row is None or row.get_parent() is not self.toc: return
        count=len(self.highlights()); text=f"Highlights & notes · {count}" if count else "Highlights & notes"
        row.label.set_text(text); self.name_widget(row,text.replace(" · ",", "))
    def add_marks_row(self):
        row=self.row_button(self.show_marks); row.add_css_class("toc-passage"); row.set_tooltip_text("Every highlight and note")
        line=Gtk.Box(spacing=8); row.label=Gtk.Label(xalign=0,hexpand=True); line.append(row.label); line.append(Gtk.Image(icon_name="go-next-symbolic")); row.set_child(line)
        self.toc.prepend(row); self.marks_row=row; self.rebuild_marks_row()
