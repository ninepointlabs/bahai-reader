"""Search everything, or only the open book (Ctrl+K): results grouped by book, opening the passage at the match. Offline,
and without regard to case, accents or apostrophes, like the contents search."""
from gi.repository import Gtk, Gdk, GLib, Pango

from .labels import heading, list_title
from .library import book_of
from .search import find, fold, search_passages, snippet

SHOWN=60  # results listed at once; the count says how many there are

def place_of(item):
    """The group a result is listed under: its book, or the prayers' category."""
    book=book_of(item)
    if book: return book
    return "Prayers · "+(item["tags"][0] if item["tags"] else "Prayers")

class FinderMixin:
    """Reader methods: the Ctrl+K search window."""
    def scope_items(self):
        """What “This book” means for the passage on show: its book, or all the prayers. None when nothing is open."""
        item=self.current if self.on_passage() else None
        if not item: return None,None
        book=book_of(item)
        if book: return book,[i for i in self.items if book_of(i)==book]
        if item["section"]=="prayers": return "Prayers",[i for i in self.items if i["section"]=="prayers"]
        return None,None
    def open_finder(self,*_):
        if getattr(self,"finder",None):
            self.finder_entry.grab_focus(); return
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        top=Gtk.Box(spacing=10,margin_top=12,margin_bottom=10,margin_start=14,margin_end=14)
        entry=Gtk.SearchEntry(hexpand=True,placeholder_text="Search the texts…"); self.name_widget(entry,"Search the texts"); top.append(entry); box.append(top)
        scopes=Gtk.Box(spacing=8,margin_start=14,margin_end=14,margin_bottom=8)
        self.finder_book,self.finder_book_items=self.scope_items()
        book=Gtk.ToggleButton(label="This book"); every=Gtk.ToggleButton(label="Everything",group=book)
        for button in (book,every): button.add_css_class("pill"); button.add_css_class("small-pill"); scopes.append(button)
        book.set_visible(self.finder_book is not None)
        if self.finder_book: book.set_tooltip_text(f"Only {self.finder_book}")
        every.set_active(True)
        note=Gtk.Label(label="Ignores accents and apostrophes · offline",hexpand=True,xalign=1); note.add_css_class("dim-label"); scopes.append(note)
        box.append(scopes); box.append(Gtk.Separator())
        results=Gtk.ListBox(selection_mode=Gtk.SelectionMode.BROWSE); results.add_css_class("navigation-sidebar"); self.name_widget(results,"Results")
        results.set_header_func(self.finder_header)
        scroll=Gtk.ScrolledWindow(vexpand=True,hscrollbar_policy=Gtk.PolicyType.NEVER,min_content_height=360); scroll.set_child(results); box.append(scroll)
        status=Gtk.Label(xalign=0,margin_start=14,margin_end=14,margin_top=8,margin_bottom=10,wrap=True); status.add_css_class("dim-label"); box.append(status)
        self.finder_entry=entry; self.finder_results=results; self.finder_status=status; self.finder_scope_book=book; self.finder_scope_every=every
        entry.connect("search-changed",lambda *_:self.finder_update())
        entry.connect("activate",lambda *_:self.finder_open(results.get_row_at_index(0)))
        for button in (book,every): button.connect("toggled",lambda b:b.get_active() and self.finder_update())
        results.connect("row-activated",lambda _l,row:self.finder_open(row))
        keys=Gtk.EventControllerKey(); keys.connect("key-pressed",self.finder_key); entry.add_controller(keys)
        # libadwaita 1.5+ has a proper dialog; elsewhere (classic window, libadwaita 1.4) a small modal window.
        Adw=getattr(self,"Adw",None)
        if Adw and hasattr(Adw,"Dialog"):
            dialog=Adw.Dialog(title="Search",content_width=640,content_height=560)
            view=Adw.ToolbarView(); view.add_top_bar(Adw.HeaderBar()); view.set_content(box); dialog.set_child(view)
            dialog.connect("closed",lambda *_:self.finder_closed())
            self.finder=dialog; dialog.present(self.window)
        else:
            window=Gtk.Window(title="Search",modal=True,transient_for=self.window,default_width=640,default_height=560)
            window.set_child(box); window.connect("close-request",lambda *_:(self.finder_closed(),False)[1])
            escape=Gtk.EventControllerKey(); escape.connect("key-pressed",lambda _c,key,*_:(window.close(),True)[1] if key==Gdk.KEY_Escape else False); window.add_controller(escape)
            quitting=Gtk.EventControllerKey(); quitting.connect("key-pressed",self.quit_key); window.add_controller(quitting)
            self.finder=window; window.present()
        entry.grab_focus(); self.finder_update()
    def finder_closed(self):
        self.finder=None
    def close_finder(self):
        if self.finder:
            finder=self.finder; self.finder=None; finder.close()
    def finder_key(self,controller,key,code,modifiers):
        if key==Gdk.KEY_Down:
            row=self.finder_results.get_row_at_index(0)
            if row: self.finder_results.select_row(row); row.grab_focus(); return True
        return False
    def finder_header(self,row,before):
        if before is None or before.place!=row.place:
            label=Gtk.Label(label=row.place,xalign=0,margin_start=10,margin_top=8 if before else 2,margin_bottom=2); label.add_css_class("dim-label"); label.add_css_class("heading-small")
            label.set_markup(f"<b>{GLib.markup_escape_text(row.place)}</b>"); row.set_header(label)
        else: row.set_header(None)
    def finder_update(self):
        while row:=self.finder_results.get_row_at_index(0): self.finder_results.remove(row)
        text=self.finder_entry.get_text().strip()
        everything=self.finder_scope_every.get_active() or not self.finder_book
        pool=self.items if everything else self.finder_book_items
        book_count=len(search_passages(self.finder_book_items,text)) if self.finder_book and text else 0
        found=search_passages(pool,text)
        total=len(search_passages(self.items,text)) if text and not everything else len(found)
        if self.finder_book: self.finder_scope_book.set_label(f"This book · {book_count}" if text else "This book")
        self.finder_scope_every.set_label(f"Everything · {total}" if text else "Everything")
        self.finder_found=found
        if not text:
            self.finder_status.set_text("Type a word or phrase. ↓ moves into the results, Enter opens one, Esc closes."); return
        query=fold(text)
        for item in found[:SHOWN]:
            span=find(item["text"],query)
            before,match,after=snippet(item["text"],span)
            row=Gtk.ListBoxRow(); row.item=item; row.span=span; row.place=place_of(item)
            lines=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=2,margin_top=4,margin_bottom=4)
            # A prayer's category is already its group's name; its own opening words tell prayers apart.
            name=list_title(item) if item["section"]=="prayers" else heading(item)
            title=Gtk.Label(xalign=0,ellipsize=Pango.EllipsizeMode.END); title.set_markup(f"<b>{GLib.markup_escape_text(name)}</b>"); lines.append(title)
            body=Gtk.Label(xalign=0,wrap=True,lines=2,ellipsize=Pango.EllipsizeMode.END,max_width_chars=80); body.add_css_class("dim-label")
            body.set_markup(GLib.markup_escape_text(before)+"<b>"+GLib.markup_escape_text(match)+"</b>"+GLib.markup_escape_text(after)); lines.append(body)
            row.set_child(lines); self.name_widget(row,f"{row.place}, {name}: {before}{match}{after}")
            self.finder_results.append(row)
        shown=min(len(found),SHOWN)
        self.finder_status.set_text(f"No passages match “{text}”." if not found else
                                    f"{len(found)} passage{'s' if len(found)!=1 else ''}"+(f"; the first {shown} are listed. Add a word to narrow them." if len(found)>shown else "."))
    def finder_open(self,row):
        """Opens a result where it is in its book or category, with the match selected and scrolled into view."""
        if row is None: return
        item,span=row.item,row.span
        self.close_finder()
        self.open_passage(item,"Search")
        if span:
            buffer=self.reader.get_buffer()
            start,end=buffer.get_iter_at_offset(span[0]),buffer.get_iter_at_offset(span[1])
            self.quiet_selection=tuple(span)  # a found word is selected to show it, not to offer a highlight
            buffer.select_range(start,end)
            mark=buffer.create_mark(None,start,True)
            def scroll():
                self.reader.scroll_to_mark(mark,0.1,True,0,0.3); buffer.delete_mark(mark); return False
            GLib.idle_add(scroll)
        self.reader.grab_focus()
