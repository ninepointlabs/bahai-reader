"""The application and its window: header, sidebar, panes, keyboard handling and navigation between sections."""
import json
import shutil
import sys
from gi.repository import Gtk, Gdk, Gio, GLib, Pango
import badi

from . import config
from .about import AboutMixin
from .config import APP_NAME
from .contents import ContentsMixin
from .counter import CounterMixin
from .languages import LanguagesMixin
from .library import catalog, load_library, local_pack
from .location import LocationMixin
from .reading import ReadingMixin
from .reminders import RemindersMixin
from .finder import FinderMixin
from .highlights import HighlightsMixin
from .saved import SavedMixin
from .shell import ShellMixin, adwaita
from .settings import CHROME_FONTS, WRITINGS_GROUPINGS, load_settings
from .theme import ThemeMixin
from .today import TodayMixin
from .ui import CONTENT_MIN_WIDTH, FADE_HEIGHT, NARROW_WIDTH, SECTION_ROWS
from .widgets import Choice

class Reader(ShellMixin, FinderMixin, HighlightsMixin, ContentsMixin, ReadingMixin, SavedMixin, RemindersMixin, CounterMixin, TodayMixin, ThemeMixin, AboutMixin, LocationMixin, LanguagesMixin, Gtk.Application):
    def __init__(self,background=False):
        super().__init__(application_id="org.bahai.Reader")
        self.window=None; self.notices=[]; self.save_failed=False; self.background_launch=background; self.ticking=False; self.held=False
        self.prefs,notice=load_settings(config.STATE)
        if notice: self.notices.append(notice)
        self.languages=catalog(); self.language=self.prefs.get("language",1); self.downloading=False
        if self.language!=1 and local_pack(self.language) is None:
            name=self.language_info().get("English",self.language_info()["Name"])
            if (config.LIBRARY/f"{self.language}.json").exists(): self.notices.append(f"The downloaded {name} library could not be read, so English is shown. Download it again in ⋮ → Languages & offline libraries.")
            else: self.notices.append(f"The {name} library is not downloaded, so English is shown.")
            self.language=1
        self.adwaita=False; self.book=None; self.finder=None
        self._items=None; self.section="today"; self.fixed_now=None; self.current=None; self.signature=None; self.palette_source=None; self.resolved_colors={}
        self.connect("activate", self.activate)
        said=Gio.SimpleAction.new("said",GLib.VariantType.new("s")); said.connect("activate",lambda _a,key:self.notification_said(key.get_string())); self.add_action(said)
        opening=Gio.SimpleAction.new("open",GLib.VariantType.new("s")); opening.connect("activate",lambda _a,target:self.notification_open(target.get_string())); self.add_action(opening)
    @property
    def items(self):
        # A background process that never opens a window never loads the library.
        if self._items is None: self._items=load_library(self.language)
        return self._items
    @items.setter
    def items(self,value): self._items=value
    def save(self):
        temp=config.STATE.with_suffix(".tmp")
        try:
            config.STATE.parent.mkdir(parents=True, exist_ok=True)
            temp.write_text(json.dumps(self.prefs)); temp.replace(config.STATE)
        except OSError as exc:
            # Reading still works; say so once instead of failing every click.
            print(f"bahai-reader: could not save {config.STATE}: {exc}",file=sys.stderr)
            if not self.save_failed: self.notice(f"Settings and saved passages cannot be stored ({exc.strerror or exc}). Changes last until you close the app.")
            self.save_failed=True
            try: temp.unlink(missing_ok=True)
            except OSError: pass
    def notice(self,text):
        if not hasattr(self,"notice_box"): self.notices.append(text); return
        if self.adwaita: return self.shell_notice(text)
        row=Gtk.Box(spacing=12); row.add_css_class("notice")
        row.append(Gtk.Label(label=text,wrap=True,xalign=0,hexpand=True))
        row.append(self.button("Dismiss",lambda *_: (self.notice_box.remove(row), self.notice_box.set_visible(self.notice_box.get_first_child() is not None))))
        self.notice_box.append(row); self.notice_box.set_visible(True)
    def notice_texts(self):
        """The notices shown so far: toasts in the libadwaita window, the notice bar in the classic one."""
        if self.adwaita: return list(self.notice_log)
        texts=[]; row=self.notice_box.get_first_child()
        while row: texts.append(row.get_first_child().get_text()); row=row.get_next_sibling()
        return texts
    def button(self, text, callback):
        b=Gtk.Button(label=text); b.connect("clicked", callback); return b
    def arrow_button(self, text, callback):
        """Previous and Next: the arrows are drawn, but a screen reader hears the name given (“Next passage”), which a button's own
        label would override. get_label/set_label act on the visible text."""
        label=Gtk.Label(label=text); b=Gtk.Button(child=label); b.connect("clicked", callback)
        b.get_label=label.get_label; b.set_label=label.set_label; return b
    def row_button(self, callback):
        """A button that gets its own content (a box of labels). Made without a label: GTK keeps a button's label, even an
        empty one, as the name screen readers announce, over the name given with name_widget."""
        b=Gtk.Button(); b.connect("clicked", callback); return b
    def name_widget(self,widget,text):
        """The name a screen reader announces. PyGObject before 3.44 (Debian 12) may not pass it; the visible text still applies."""
        try: widget.update_property([Gtk.AccessibleProperty.LABEL],[text])
        except (TypeError,AttributeError): pass
    def place(self):
        """Where the day's times come from: the saved location, with the clock hours the user entered, if any, in place of the sun."""
        location=self.prefs.get("location"); hours=self.prefs.get("clock_hours")
        return badi.clock_place(location,hours) if hours else location
    def activate(self, app):
        self.start_ticking()
        if self.background_launch:
            # --background: reminders run with no window until the next launch asks for one.
            self.background_launch=False; self.apply_keep_running(True); return
        self.apply_keep_running(bool(self.prefs.get("keep_running")) or self.held)
        if self.window: self.window.present(); return
        try: self.build()
        except Exception:
            # Never leave a running instance without a window; later launches would find it.
            if self.window: self.window.destroy()
            self.window=None; self.quit(); raise
    def build(self):
        Adw=adwaita()
        if Adw: return self.build_adwaita(Adw)
        self.window=Gtk.ApplicationWindow(application=self, title="Bahá’í Reader", default_width=1160, default_height=790)
        self.window.connect("close-request",self.window_closing)
        outer=Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        header=Gtk.HeaderBar(); header.set_show_title_buttons(not bool(shutil.which("omarchy"))); self.app_title=Gtk.Label(label=APP_NAME,ellipsize=Pango.EllipsizeMode.END); self.app_title.add_css_class("app-title"); header.set_title_widget(self.app_title)
        self.narrow=False; self.sidebar_wanted=True
        # Today lives in the section list only; Random is an action, so it sits in the menu rather than beside navigation.
        panel=Gtk.Button(icon_name="sidebar-show-symbolic"); panel.connect("clicked",self.toggle_sidebar); panel.set_tooltip_text("Show or hide the contents (Esc)"); self.name_widget(panel,"Contents"); header.pack_start(panel)
        # The menu holds what concerns the whole app; Aa holds only how the text reads.
        more=Gtk.MenuButton(icon_name="view-more-symbolic"); more.set_tooltip_text("Menu"); more.add_css_class("app-menu"); self.name_widget(more,"Menu"); self.app_menu=more; header.pack_end(more)
        self.make_menu(more)
        for widget in self.make_actions(): header.pack_end(widget)
        self.window.set_child(outer)
        if shutil.which("omarchy"): outer.append(header); self.window.set_decorated(False)
        else: self.window.set_titlebar(header)
        self.notice_box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,visible=False); outer.append(self.notice_box)
        for text in self.notices: self.notice(text)
        self.notices=[]
        self.install_keys()
        body=Gtk.Paned(orientation=Gtk.Orientation.HORIZONTAL)
        self.split=body; self.panel_width_ready=False; self.panel_programmatic=False; self.panel_save_source=None; self.panel_window_width=0
        # Neither pane can be dragged below its minimum width, so neither disappears.
        body.set_resize_start_child(False); body.set_shrink_start_child(False)
        body.set_resize_end_child(True); body.set_shrink_end_child(False)
        outer.append(body); body.set_vexpand(True)
        body.connect("notify::position",self.panel_moved)
        body.add_tick_callback(self.panel_layout)
        self.sidebar=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10); self.sidebar.set_size_request(220,-1); self.sidebar.add_css_class("sidebar")
        for edge in ("top", "bottom", "start", "end"): getattr(self.sidebar,"set_margin_"+edge)(16)
        body.set_start_child(self.sidebar)
        # The sections: one compact list of icon-and-label rows, the current one selected.
        self.switcher=Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE); self.switcher.add_css_class("switcher"); self.switcher_rows={}
        self.name_widget(self.switcher,"Sections")
        for key,title,icon in SECTION_ROWS:
            row=Gtk.ListBoxRow(); row.section=key; line=Gtk.Box(spacing=10)
            image=Gtk.Image(gicon=Gio.ThemedIcon.new_from_names([icon,"text-x-generic-symbolic"]),accessible_role=Gtk.AccessibleRole.PRESENTATION)
            line.append(image); line.append(Gtk.Label(label=title,xalign=0,hexpand=True,ellipsize=Pango.EllipsizeMode.END))
            row.set_child(line); row.set_tooltip_text(title); self.switcher.append(row); self.switcher_rows[key]=row
        self.switcher_syncing=False
        self.switcher.connect("row-selected",lambda _box,row: row and not self.switcher_syncing and row.section!=self.section and self.navigate(row.section))
        self.sidebar.append(self.switcher)
        self.make_contents(self.sidebar)
        self.make_views(); body.set_end_child(self.views)
        self.finish_build()
    def make_menu(self,more):
        """The ⋮ menu: what concerns the whole app."""
        entries=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=2)
        for edge in ("top","bottom","start","end"): getattr(entries,"set_margin_"+edge)(6)
        more_pop=Gtk.Popover(); more_pop.set_child(entries); more.set_popover(more_pop); more_pop.add_css_class("menu")
        def menu_entry(label,action,shortcut=None):
            entry=self.row_button(lambda _,a=action:(more_pop.popdown(),a())); entry.add_css_class("flat")
            row=Gtk.Box(spacing=24); row.append(Gtk.Label(label=label,xalign=0,hexpand=True))
            if shortcut: keys=Gtk.Label(label=shortcut); keys.add_css_class("dim-label"); row.append(keys)
            entry.set_child(row); entry.get_label=lambda:label; self.name_widget(entry,label.rstrip("…")); entries.append(entry); return entry
        self.search_entry=menu_entry("Search the texts…",self.open_finder,"Ctrl+K")
        self.random_entry=menu_entry("Random passage",self.random_passage,"Ctrl+R")
        # In a narrow window the header's Copy rests here.
        self.copy_entry=menu_entry("Copy the passage",self.copy_passage,"Ctrl+Shift+C"); self.copy_entry.set_visible(False); self.narrow_entries=[self.copy_entry]
        more_pop.connect("show",lambda *_:self.copy_entry.set_sensitive(self.copy.get_sensitive()))
        entries.append(Gtk.Separator())
        for label,action,keys in (("Location & reminders…",self.location_dialog,None),("Languages & offline libraries…",self.language_dialog,None),("Keyboard shortcuts",self.shortcuts_dialog,None),("About Bahá’í Reader",self.about_dialog,"F1")):
            menu_entry(label,action,keys)
    def make_actions(self):
        """Save, Copy and Aa, in the order a header packs them from the end."""
        self.star=self.button("☆ Save", self.bookmark); self.star.set_tooltip_text("Save this passage (Ctrl+D)"); 
        self.copy=self.button("Copy", self.copy_passage); self.copy.set_tooltip_text("Copy the passage with its citation (Ctrl+Shift+C)"); 
        self.wide_header=(self.copy,)
        menu=Gtk.MenuButton(label="Aa"); menu.set_tooltip_text("Text and appearance"); pop=Gtk.Popover(); menu.set_popover(pop); self.text_menu=menu
        settings=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        for edge in ("top", "bottom", "start", "end"): getattr(settings, "set_margin_"+edge)(18)
        pop.set_child(settings)
        self.option(settings, "Appearance", "theme", ["Omarchy", "Light", "Dark", "Sepia"], "Omarchy")
        self.option(settings, "Interface font", "chrome_font", list(CHROME_FONTS), "System")
        fonts=sorted({f.get_name() for f in self.window.get_pango_context().list_families()})
        self.option(settings, "Reading font", "font", fonts, "Noto Serif" if "Noto Serif" in fonts else "DejaVu Serif")
        self.slider(settings, "Text size", "size", 15, 36, 22)
        self.slider(settings, "Line spacing", "spacing", 0, 20, 8)
        self.slider(settings, "Page margins", "margin", 24, 160, 80)
        settings.append(Gtk.Label(label="Side by side",xalign=0)); self.compare=Choice(); settings.append(self.compare)
        self.compare.connect("changed",self.compare_changed); self.compare_cache=(None,{}); self.filling_compare=False
        pop.connect("show",lambda *_: self.fill_compare())
        return [self.star,self.copy,self.text_menu]
    def install_keys(self):
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed", self.key_pressed); self.window.add_controller(keys)
        self.counter_held=set()
        counting=Gtk.EventControllerKey(propagation_phase=Gtk.PropagationPhase.CAPTURE); counting.connect("key-pressed",self.counter_key); counting.connect("key-released",lambda _c,key,*_:self.counter_held.discard(key)); self.window.add_controller(counting)
        # Previous/Next before the reading view's own cursor keys see them.
        paging=Gtk.EventControllerKey(propagation_phase=Gtk.PropagationPhase.CAPTURE); paging.connect("key-pressed", self.page_key); self.window.add_controller(paging)
    def make_contents(self,box):
        """Below the sections: Manage collections, the Writings grouping, the search entry, the count and the contents tree."""
        self.manage=self.button("Manage collections…",self.collections_dialog); self.manage.set_visible(False); box.append(self.manage)
        self.grouping=Choice()
        for key,label in WRITINGS_GROUPINGS.items(): self.grouping.append(key,label)
        self.grouping.set_active_id(self.prefs.get("writings_by","book")); self.grouping.set_visible(False)
        self.grouping.set_tooltip_text("List the Writings by book, or by author and then book")
        self.grouping.connect("changed",self.change_grouping); box.append(self.grouping)
        self.search=Gtk.SearchEntry(placeholder_text="Search this section…"); self.search.connect("search-changed", self.filter); box.append(self.search)
        self.name_widget(self.search,"Search this section")
        into_list=Gtk.EventControllerKey(); into_list.connect("key-pressed", self.search_key); self.search.add_controller(into_list)
        self.count=Gtk.Label(xalign=0); self.count.add_css_class("dim-label"); box.append(self.count)
        scroll=Gtk.ScrolledWindow(vexpand=True, hscrollbar_policy=Gtk.PolicyType.EXTERNAL); box.append(scroll)
        self.toc=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4); scroll.set_child(self.toc)
        # The contents list is one Tab stop; arrow keys move inside it.
        out_of_list=Gtk.EventControllerKey(propagation_phase=Gtk.PropagationPhase.CAPTURE); out_of_list.connect("key-pressed", self.list_key); scroll.add_controller(out_of_list)
        self.branches={}; self.passage_buttons=[]; self.active_group=[]; self.restoring=False; self.query=None
    def make_views(self):
        """The right-hand views: a passage, Today and the counter."""
        # No transition between views: nothing moves, so there is nothing to reduce for gtk-enable-animations.
        self.views=Gtk.Stack(hexpand=True,vexpand=True,transition_type=Gtk.StackTransitionType.NONE); self.views.set_size_request(CONTENT_MIN_WIDTH,-1)
        right=Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, hexpand=True)
        right.set_margin_top(32); self.views.add_named(right,"reading")
        self.build_today(); self.build_counter()
        self.heading=Gtk.Label(label="Prayers", wrap=True); self.heading.add_css_class("heading"); right.append(self.heading)
        self.subtitle=Gtk.Label(label="A moment for reflection",wrap=True,justify=Gtk.Justification.CENTER,margin_start=12,margin_end=12); self.subtitle.add_css_class("dim-label"); right.append(self.subtitle)
        self.reader=Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD, vexpand=True, hexpand=True)
        self.reader.set_top_margin(24); self.reader.set_bottom_margin(50)
        self.pages=Gtk.Box(homogeneous=True, vexpand=True)
        # The text fades out above the footer instead of being cut mid-line under it.
        pages_overlay=Gtk.Overlay(vexpand=True); pages_overlay.set_child(self.pages); right.append(pages_overlay)
        self.fade=Gtk.Box(valign=Gtk.Align.END,height_request=FADE_HEIGHT,can_target=False); self.fade.add_css_class("reading-fade"); pages_overlay.add_overlay(self.fade)
        self.readscroll=Gtk.ScrolledWindow(vexpand=True, kinetic_scrolling=True, hscrollbar_policy=Gtk.PolicyType.NEVER); self.readscroll.set_child(self.reader); self.pages.append(self.readscroll)
        # A second language beside the passage, from a downloaded library; never fetched while reading.
        self.second=Gtk.TextView(editable=False, cursor_visible=False, wrap_mode=Gtk.WrapMode.WORD, vexpand=True, hexpand=True)
        self.second.set_top_margin(24); self.second.set_bottom_margin(50)
        self.secondscroll=Gtk.ScrolledWindow(vexpand=True, visible=False, hscrollbar_policy=Gtk.PolicyType.NEVER); self.secondscroll.set_child(self.second); self.pages.append(self.secondscroll)
        self.readscroll.get_vadjustment().connect("value-changed",self.follow_scroll)
        self.scroll_tick=None; self.scroll_target=0.0; self.scroll_time=None; self.scroll_direction=0
        wheel=Gtk.EventControllerScroll.new(Gtk.EventControllerScrollFlags.VERTICAL)
        wheel.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        wheel.connect("scroll",self.reader_scroll); self.readscroll.add_controller(wheel)
        click=Gtk.GestureClick(); click.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        click.connect("pressed",lambda *_:self.stop_scroll()); self.readscroll.add_controller(click)
        self.related=Gtk.MenuButton(label="Related passages",visible=False); right.append(self.related)
        self.said_toggle=Gtk.ToggleButton(label="Said today",halign=Gtk.Align.CENTER,visible=False,tooltip_text="Mark this obligatory prayer as said. Today shows what is said and what is still open."); self.said_toggle.connect("toggled",self.said_toggled); right.append(self.said_toggle)
        self.filing=Gtk.Box(spacing=10,halign=Gtk.Align.CENTER,visible=False); right.append(self.filing)
        self.filing.append(Gtk.Label(label="Collection")); self.collection=Choice(); self.filing.append(self.collection)
        self.collection.connect("changed",self.file_current); self.filling=False
        self.filing.append(self.button("Manage…",self.collections_dialog))
        footer=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=12); footer.add_css_class("reading-footer"); self.footer=footer
        nav=Gtk.Box(spacing=12, halign=Gtk.Align.CENTER); self.previous=self.arrow_button("← Previous", lambda *_: self.step(-1)); nav.append(self.previous)
        self.position=Gtk.Label(); self.position.add_css_class("dim-label"); self.position.add_css_class("count"); nav.append(self.position)
        self.next=self.arrow_button("Next →", lambda *_: self.step(1)); self.next.add_css_class("primary"); nav.append(self.next); footer.append(nav); right.append(footer)
        self.name_widget(self.previous,"Previous passage"); self.name_widget(self.next,"Next passage")
        self.status=Gtk.Label(label="English · Available offline · Texts: BahaiPrayers.net, bahai.org", margin_bottom=16, margin_start=12, margin_end=12, wrap=True, justify=Gtk.Justification.CENTER); self.status.add_css_class("dim-label"); footer.append(self.status)
        self.build_highlights()
    def finish_build(self):
        self.provider=Gtk.CssProvider(); Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(),self.provider,Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        # New installs open on Today; everyone else keeps the section they were in.
        self.update_status(); self.navigate(self.prefs.get("section",self.first_section()),book=self.prefs.get("book")); self.apply_theme(); GLib.timeout_add_seconds(1,self.theme_tick)
        self.window.connect("notify::default-width",self.window_resized); self.window_resized()
        self.window.present()
    def window_closing(self,window):
        """Closing the window keeps the process alive only when reminders are to keep running."""
        if not self.held: return False
        for name in ("about_window","language_window","collections_window","location_window","shortcuts_window"):
            other=getattr(self,name,None)
            if other: other.close()
        window.set_visible(False); return True
    def quit_app(self):
        """Ctrl+Q ends the app, or, while reminders keep running, closes the window as the close button does."""
        if self.held and self.window: self.window_closing(self.window)
        else: self.quit()
    def apply_keep_running(self,wanted):
        """The hold that keeps a process with no window alive. Turning the option off releases it, so closing the window then ends the process."""
        if wanted and not self.held: self.hold(); self.held=True
        elif self.held and not wanted: self.held=False; self.release()
    def panel_layout(self,widget,clock):
        width=widget.get_width()
        if width<=0: return True
        self.window_resized()
        if not self.sidebar.get_visible() or not self.views.get_visible(): self.panel_window_width=width; return True
        if width!=self.panel_window_width or not self.panel_width_ready:
            self.panel_window_width=width
            # Start at 28% of the actual allocated window; remember manual sizing.
            desired=self.prefs.get("sidebar_width", min(400,max(260,round(width*0.28))))
            position=min(max(220,int(desired)),max(220,int(width*0.60)))
            self.panel_programmatic=True; widget.set_position(position); self.panel_programmatic=False
            self.panel_width_ready=True
        return True
    def window_resized(self,*_):
        if self.adwaita: return self.fit_margins()
        """Too narrow for both panes: they take turns and the contents button switches between them. Wide-mode minimums stay under NARROW_WIDTH, so the allocated
        width always gets there, whatever the compositor does; the asked-for size gets there before the first frame."""
        sizes=[n for n in (self.window.get_default_size()[0],self.window.get_width()) if n>0]
        width=min(sizes) if sizes else 0
        narrow=0<width<NARROW_WIDTH
        if narrow!=self.narrow:
            self.narrow=narrow; self.views.set_visible(True)
            self.sidebar.set_visible(self.sidebar_wanted and not narrow)
            for widget in self.wide_header: widget.set_visible(not narrow)
            for entry in self.narrow_entries: entry.set_visible(narrow)
            self.app_title.set_visible(not narrow)
            # Stacked rather than squeezed: two columns of 150 px read badly.
            stacked=Gtk.Orientation.VERTICAL if narrow else Gtk.Orientation.HORIZONTAL
            self.pages.set_orientation(stacked); self.filing.set_orientation(stacked); self.counter_controls.set_orientation(stacked)
            self.previous.set_label("←" if narrow else "← Previous"); self.next.set_label("→" if narrow else "Next →")
            self.panel_width_ready=False; self.update_star()
        self.fit_margins(width or None)
    def fit_margins(self,width=None):
        """Page margins give way once the text column would get narrower than about 360 px."""
        if self.adwaita: return self.shell_fit_margins()
        width=width or self.split.get_width()
        if self.sidebar.get_visible() and self.views.get_visible(): width-=self.split.get_position()
        if self.secondscroll.get_visible() and not self.narrow: width//=2
        margin=min(int(self.prefs.get("margin",80)),max(12,(width-360)//2))
        for view in (self.reader,self.second): view.set_left_margin(margin); view.set_right_margin(margin)
    def toggle_sidebar(self,*_):
        if self.adwaita: return self.shell_toggle_sidebar()
        if self.narrow: self.show_list(not self.sidebar.get_visible())
        else: self.sidebar_wanted=not self.sidebar.get_visible(); self.sidebar.set_visible(self.sidebar_wanted)
    def show_list(self,visible=True):
        """The contents panel; in a narrow window, instead of the right pane."""
        if self.adwaita: return self.shell_show_list(visible)
        self.sidebar.set_visible(visible)
        if self.narrow:
            self.views.set_visible(not visible)
            # Focus must not stay on what was just hidden.
            self.search.grab_focus() if visible else self.focus_view()
        elif visible: self.sidebar_wanted=True
    def show_content(self):
        if self.adwaita:
            if self.splitview.get_collapsed(): self.splitview.set_show_content(True)
            return
        if self.narrow and self.sidebar.get_visible(): self.show_list(False)
    def open_from_list(self,item,group):
        self.show_passage(item,group); self.show_content()
    def panel_moved(self,widget,_):
        if not self.panel_width_ready or self.panel_programmatic or not self.sidebar.get_visible() or not self.views.get_visible():return
        self.prefs["sidebar_width"]=widget.get_position(); self.fit_margins()
        if self.panel_save_source:GLib.source_remove(self.panel_save_source)
        def persist():
            self.panel_save_source=None; self.save(); return False
        self.panel_save_source=GLib.timeout_add(250,persist)
    def key_pressed(self, controller, key, code, modifiers):
        if modifiers & Gdk.ModifierType.CONTROL_MASK:
            if key==Gdk.KEY_t: self.navigate("today"); self.focus_view(); return True
            if key==Gdk.KEY_r: self.random_passage(); return True
            if key==Gdk.KEY_f: self.show_list(); self.search.grab_focus(); return True
            if key==Gdk.KEY_k: self.open_finder(); return True
            if key==Gdk.KEY_question: self.shortcuts_dialog(); return True
            if key==Gdk.KEY_h and self.selected_span(): self.highlight_selection(edit=True); return True
            if key==Gdk.KEY_q: self.quit_app(); return True
            if key==Gdk.KEY_d: self.bookmark(); return True
            if key in (Gdk.KEY_c,Gdk.KEY_C) and modifiers & Gdk.ModifierType.SHIFT_MASK: self.copy_passage(); return True
        if key==Gdk.KEY_F1: self.about_dialog(); return True
        if self.adwaita and key==Gdk.KEY_F11 and not modifiers & (Gdk.ModifierType.CONTROL_MASK|Gdk.ModifierType.ALT_MASK):
            self.set_focus_mode(not self.focus_mode); return True
        if self.adwaita and key==Gdk.KEY_Escape:
            if self.focus_mode: self.set_focus_mode(False); return True
            if self.splitview.get_collapsed() and self.splitview.get_show_content(): self.show_list(); return True
            return False
        if key==Gdk.KEY_Escape:
            if not self.sidebar.get_visible(): self.show_list(); return True
            if self.narrow: self.show_list(False); return True
        return False
    def page_key(self, controller, key, code, modifiers):
        # Alt+Left/Right and Ctrl+Page Up/Down, as in browsers and document viewers.
        if modifiers & Gdk.ModifierType.ALT_MASK and key in (Gdk.KEY_Left,Gdk.KEY_Right):
            self.step(-1 if key==Gdk.KEY_Left else 1); return True
        if modifiers & Gdk.ModifierType.CONTROL_MASK and key in (Gdk.KEY_Page_Up,Gdk.KEY_Page_Down):
            self.step(-1 if key==Gdk.KEY_Page_Up else 1); return True
        return False
    def quit_key(self, controller, key, code, modifiers):
        # Dialogs are plain windows; keep Ctrl+Q working while they have focus.
        if modifiers & Gdk.ModifierType.CONTROL_MASK and key==Gdk.KEY_q: self.quit_app(); return True
        return False
    def search_key(self, controller, key, code, modifiers):
        if key in (Gdk.KEY_Tab,Gdk.KEY_Down) and not modifiers & (Gdk.ModifierType.SHIFT_MASK|Gdk.ModifierType.CONTROL_MASK):
            return self.focus_list()
        return False
    def focus_list(self):
        current=next((b for i,b in self.passage_buttons if self.current and i["id"]==self.current["id"] and b.is_drawable()),None)
        target=current or next((e for e,*_ in self.branch_rows if e.get_visible()),None)
        return bool(target) and target.grab_focus()
    def list_key(self, controller, key, code, modifiers):
        if key==Gdk.KEY_ISO_Left_Tab or (key==Gdk.KEY_Tab and modifiers & Gdk.ModifierType.SHIFT_MASK):
            self.search.grab_focus(); return True
        if key==Gdk.KEY_Tab: return self.focus_view()
        return False
    def focus_view(self):
        """Into whichever view is showing: the reading pane, or the first action on it."""
        if self.views.get_visible_child_name()=="reading": self.reader.grab_focus(); return True
        self.window.set_focus(None)  # from the top of the view, wherever the focus was
        return self.views.get_visible_child().child_focus(Gtk.DirectionType.TAB_FORWARD)
    def option(self, box, title, key, options, default):
        box.append(Gtk.Label(label=title,xalign=0)); combo=Choice()
        for item in options: combo.append_text(item)
        fallback=default if default in options else (options[0] if options else "")
        value=self.prefs.get(key,fallback); combo.set_active_id(value if value in options else fallback)
        def change(c): self.prefs[key]=c.get_active_text(); self.save(); self.signature=None; self.apply_theme()
        combo.connect("changed",change); box.append(combo)
    def slider(self,box,title,key,low,high,default):
        box.append(Gtk.Label(label=title,xalign=0)); scale=Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL,low,high,1)
        scale.set_value(self.prefs.get(key,default)); scale.set_draw_value(True)
        def change(s): self.prefs[key]=int(s.get_value()); self.save(); self.signature=None; self.apply_theme()
        scale.connect("value-changed",change); box.append(scale)
    def navigate(self,key,book=None):
        """Open a section. book: in the libadwaita window, the book to open in Writings (None shows the library)."""
        if key=="home" and not self.adwaita: key="today"
        self.section="writings" if key=="gleanings" else key
        self.book=book if self.adwaita and self.section=="writings" else None
        if self.book: self.prefs["book"]=self.book
        else: self.prefs.pop("book",None)
        self.prefs["section"]=self.section; self.save(); self.search.set_text(""); self.manage.set_visible(self.section=="saved")
        self.switcher_syncing=True; self.switcher.select_row(self.switcher_rows.get(self.nav_key())); self.switcher_syncing=False
        if self.section in ("today","home") or self.library_showing():
            self.current=None; self.active_group=[]; self.filing.set_visible(False); self.related.set_visible(False)
        self.show_view("today" if self.section=="today" else "home" if self.section=="home" else "library" if self.library_showing() else "reading")
        self.rebuild()
        if self.section=="today": self.refresh_today()
        if self.section=="home": self.refresh_home()
        if self.library_showing(): self.refresh_library()
        if self.adwaita: self.shell_navigated()
    def first_section(self):
        """Where a new install opens: Home in the libadwaita window, Today in the classic one."""
        return "home" if self.adwaita else "today"
    def library_showing(self):
        """Writings with no book open, in the libadwaita window: the library instead of a passage."""
        return self.adwaita and self.section=="writings" and not self.book
    def show_view(self,name):
        """The right pane: a passage, or Today. Copy and Save act on a passage, so they rest elsewhere."""
        self.views.set_visible_child_name(name)
        if name!="reading": self.show_content()  # a passage is picked from the list; Today and the counter are only here
        ready=name=="reading" and self.current is not None
        self.star.set_sensitive(ready); self.copy.set_sensitive(ready)
        if self.adwaita: self.shell_titles()
