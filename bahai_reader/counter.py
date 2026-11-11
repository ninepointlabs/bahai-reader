"""The Alláh-u-Abhá counter."""
from gi.repository import Gtk, Gdk
import badi

from .library import unnumbered
from .widgets import Choice

class CounterMixin:
    """Reader methods: the Alláh-u-Abhá counter."""
    def counter_key(self,controller,key,code,modifiers):
        """Before the focused widget sees the key: GTK's text views bind Ctrl+Shift+A to Deselect, and holding Space must not count on."""
        control=bool(modifiers & Gdk.ModifierType.CONTROL_MASK); shift=bool(modifiers & Gdk.ModifierType.SHIFT_MASK)
        if control and shift and key in (Gdk.KEY_a,Gdk.KEY_A): self.show_counter(); return True
        if self.views.get_visible_child_name()!="counter": return False
        if key==Gdk.KEY_Escape: self.leave_counter(); return True
        if control and key in (Gdk.KEY_0,Gdk.KEY_KP_0): self.counter_reset(); return True
        if control or modifiers & Gdk.ModifierType.ALT_MASK: return False
        focus=self.window.get_focus()
        typing=isinstance(focus,Gtk.Text) or isinstance(focus,Gtk.Editable)
        if key==Gdk.KEY_BackSpace and not typing: self.counter_undo(); return True
        if key in (Gdk.KEY_space,Gdk.KEY_Return,Gdk.KEY_KP_Enter,Gdk.KEY_ISO_Enter):
            # Other buttons and the target list keep their own Space and Enter.
            if focus is self.counter_button or focus is None or focus is self.window:
                if key not in self.counter_held: self.counter_held.add(key); self.counter_add()
                return True
        return False

    def build_counter(self):
        self.counter=badi.Counter(self.prefs.get("counter_target",badi.Counter.DEFAULT)); self.counter_return="reading"
        scroll=Gtk.ScrolledWindow(vexpand=True,hexpand=True,hscrollbar_policy=Gtk.PolicyType.NEVER); self.views.add_named(scroll,"counter")
        box=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=14,halign=Gtk.Align.CENTER,margin_top=32,margin_bottom=32,margin_start=16,margin_end=16); scroll.set_child(box)
        title=Gtk.Label(label="Alláh-u-Abhá"); title.add_css_class("heading"); box.append(title)
        self.counter_count=Gtk.Label(label="0"); self.counter_count.add_css_class("counter-count"); box.append(self.counter_count)
        self.counter_state=Gtk.Label(); box.append(self.counter_state)
        self.counter_button=self.button("Count",lambda *_:self.counter_add()); self.counter_button.add_css_class("counter-button"); self.counter_button.add_css_class("primary"); self.counter_button.set_halign(Gtk.Align.CENTER); box.append(self.counter_button)
        controls=Gtk.Box(spacing=10,halign=Gtk.Align.CENTER); box.append(controls); self.counter_controls=controls
        controls.append(Gtk.Label(label="Target"))
        self.counter_target=Choice(); self.name_widget(self.counter_target,"Target")
        for preset in badi.Counter.PRESETS: self.counter_target.append(str(preset),str(preset))
        self.counter_target.append("custom","Custom…"); controls.append(self.counter_target)
        self.counter_custom=Gtk.Entry(visible=False,width_chars=6,placeholder_text="Number"); self.name_widget(self.counter_custom,"Custom target"); controls.append(self.counter_custom)
        self.counter_custom.connect("activate",lambda *_:self.counter_apply_custom())
        self.counter_custom.connect("changed",lambda *_:self.counter_apply_custom())
        self.counter_undo_button=self.button("Undo",lambda *_:self.counter_undo()); controls.append(self.counter_undo_button)
        self.counter_reset_button=self.button("Reset",lambda *_:self.counter_reset()); controls.append(self.counter_reset_button)
        back=self.button("Back",lambda *_:self.leave_counter()); back.set_tooltip_text("Back to where you were (Esc)"); controls.append(back)
        self.counter_verse=Gtk.Label(wrap=True,xalign=0,max_width_chars=60,margin_top=18); self.counter_verse.add_css_class("today-reading"); box.append(self.counter_verse)
        self.counter_source=Gtk.Label(wrap=True,xalign=0,max_width_chars=60); self.counter_source.add_css_class("dim-label"); box.append(self.counter_source)
        target=self.counter.target
        if target in badi.Counter.PRESETS: self.counter_target.set_active_id(str(target))
        else: self.counter_target.set_active_id("custom"); self.counter_custom.set_visible(True); self.counter_custom.set_text(str(target))
        self.counter_target.connect("changed",self.counter_target_changed)
        self.counter_show()

    def counter_verse_item(self):
        """Kitáb-i-Aqdas ¶18 from the current library, with its citation."""
        return next((i for i in self.items if i["id"].endswith("aqdas:Paragraphs:18")),None)

    def show_counter(self,*_):
        current=self.views.get_visible_child_name()
        if current!="counter": self.counter_return=current
        self.show_view("counter")
        item=self.counter_verse_item()
        self.counter_verse.set_visible(bool(item)); self.counter_source.set_visible(bool(item))
        if item: self.counter_verse.set_text(unnumbered(item)); self.counter_source.set_text("— "+item["citation"])
        self.counter_button.grab_focus()

    def leave_counter(self):
        self.show_view(self.counter_return)
        if self.counter_return=="reading" and self.current: self.reader.grab_focus()
        else: self.focus_view()

    def counter_show(self):
        counter=self.counter; state=str(counter)
        self.counter_count.set_text(str(counter.count)); self.counter_state.set_text(state)
        if counter.done: self.counter_count.add_css_class("counter-done")
        else: self.counter_count.remove_css_class("counter-done")
        self.counter_button.set_label("Complete" if counter.done else "Count")
        # The label stays current for anyone who asks for it; only milestones are spoken unprompted.
        self.name_widget(self.counter_count,state)

    def counter_announce(self):
        if self.counter.milestone and hasattr(self.counter_state,"announce"):
            self.counter_state.announce(str(self.counter),Gtk.AccessibleAnnouncementPriority.MEDIUM)

    def counter_add(self):
        if self.counter.add(): self.counter_show(); self.counter_announce()

    def counter_undo(self):
        if self.counter.undo(): self.counter_show()

    def counter_reset(self):
        self.counter.reset(); self.counter_show()

    def counter_set_target(self,value):
        if not self.counter.set_target(value): return False
        self.prefs["counter_target"]=self.counter.target; self.save(); self.counter_show(); return True

    def counter_target_changed(self,choice):
        chosen=choice.get_active_id()
        self.counter_custom.set_visible(chosen=="custom")
        if chosen=="custom": self.counter_apply_custom(); self.counter_custom.grab_focus()
        elif chosen: self.counter_set_target(chosen)

    def counter_apply_custom(self):
        self.counter_set_target(self.counter_custom.get_text())
