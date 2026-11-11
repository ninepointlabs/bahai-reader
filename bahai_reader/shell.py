"""The libadwaita window (libadwaita 1.4 or newer): a split view with Home, Prayers, Writings and Saved in the sidebar and the
reader beside it. It builds the same widgets the classic window has (the contents list, the reading view, Today, the counter),
so the views work unchanged in either; only the frame around them differs. Debian 12 (libadwaita 1.2) keeps the classic window."""
import os
import shutil
import sys
import time
import gi
from gi.repository import Gtk, Gdk, Gio, GLib, Pango

from .config import APP_NAME
from .labels import heading
from .library import HIDDEN_WORDS, book_of, book_progress, book_summary, books
from .settings import AUTHOR_ORDER
from .ui import NARROW_WIDTH, SHORTCUT_GROUPS

ADWAITA_MINIMUM=(1,4)  # AdwNavigationSplitView, AdwToolbarView and AdwBreakpoint
# The sidebar: key, label, symbolic icon.
NAV_ROWS=(("home","Home","go-home-symbolic"),("prayers","Prayers","emoji-nature-symbolic"),
          ("writings","Writings","accessories-dictionary-symbolic"),("saved","Saved","starred-symbolic"))
# The sidebar row each section belongs to: Today is part of Home, Obligatory prayers of Prayers, the Hidden Words a book in Writings.
NAV_OF={"home":"home","today":"home","prayers":"prayers","obligatory":"prayers","hidden":"writings","writings":"writings","saved":"saved"}
# Sections shown as one book in the sidebar, with a back button to where they belong.
BOOK_SECTIONS={"obligatory":"prayers","hidden":"writings"}
CONTINUE_CARDS=3

def adwaita():
    """libadwaita, when the libadwaita window can be used: installed, 1.4 or newer, and not turned off with
    BAHAI_READER_SHELL=classic. None means the classic window."""
    wanted=os.environ.get("BAHAI_READER_SHELL","auto")
    if wanted=="classic": return None
    try:
        gi.require_version("Adw","1")
        from gi.repository import Adw
    except (ValueError,ImportError): Adw=None
    if Adw and (Adw.get_major_version(),Adw.get_minor_version())>=ADWAITA_MINIMUM: return Adw
    if wanted=="adwaita": print("bahai-reader: libadwaita 1.4 or newer is needed for that window; using the classic one.",file=sys.stderr)
    return None

OPENING=0.45  # seconds an AdwDialog takes to animate open

def present_dialog(Adw,dialog,parent):
    dialog.shown_at=time.monotonic(); Adw.Dialog.present(dialog,parent)

def close_dialog(Adw,dialog):
    """Closes an AdwDialog. libadwaita 1.5 (Ubuntu 24.04) leaves a dialog on screen for good if it is closed while still
    animating open, so there a close that comes too early waits until the dialog is fully open; and one that is somehow
    still attached afterwards is closed without its animation."""
    if (Adw.get_major_version(),Adw.get_minor_version())>=(1,6): return Adw.Dialog.close(dialog)
    def rescue():
        if dialog.get_parent() is not None and dialog.get_can_close(): dialog.force_close()
        return False
    def close():
        Adw.Dialog.close(dialog); GLib.timeout_add(600,rescue); return False
    early=OPENING-(time.monotonic()-getattr(dialog,"shown_at",0))
    if early>0: GLib.timeout_add(int(early*1000)+50,close)
    else: close()
    return True

def author_rank(author):
    return (AUTHOR_ORDER.index(author) if author in AUTHOR_ORDER else len(AUTHOR_ORDER),author or "")

