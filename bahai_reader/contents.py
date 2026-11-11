"""The contents list in the sidebar: sections, groups, search filtering and the Today calendar."""
from gi.repository import Gtk, Pango
import badi

from .labels import list_title, word_label
from .library import AYYAM_PRAYERS, FAST_PRAYERS, badi_days_tag, book_of, obligatory
from .search import fold
from .settings import AUTHOR_ORDER

class ContentsMixin:
    """Reader methods: the contents list in the sidebar: sections, groups, search filtering and the Today calendar."""
    def rebuild(self):
        """Build the contents tree for the section once; searching only hides rows."""
        if not hasattr(self,"toc"): return
        self.grouping.set_visible(self.section=="writings" and not self.adwaita)
        saved=self.prefs.get("saved",[])
        self.section_items=[i for i in self.items if (i["id"] in saved if self.section=="saved" else i["section"]==self.section)]
        if self.section=="writings" and self.book: self.section_items=[i for i in self.section_items if book_of(i)==self.book]
        while child:=self.toc.get_first_child(): self.toc.remove(child)
        self.branches={}; self.branch_rows=[]; self.passage_buttons=[]; self.groups={}
        if self.section=="home" or self.library_showing():
            # Home and the library are pages of their own; there is no contents list to show.
            self.section_items=[]; self.visible=[]; self.query=None; self.count.set_text(""); self.secondscroll.set_visible(False); return
        if self.section=="today":
            self.build_calendar()
            self.no_match=Gtk.Label(wrap=True,xalign=0,visible=False); self.no_match.add_css_class("dim-label"); self.toc.append(self.no_match)
            self.query=None; self.filter(); self.secondscroll.set_visible(False); return
        groups={}
        for item in self.section_items:
            for tag in item["tags"] or ["Uncategorized"]: groups.setdefault(tag,[]).append(item)
        if self.section=="obligatory":
            # Prayers first, then the guidance, in reading order rather than alphabetically.
            groups=obligatory(self.items); self.section_items=[i for g in groups.values() for i in g]
        if self.section=="saved":
            # A personal prayerbook: collections in their own order, then whatever is not filed yet.
            groups=self.filed(); self.section_items=[i for g in groups.values() for i in g]
        if self.section=="prayers" and self.adwaita:
            # In the libadwaita window the obligatory prayers are the first group of Prayers.
            row=self.row_button(lambda *_:self.navigate("obligatory")); row.add_css_class("toc-passage"); row.set_tooltip_text("The three obligatory prayers, their guidance, and the Alláh-u-Abhá counter")
            line=Gtk.Box(spacing=8); line.append(Gtk.Label(label="Obligatory prayers",xalign=0,hexpand=True)); line.append(Gtk.Image(icon_name="go-next-symbolic")); row.set_child(line)
            self.name_widget(row,"Obligatory prayers")
            self.toc.append(row); self.obligatory_row=row
        if self.section=="obligatory":
            row=self.button("Alláh-u-Abhá counter",self.show_counter); row.add_css_class("toc-passage"); row.get_child().set_xalign(0); self.toc.append(row); self.counter_row=row
        ordered=list(groups.items()) if self.section in ("obligatory","saved") else sorted(groups.items())
        if self.section=="writings" and self.prefs.get("writings_by")=="author":
            # Author, then book, then the book's own parts.
            authors={}
            for tag,items in ordered: authors.setdefault(items[0].get("author") or "Other",[]).append((tag,items))
            rank=lambda a:AUTHOR_ORDER.index(a) if a in AUTHOR_ORDER else len(AUTHOR_ORDER)
            for author in sorted(authors,key=lambda a:(rank(a),a)):
                path=f"writings/by-author/{author}"
                container=self.branch(self.toc,author,path,[i for _,items in authors[author] for i in items])
                for tag,items in authors[author]: self.add_entries(self.branch(container,tag,f"{path}/{tag}",items),f"{path}/{tag}",items)
        elif self.section=="writings" and self.book:
            # One book: its own parts and passages are the contents.
            path=f"writings/{self.book}"; self.add_entries(self.toc,path,self.section_items)
        else:
            for tag,items in ordered:
                path=f"{self.section}/{tag}"
                self.add_entries(self.branch(self.toc,tag,path,items),path,items)
        self.no_match=Gtk.Label(wrap=True,xalign=0,visible=False); self.no_match.add_css_class("dim-label"); self.toc.append(self.no_match)
        if self.section=="saved": self.add_marks_row()
        self.query=None; self.filter(); self.show_second()

    def add_entries(self,container,path,items):
        """A group's passages, under their subgroups (parts, chapters, decades) where they have them."""
        # Named subgroups gather their passages; passages outside any (a foreword, a closing chapter) stay where they come.
        subgroups={}; loose=0
        for item in items:
            name=item["subgroup"] if self.section!="saved" else None
            if not name and (not subgroups or list(subgroups)[-1]!=(None,loose)): loose+=1
            subgroups.setdefault(name or (None,loose),[]).append(item)
        for key,entries in subgroups.items():
            subgroup=key if isinstance(key,str) else None
            parent=self.branch(container,subgroup,path+"/"+subgroup,entries) if subgroup else container
            for item in entries:
                self.groups.setdefault(item["id"],entries)
                button=self.row_button(lambda _,i=item,g=entries:self.open_from_list(i,g))
                label=Gtk.Label(label=list_title(item),xalign=0,ellipsize=Pango.EllipsizeMode.END,max_width_chars=29)
                content=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
                content.append(label)
                if item["section"]=="prayers":
                    count_label=Gtk.Label(label=word_label(item), xalign=0)
                    count_label.add_css_class("dim-label"); content.append(count_label)
                button.set_child(content)
                # The whole title, which the row may cut off.
                button.set_tooltip_text(item["title"]+(" — "+word_label(item) if item["section"]=="prayers" else ""))
                button.add_css_class("toc-passage")
                # GTK names a button from a plain label, not from a box of labels; a screen reader needs it said.
                self.name_widget(button,list_title(item)+(", "+word_label(item) if item["section"]=="prayers" else ""))
                parent.append(button); button.container=parent; self.passage_buttons.append((item,button))

    def change_grouping(self,choice):
        value=choice.get_active_id()
        if value and value!=self.prefs.get("writings_by","book"):
            self.prefs["writings_by"]=value; self.save()
            if self.section=="writings": self.rebuild()

    def filter(self,*_):
        if not hasattr(self,"section_items"): return
        query=fold(self.search.get_text().strip())
        if query==self.query: return
        self.query=query
        if query:
            for item in self.section_items:
                if "search" not in item: item["search"]=fold(item["title"]+" "+item["text"]+" "+" ".join(item["tags"]))
        matches={i["id"] for i in self.section_items if query in i["search"]} if query else {i["id"] for i in self.section_items}
        self.visible=[i for i in self.section_items if i["id"] in matches]
        for item,button in self.passage_buttons: button.set_visible(item["id"] in matches)
        self.restoring=True
        for expander,total,path,items in self.branch_rows:
            count=sum(1 for i in items if i["id"] in matches)
            expander.set_visible(count>0); total.set_text(self.unit_label(count))
            expander.set_expanded(bool(query) or self.prefs.get("expanded",{}).get(path,self.section in ("obligatory","today")))
        self.restoring=False
        unit="date" if self.section=="today" else "passage"
        self.count.set_text(f"{len(self.visible)} {unit}{'s' if len(self.visible)!=1 else ''}")
        self.no_match.set_text(f"No {unit}s match “{self.search.get_text().strip()}”." if query else "")
        self.no_match.set_visible(bool(query) and not self.visible)
        if self.section=="today": return  # Today's contents are dates; choosing one opens its readings.
        # Searching never moves the reading position; it only narrows the list.
        current=next((i for i in self.section_items if self.current and i["id"]==self.current["id"]),None)
        if current is not None:
            if current is not self.current: self.show_passage(current,self.groups[current["id"]])
            else: self.highlight()
        elif self.section_items:
            item=next((i for i in self.section_items if i["id"]==self.prefs.get("last")),self.section_items[0])
            self.show_passage(item,self.groups[item["id"]])
        else:
            self.position.set_text(""); self.related.set_visible(False); self.current=None; self.active_group=[]; self.reader.get_buffer().set_text(""); self.star.set_sensitive(False); self.copy.set_sensitive(False); self.filing.set_visible(False)
            if self.section=="saved":
                self.heading.set_text("No saved passages yet"); self.subtitle.set_text("Press Ctrl+D or ☆ Save to keep one here.")
            else:
                self.heading.set_text("No passages found")
                self.subtitle.set_text("This language’s library does not mark the obligatory prayers." if self.section=="obligatory" else "Check this language’s available books in Languages & offline libraries.")

    def unit_label(self,count):
        unit="prayer" if self.section=="prayers" else "date" if self.section=="today" else "passage"
        return f"{count} {unit}{'s' if count != 1 else ''}"

    def branch(self,parent,title,path,items):
        expander=Gtk.Expander(hexpand=True, vexpand=False)
        expander.add_css_class("toc-branch")
        # The name takes whatever width there is; when it is still cut off, its tooltip has it whole.
        heading=Gtk.Box(spacing=8, hexpand=True, margin_end=12)
        label=Gtk.Label(label=title, xalign=0, hexpand=True,
                        ellipsize=Pango.EllipsizeMode.END, tooltip_text=title)
        heading.append(label)
        total=Gtk.Label(label=self.unit_label(len(items))); total.add_css_class("dim-label"); total.add_css_class("count")
        heading.append(total)
        expander.set_label_widget(heading)
        expander.set_tooltip_text(title); self.name_widget(expander,f"{title}, {self.unit_label(len(items))}")
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=3,margin_start=14,margin_top=6,margin_bottom=6)
        box.expander=expander; expander.container=parent
        expander.set_child(box); parent.append(expander); self.branches[path]=expander; self.branch_rows.append((expander,total,path,items))
        def toggled(widget,_):
            if not self.restoring and not self.query:
                self.prefs.setdefault("expanded",{})[path]=widget.get_expanded(); self.save()
        expander.connect("notify::expanded",toggled)
        return box

    def build_calendar(self):
        """Upcoming Holy Days and Feasts, then this Badí‘ year, as contents rows that search can narrow."""
        day=badi.observed_date(self.now(),self.place()); today=badi.from_gregorian(day)
        if not today:
            self.section_items=[]; note=Gtk.Label(label=badi.UNPUBLISHED,wrap=True,xalign=0); note.add_css_class("dim-label"); self.toc.append(note); return
        rows=[]
        def row(group,name,detail,opens=None):
            rows.append(dict(id=f"{group}:{len(rows)}",group=group,title=name,detail=detail,opens=opens,search=fold(f"{name} {detail}")))
        for event in badi.upcoming(day):
            detail=f"{badi.gregorian_text(event.date)}. {badi.event_summary(event,day)}"
            if event.work_suspended: detail+=" Work is suspended."
            name=f"{event.name} ({event.meaning})" if event.meaning else event.name
            row("Upcoming",name,detail,self.event_opener(event))
        this_year=f"This year, {today.year} B.E."
        for period in badi.year_months(today.year):
            name=f"{period.name} ({period.meaning})" if period.meaning else period.name
            detail=f"{badi.gregorian_text(period.first)} to {badi.gregorian_text(period.last)}"
            prayers=AYYAM_PRAYERS if period.badi.month==badi.INTERCALARY else FAST_PRAYERS if period.badi.month==badi.FAST_MONTH else None
            row(this_year,name,detail,self.prayer_opener(prayers,f"Prayers for {period.name}") if prayers else None)
        self.section_items=rows
        for group in ("Upcoming",this_year):
            entries=[r for r in rows if r["group"]==group]
            if not entries: continue
            parent=self.branch(self.toc,group,f"today/{group.split(',')[0]}",entries)
            for entry in entries:
                content=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=3)
                content.append(Gtk.Label(label=entry["title"],xalign=0,wrap=True,max_width_chars=30))
                detail=Gtk.Label(label=entry["detail"],xalign=0,wrap=True,max_width_chars=30); detail.add_css_class("dim-label"); content.append(detail)
                if entry["opens"]:
                    # Only a date with readings or prayers is a button; the rest are plain text, not stops for the keyboard.
                    widget=Gtk.Button(child=content); widget.connect("clicked",lambda _,o=entry["opens"]:o()); widget.add_css_class("toc-passage")
                    self.name_widget(widget,f"{entry['title']}. {entry['detail']}")
                else:
                    widget=content; widget.add_css_class("toc-date")
                widget.set_tooltip_text(entry["title"]); parent.append(widget); self.passage_buttons.append((entry,widget))

    def prayer_group(self,category):
        return [i for i in self.items if i["section"]=="prayers" and category in i["tags"]]

    def readings_group(self,tag):
        """The Days of Remembrance readings for a HolyDay tag, in this language's library."""
        return [i for i in self.items if badi_days_tag(i)==tag]

    def prayer_opener(self,category,label):
        """A callback opening the first prayer of a category, or None if this library has none."""
        if not category or not self.prayer_group(category): return None
        def go():
            group=self.prayer_group(category)
            self.open_in_section(group[0],group,label)
        return go

    def event_opener(self,event):
        """What choosing a date opens: its readings in Days of Remembrance, else its prayers, else nothing."""
        if event.readings and self.readings_group(event.readings):
            def go():
                group=self.readings_group(event.readings)
                self.open_in_section(group[0],group,f"Readings for {event.name}")
            return go
        return self.prayer_opener(event.prayers,f"Prayers for {event.name}")

    def open_in_section(self,item,group,label):
        if self.section!=item["section"] or (self.adwaita and item["section"]=="writings" and self.book!=book_of(item)): self.navigate(item["section"],book=book_of(item))
        elif self.search.get_text(): self.search.set_text(""); self.filter()
        self.show_passage(item,group); self.show_content()
        self.subtitle.set_text(label+" · "+self.subtitle.get_text())

    def highlight(self):
        for item,button in self.passage_buttons:
            if self.current and item["id"]==self.current["id"]:
                button.add_css_class("current-passage")
                if self.adwaita and not self.query:
                    # Open the parts that hold it, so the contents show where the reader is (without remembering that as a choice).
                    # (A collapsed GtkExpander unparents its child, so the way up is recorded when the contents are built.)
                    self.restoring=True; box=getattr(button,"container",None)
                    while getattr(box,"expander",None):
                        box.expander.set_expanded(True); box=box.expander.container
                    self.restoring=False
            else: button.remove_css_class("current-passage")