class ShellMixin:
    """Reader methods for the libadwaita window."""
    def build_adwaita(self,Adw):
        Adw.init(); self.Adw=Adw; self.adwaita=True
        self.css_variables=Gtk.get_minor_version()>=16  # libadwaita 1.6+ reads CSS variables, which need GTK 4.16
        omarchy=bool(shutil.which("omarchy"))
        self.window=Adw.ApplicationWindow(application=self,title=APP_NAME,default_width=1160,default_height=790)
        self.window.set_size_request(320,360)
        self.window.connect("close-request",self.window_closing)
        if omarchy: self.window.set_decorated(False)  # Hyprland draws the border; no window buttons
        self.narrow=False; self.sidebar_wanted=True; self.focus_mode=False; self.notice_log=[]; self.book=None
        self.home_buttons={}; self.library_cards={}; self.continue_cards=[]
        self.toasts=Adw.ToastOverlay(); self.window.set_content(self.toasts)
        self.splitview=Adw.NavigationSplitView(min_sidebar_width=240,max_sidebar_width=340,sidebar_width_fraction=0.26)
        self.toasts.set_child(self.splitview)
        # The sidebar page.
        side=Adw.ToolbarView(); bar=Adw.HeaderBar()
        if omarchy: bar.set_show_start_title_buttons(False); bar.set_show_end_title_buttons(False)
        self.book_back=Gtk.Button(icon_name="go-previous-symbolic",visible=False,tooltip_text="Back"); self.book_back.connect("clicked",lambda *_:self.leave_book())
        bar.pack_start(self.book_back)
        self.side_title=Adw.WindowTitle(title=APP_NAME); bar.set_title_widget(self.side_title)
        find=Gtk.Button(icon_name="system-search-symbolic",tooltip_text="Search the texts (Ctrl+K)"); find.connect("clicked",self.open_finder); self.name_widget(find,"Search the texts"); bar.pack_end(find); self.find_button=find
        side.add_top_bar(bar)
        self.sidebar=Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.switcher=Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE); self.switcher.add_css_class("navigation-sidebar"); self.switcher_rows={}; self.nav_counts={}
        self.name_widget(self.switcher,"Sections")
        for key,title,icon in NAV_ROWS:
            row=Gtk.ListBoxRow(); row.section=key; line=Gtk.Box(spacing=12)
            line.append(Gtk.Image(gicon=Gio.ThemedIcon.new_from_names([icon,"text-x-generic-symbolic"]),accessible_role=Gtk.AccessibleRole.PRESENTATION))
            line.append(Gtk.Label(label=title,xalign=0,hexpand=True,ellipsize=Pango.EllipsizeMode.END))
            count=Gtk.Label(); count.add_css_class("dim-label"); count.add_css_class("count"); line.append(count); self.nav_counts[key]=count
            row.set_child(line); row.set_tooltip_text(title); self.switcher.append(row); self.switcher_rows[key]=row
        self.switcher_syncing=False
        self.switcher.connect("row-selected",lambda _box,row: row and not self.switcher_syncing and self.nav_key()!=row.section and self.navigate(row.section))
        self.sidebar.append(self.switcher)
        self.contents_box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=10,vexpand=True,margin_top=6,margin_bottom=10,margin_start=12,margin_end=12)
        self.make_contents(self.contents_box); self.sidebar.append(self.contents_box)
        side.set_content(self.sidebar)
        self.sidebar_page=Adw.NavigationPage(title=APP_NAME,child=side,tag="sidebar")
        self.splitview.set_sidebar(self.sidebar_page)
        # The content page.
        content=Adw.ToolbarView(); self.content_bar=Adw.HeaderBar()
        if omarchy: self.content_bar.set_show_start_title_buttons(False); self.content_bar.set_show_end_title_buttons(False)
        self.content_title=Adw.WindowTitle(title=APP_NAME); self.content_bar.set_title_widget(self.content_title)
        panel=Gtk.Button(icon_name="sidebar-show-symbolic",tooltip_text="Show or hide the sidebar"); panel.connect("clicked",self.toggle_sidebar); self.name_widget(panel,"Sidebar")
        self.panel_button=panel; self.content_bar.pack_start(panel)
        more=Gtk.MenuButton(icon_name="view-more-symbolic",tooltip_text="Menu"); self.name_widget(more,"Menu"); self.app_menu=more; self.content_bar.pack_end(more)
        self.make_menu(more)
        actions=self.make_actions()
        # Save and Copy as icon buttons, made without a label so the name given to screen readers is the one they hear.
        self.star=Gtk.Button(icon_name="non-starred-symbolic",tooltip_text=self.star.get_tooltip_text()); self.star.connect("clicked",self.bookmark)
        self.copy=Gtk.Button(icon_name="edit-copy-symbolic",tooltip_text=self.copy.get_tooltip_text()); self.copy.connect("clicked",self.copy_passage)
        self.name_widget(self.star,"Save"); self.name_widget(self.copy,"Copy with citation"); self.wide_header=(self.copy,)
        for widget in (self.star,self.copy,actions[2]): self.content_bar.pack_end(widget)
        search=Gtk.Button(icon_name="system-search-symbolic",tooltip_text="Search the texts (Ctrl+K)"); search.connect("clicked",self.open_finder); self.name_widget(search,"Search the texts")
        self.content_bar.pack_end(search); self.content_search=search
        self.text_menu.set_tooltip_text("Text and appearance"); self.name_widget(self.text_menu,"Text and appearance")
        content.add_top_bar(self.content_bar)
        self.make_views(); self.build_home(); self.build_library_view(); self.build_reader_place()
        content.set_content(self.views)
        self.content_page=Adw.NavigationPage(title=APP_NAME,child=content,tag="content")
        self.splitview.set_content(self.content_page)
        # Narrow windows: the split view collapses and the two pages take turns.
        point=Adw.Breakpoint.new(Adw.BreakpointCondition.parse(f"max-width: {NARROW_WIDTH-1}px"))
        point.add_setter(self.splitview,"collapsed",True)
        point.connect("apply",lambda *_:self.set_narrow(True)); point.connect("unapply",lambda *_:self.set_narrow(False))
        self.window.add_breakpoint(point)
        self.notice_box=None
        for text in self.notices: self.notice(text)
        self.notices=[]
        self.install_keys()
        self.views.add_tick_callback(self.follow_width); self.views_width=0
        self.finish_build()

    # ----- layout -----
    def set_narrow(self,narrow):
        self.narrow=narrow
        stacked=Gtk.Orientation.VERTICAL if narrow else Gtk.Orientation.HORIZONTAL
        self.pages.set_orientation(stacked); self.filing.set_orientation(stacked); self.counter_controls.set_orientation(stacked)
        self.previous.set_label("←" if narrow else "← Previous"); self.next.set_label("→" if narrow else "Next →")
        for entry in self.narrow_entries: entry.set_visible(narrow)
        self.copy.set_visible(not narrow)
        # A narrow window has Back to the sidebar; the toggle would only crowd the header.
        self.panel_button.set_visible(not narrow)
        orientation=Gtk.Orientation.VERTICAL if narrow else Gtk.Orientation.HORIZONTAL
        self.home_today.set_orientation(orientation); self.home_continue.set_orientation(orientation)
        self.fit_margins()
    def follow_width(self,widget,clock):
        width=widget.get_width()
        if width!=self.views_width: self.views_width=width; self.fit_margins()
        return True
    def shell_fit_margins(self):
        width=self.views.get_width() or self.window.get_width()
        if self.secondscroll.get_visible() and not self.narrow: width//=2
        margin=min(int(self.prefs.get("margin",80)),max(12,(width-360)//2))
        for view in (self.reader,self.second): view.set_left_margin(margin); view.set_right_margin(margin)
    def shell_toggle_sidebar(self):
        split=self.splitview
        if self.narrow: split.set_show_content(not split.get_show_content())
        else:
            # A wide window hides the sidebar by collapsing the split view onto the reader.
            split.set_collapsed(not split.get_collapsed()); split.set_show_content(True)
    def shell_show_list(self,visible):
        split=self.splitview
        if visible and self.focus_mode: self.set_focus_mode(False)
        if split.get_collapsed(): split.set_show_content(not visible)
        if visible: (self.search if self.search.get_visible() else self.switcher).grab_focus()
        else: self.focus_view()
    def find_in_contents(self):
        self.show_list(True)
        if self.search.get_visible(): self.search.grab_focus()
    def set_focus_mode(self,on):
        """Focus mode: only the text. The sidebar and the header hide; Esc or F11 brings them back."""
        self.focus_mode=on
        if on:
            self.focus_saved=self.splitview.get_collapsed()
            self.splitview.set_collapsed(True); self.splitview.set_show_content(True)
        else: self.splitview.set_collapsed(getattr(self,"focus_saved",False) or self.narrow)
        self.splitview.get_content().get_child().set_reveal_top_bars(not on)

    # ----- where we are -----
    def nav_key(self):
        return NAV_OF.get(self.section,self.section) if getattr(self,"adwaita",False) else self.section
    def in_book(self):
        return self.section in BOOK_SECTIONS or (self.section=="writings" and bool(self.book))
    def shell_navigated(self):
        """After navigate(): the sidebar row, whether the sidebar shows a book, and the titles."""
        book=self.in_book()
        self.switcher.set_visible(not book); self.book_back.set_visible(book)
        self.contents_box.set_visible(self.section not in ("home",) and not (self.section=="writings" and not self.book))
        if book:
            name={"obligatory":"Obligatory prayers","hidden":HIDDEN_WORDS}.get(self.section,self.book)
            passages=self.section_items
            author=next((i.get("author") for i in passages if i.get("author")),None) if self.section!="obligatory" else None
            self.side_title.set_title(name); self.side_title.set_subtitle(" · ".join(filter(None,(author,book_summary(passages) if passages else None))))
            self.sidebar_page.set_title(name)
        else:
            self.side_title.set_title(APP_NAME); self.side_title.set_subtitle(""); self.sidebar_page.set_title(APP_NAME)
        self.update_counts(); self.shell_titles()
    def leave_book(self):
        self.navigate(BOOK_SECTIONS.get(self.section,"writings"))
        self.show_list(True)
    def shell_titles(self):
        view=self.views.get_visible_child_name()
        titles={"home":("Home",""),"library":("Library","18 books" if not self.items else f"{len(books(self.items))} books"),
                "today":("Today",(self.place() or {}).get("label","")),"counter":("Alláh-u-Abhá","Kitáb-i-Aqdas ¶18")}
        if view in titles: title,sub=titles[view]
        elif self.current:
            book=book_of(self.current)
            title=book or {"prayers":"Prayers","obligatory":"Obligatory prayers","saved":"Saved"}.get(self.section,APP_NAME)
            sub=self.heading.get_text()
        else: title,sub={"saved":("Saved",""),"prayers":("Prayers","")}.get(self.section,(APP_NAME,""))
        self.content_title.set_title(title); self.content_title.set_subtitle(sub or "")
        if view=="reading": self.shell_progress()
        self.content_page.set_title(title)
    def update_counts(self):
        saved=len(self.prefs.get("saved",[]))
        counts={"prayers":str(sum(1 for i in self.items if i["section"]=="prayers")),"writings":f"{len(books(self.items))} books","saved":str(saved) if saved else ""}
        for key,label in self.nav_counts.items(): label.set_text(counts.get(key,""))
    def open_book(self,book):
        """A book from the library: its contents in the sidebar, at the passage last read in it, else its first."""
        position=self.prefs.get("positions",{}).get(book)
        if position: self.prefs["last"]=position
        if book==HIDDEN_WORDS: self.navigate("hidden")
        else: self.navigate("writings",book=book)
        self.show_content()

    # ----- the reader: where the passage is, and how far through the book -----
    def build_reader_place(self):
        """Above the text, the book and part as a small line, then the heading, then the passage's place and reading time.
        In the footer, progress through the whole book in place of “1 of 71”."""
        right=self.heading.get_parent()
        right.reorder_child_after(self.subtitle,None); self.subtitle.add_css_class("eyebrow"); self.subtitle.remove_css_class("dim-label")
        self.reading_meta=Gtk.Label(wrap=True,justify=Gtk.Justification.CENTER); self.reading_meta.add_css_class("dim-label"); self.reading_meta.add_css_class("count")
        right.insert_child_after(self.reading_meta,self.heading)
        nav=self.position.get_parent(); nav.set_halign(Gtk.Align.FILL); nav.set_margin_start(18); nav.set_margin_end(18)
        progress=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=6,hexpand=True,valign=Gtk.Align.CENTER)
        labels=Gtk.Box(spacing=12); self.progress_where=Gtk.Label(xalign=0,hexpand=True,ellipsize=Pango.EllipsizeMode.END); self.progress_percent=Gtk.Label(xalign=1)
        for label in (self.progress_where,self.progress_percent): label.add_css_class("dim-label"); label.add_css_class("count"); labels.append(label)
        progress.append(labels); self.book_bar=Gtk.ProgressBar(); progress.append(self.book_bar); self.progress_box=progress
        nav.insert_child_after(progress,self.previous); self.position.set_visible(False)
        self.next.remove_css_class("primary"); self.next.add_css_class("suggested-action"); self.next.add_css_class("pill")
        self.shelf_cache=(None,{})
    def shelf(self):
        if self.shelf_cache[0] is not self.items: self.shelf_cache=(self.items,books(self.items))
        return self.shelf_cache[1]
    def shell_progress(self):
        item=self.current
        if not item:
            self.reading_meta.set_text(""); self.progress_box.set_visible(False); return
        book=book_of(item); passages=self.shelf().get(book) if book else None
        if passages:
            index=next((n for n,i in enumerate(passages) if i is item or i["id"]==item["id"]),0)
            before,total=book_progress(passages,item); minutes=max(1,round(item["word_count"]/230))
            self.reading_meta.set_text(f"Passage {index+1} of {len(passages)} · about {minutes} minute{'s' if minutes!=1 else ''}")
            fraction=before/total if total else 0
            self.progress_where.set_text(f"{book} · {index+1} of {len(passages)}"); self.progress_percent.set_text(f"{round(100*fraction)}% of the book")
            self.book_bar.set_fraction(fraction); self.book_bar.set_visible(True); self.progress_box.set_visible(True)
            self.name_widget(self.book_bar,f"{round(100*fraction)}% through {book}")
        else:
            group=self.active_group if item in self.active_group else [item]; index=group.index(item)
            self.reading_meta.set_text("")
            self.progress_where.set_text(f"{index+1} of {len(group)}" if len(group)>1 else ""); self.progress_percent.set_text("")
            self.book_bar.set_fraction(index/(len(group)-1) if len(group)>1 else 0); self.book_bar.set_visible(len(group)>1)
            self.progress_box.set_visible(len(group)>1)

    # ----- Home and the library -----
    def build_home(self):
        scroll=Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER,vexpand=True); self.views.add_named(scroll,"home")
        clamp=self.Adw.Clamp(maximum_size=920,tightening_threshold=600); scroll.set_child(clamp)
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=12,margin_top=20,margin_bottom=28,margin_start=16,margin_end=16); clamp.set_child(box)
        self.home_today=Gtk.Box(spacing=12,homogeneous=True)
        box.append(self.home_today)
        self.continue_title=Gtk.Label(label="Continue reading",xalign=0,margin_top=12); self.continue_title.add_css_class("section-title"); box.append(self.continue_title)
        self.home_continue=Gtk.Box(spacing=12,homogeneous=True)
        box.append(self.home_continue)
        title=Gtk.Label(label="Library",xalign=0,margin_top=16); title.add_css_class("library-title"); box.append(title)
        self.home_library=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=10); box.append(self.home_library)
        self.home_items=None
    def build_library_view(self):
        scroll=Gtk.ScrolledWindow(hscrollbar_policy=Gtk.PolicyType.NEVER,vexpand=True); self.views.add_named(scroll,"library")
        clamp=self.Adw.Clamp(maximum_size=920,tightening_threshold=600); scroll.set_child(clamp)
        self.library_page=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=10,margin_top=16,margin_bottom=28,margin_start=16,margin_end=16); clamp.set_child(self.library_page)
        self.library_items=None
    def fill_library(self,box,cards):
        """The books as cards, grouped by author in the order of the Central Figures and the institutions."""
        while child:=box.get_first_child(): box.remove(child)
        shelf=books(self.items); authors={}
        for book,passages in shelf.items(): authors.setdefault(next((i.get("author") for i in passages if i.get("author")),"Other"),[]).append(book)
        for author in sorted(authors,key=author_rank):
            title=Gtk.Label(label=f"{author}",xalign=0,margin_top=10); title.add_css_class("section-title"); box.append(title)
            grid=Gtk.FlowBox(selection_mode=Gtk.SelectionMode.NONE,homogeneous=True,max_children_per_line=4,min_children_per_line=1,column_spacing=12,row_spacing=12)
            self.name_widget(grid,f"Books by {author}")
            for book in authors[author]:
                card=Gtk.Button(); card.add_css_class("card"); card.add_css_class("book-card"); card.connect("clicked",lambda _,b=book:self.open_book(b))
                inner=Gtk.Box(spacing=12); spine=Gtk.Box(); spine.add_css_class("spine"); inner.append(spine)
                text=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=6,hexpand=True)
                name=Gtk.Label(label=book,xalign=0,wrap=True,yalign=0,vexpand=True,lines=3,ellipsize=Pango.EllipsizeMode.END,width_chars=14,max_width_chars=16); name.add_css_class("book-title"); text.append(name)
                meta=Gtk.Label(label=book_summary(shelf[book]),xalign=0); meta.add_css_class("dim-label"); text.append(meta)
                inner.append(text); card.set_child(inner); card.set_tooltip_text(f"{book}, {author}")
                self.name_widget(card,f"{book}, {author}. {book_summary(shelf[book])}")
                grid.append(card); cards[book]=card
            box.append(grid)
    def refresh_library(self):
        if self.library_items is not self.items:
            self.library_items=self.items; self.library_cards={}; self.fill_library(self.library_page,self.library_cards)
    def refresh_home(self):
        if not getattr(self,"home_today",None): return
        if self.home_items is not self.items:
            self.home_items=self.items; self.home_cards={}; self.fill_library(self.home_library,self.home_cards)
        # The day at a glance: the date, the obligatory prayer, the passage of the day. Rebuilt only when it changes.
        cards=self.today_content()
        date=[r for r in cards.get("date",[]) if r[0]!="dim"][:3]+[("button","Open Today",lambda *_:(self.navigate("today"),self.focus_view()))]
        # Home keeps each card short: the prayer's state with Said and Open; the rest is on the Today page.
        prayer=[r for r in cards.get("prayer",[]) if r[0]!="button" or r[1].startswith("Open the ")]
        strip=[("date","Today",date)]+([("prayer",None,prayer)] if prayer else [])+([("passage",None,cards["passage"])] if cards.get("passage") else [])
        signature=[(k,[(r[0],r[1],r[2]) if r[0]=="toggle" else r[:2] for r in rows]) for k,_,rows in strip]
        if signature!=getattr(self,"home_signature",None):
            self.home_signature=signature
            while child:=self.home_today.get_first_child(): self.home_today.remove(child)
            self.home_buttons={}
            for key,tag,rows in strip: self.home_today.append(self.home_card(key,tag,rows))
        # Continue reading: the books read most recently, at the passage last open in each.
        signature=(self.prefs.get("recent",[])[:],dict(self.prefs.get("positions",{})),id(self.items))
        if signature==getattr(self,"continue_signature",None): return
        self.continue_signature=signature
        while child:=self.home_continue.get_first_child(): self.home_continue.remove(child)
        self.continue_cards=[]; shelf=books(self.items); by_id={i["id"]:i for i in self.items}
        for book in self.prefs.get("recent",[]):
            item=by_id.get(self.prefs.get("positions",{}).get(book))
            if not item or book not in shelf: continue
            before,total=book_progress(shelf[book],item); percent=round(100*before/total) if total else 0
            card=Gtk.Button(); card.add_css_class("card"); card.connect("clicked",lambda _,b=book:self.open_book(b))
            inner=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=6,margin_top=4,margin_bottom=4,margin_start=4,margin_end=4)
            name=Gtk.Label(label=book,xalign=0,ellipsize=Pango.EllipsizeMode.END); name.add_css_class("dim-label"); inner.append(name)
            where=Gtk.Label(label=heading(item),xalign=0,ellipsize=Pango.EllipsizeMode.END); where.add_css_class("heading-small"); where.set_markup(f"<b>{GLib.markup_escape_text(heading(item))}</b>"); inner.append(where)
            bar=Gtk.ProgressBar(fraction=before/total if total else 0); inner.append(bar)
            done=Gtk.Label(label=f"{percent}% of the book",xalign=0); done.add_css_class("dim-label"); done.add_css_class("count"); inner.append(done)
            card.set_child(inner); self.name_widget(card,f"Continue {book}: {heading(item)}, {percent}% of the book")
            self.home_continue.append(card); self.continue_cards.append((book,card))
            if len(self.continue_cards)>=CONTINUE_CARDS: break
        self.continue_title.set_visible(bool(self.continue_cards)); self.home_continue.set_visible(bool(self.continue_cards))
    def home_card(self,key,tag,rows):
        card=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=6,valign=Gtk.Align.START); card.add_css_class("today-card")
        if tag:
            label=Gtk.Label(label=tag.upper(),xalign=0); label.add_css_class("tag"); card.append(label)
        actions=None
        for row in rows:
            kind,text=row[:2]
            if kind in ("button","toggle"):
                if actions is None:
                    actions=Gtk.Box(spacing=8,margin_top=6); card.append(actions)
                if kind=="button":
                    widget=self.button(text,lambda _,a=row[2]:a())
                else:
                    widget=Gtk.ToggleButton(label=("✓ " if row[2] else "")+text,active=row[2])
                    widget.connect("toggled",lambda t,a=row[3]:a(t.get_active()))
                if isinstance(widget.get_child(),Gtk.Label): widget.get_child().set_wrap(True)
                actions.append(widget); self.home_buttons[key,text]=widget
                # Two actions, or a long one, stack rather than squeeze a third of the width.
                if actions.get_first_child() is not widget or len(text)>18: actions.set_orientation(Gtk.Orientation.VERTICAL); actions.set_halign(Gtk.Align.START)
                continue
            if kind=="title":
                label=Gtk.Label(label=text.upper(),xalign=0); label.add_css_class("tag")
            else:
                label=Gtk.Label(label=text,xalign=0,wrap=True,max_width_chars=24,natural_wrap_mode=Gtk.NaturalWrapMode.WORD) if hasattr(Gtk,"NaturalWrapMode") else Gtk.Label(label=text,xalign=0,wrap=True,max_width_chars=24)
                label.add_css_class({"large":"today-large","reading":"today-reading","dim":"dim-label"}.get(kind,"today-text"))
                if kind=="reading": label.set_lines(4); label.set_ellipsize(Pango.EllipsizeMode.END)
            card.append(label)
        return card

    # ----- settings windows and the shortcuts dialog -----
    def settings_window(self,attribute,title,icon,width=520,spacing=12):
        """In the libadwaita window, a settings window (Location & reminders, Languages, Collections) is an AdwPreferencesDialog
        (libadwaita 1.5+; AdwPreferencesWindow on 1.4) holding the same content as before. It keeps the small window's
        interface (present, close, close-request, add_controller), so the code that fills and closes it is shared."""
        Adw=self.Adw; app=self
        def forget(*_):
            if getattr(self,attribute,None) is window: setattr(self,attribute,None)
            return False
        if hasattr(Adw,"PreferencesDialog"):
            class SettingsDialog(Adw.PreferencesDialog):
                def present(self): present_dialog(Adw,self,app.window)
                def close(self):
                    # A dialog closes with an animation and says "closed" afterwards; forget it now, so opening it again at once
                    # builds a fresh one instead of showing the one on its way out.
                    if self.get_can_close(): forget()
                    return close_dialog(Adw,self)
                def connect(self,signal,callback,*args):
                    if signal!="close-request": return super().connect(signal,callback,*args)
                    # A small window's close-request may keep it open (Languages, while downloading) by returning True.
                    self.set_can_close(False)
                    def attempt(dialog):
                        if not callback(dialog): forget(); dialog.force_close()
                    return super().connect("close-attempt",attempt)
            window=SettingsDialog(title=title,content_width=width,search_enabled=False)
        else:
            window=Adw.PreferencesWindow(title=title,transient_for=self.window,modal=True,default_width=width,search_enabled=False)
        setattr(self,attribute,window)
        # Closed, it is forgotten, so the next opening builds it afresh (as the small windows do).
        if isinstance(window,Gtk.Window): window.connect("close-request",forget)
        else: window.connect("closed",forget)
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed",self.quit_key); window.add_controller(keys)
        if not isinstance(window,Gtk.Window):
            # Esc through the same close as the Close button (see close_dialog).
            escape=Gtk.EventControllerKey(propagation_phase=Gtk.PropagationPhase.CAPTURE)
            escape.connect("key-pressed",lambda _c,key,*_:(window.close(),True)[1] if key==Gdk.KEY_Escape else False); window.add_controller(escape)
        page=Adw.PreferencesPage(title=title,icon_name=icon); group=Adw.PreferencesGroup(); page.add(group); window.add(page)
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=spacing); group.add(box)
        return window,box
    def adwaita_shortcuts(self):
        """The shortcuts in libadwaita's own dialog (1.8+), else GTK's shortcuts window; both list them by group, with the keys drawn."""
        Adw=self.Adw
        if hasattr(Adw,"ShortcutsDialog"):
            dialog=Adw.ShortcutsDialog()
            for title,items in SHORTCUT_GROUPS:
                section=Adw.ShortcutsSection(title=title)
                for name,keys in items: section.add(Adw.ShortcutsItem(title=name,accelerator=keys))
                dialog.add(section)
            dialog.connect("closed",lambda *_:setattr(self,"shortcuts_window",None))
            self.shortcuts_window=dialog; dialog.present(self.window); return dialog
        xml=['<interface><object class="GtkShortcutsWindow" id="window"><property name="modal">1</property><child><object class="GtkShortcutsSection"><property name="section-name">all</property>']
        for title,items in SHORTCUT_GROUPS:
            xml.append(f'<child><object class="GtkShortcutsGroup"><property name="title">{GLib.markup_escape_text(title)}</property>')
            for name,keys in items:
                xml.append(f'<child><object class="GtkShortcutsShortcut"><property name="title">{GLib.markup_escape_text(name)}</property><property name="accelerator">{GLib.markup_escape_text(keys)}</property></object></child>')
            xml.append('</object></child>')
        xml.append('</object></child></object></interface>')
        window=Gtk.Builder.new_from_string("".join(xml),-1).get_object("window")
        window.set_transient_for(self.window)
        window.connect("close-request",lambda *_:(setattr(self,"shortcuts_window",None),False)[1])
        self.shortcuts_window=window; window.present(); return window

    # ----- notices -----
    def shell_notice(self,text):
        self.notice_log.append(text)
        toast=self.Adw.Toast(title=GLib.markup_escape_text(text),timeout=0)
        self.toasts.add_toast(toast)
