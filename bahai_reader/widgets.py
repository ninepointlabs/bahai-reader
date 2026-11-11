"""Small widgets shared by the views."""
from gi.repository import Gtk, GObject


class Choice(Gtk.DropDown):
    """Gtk.DropDown (ComboBoxText is deprecated since GTK 4.10) with string ids and a "changed" signal."""
    __gsignals__={"changed":(GObject.SignalFlags.RUN_FIRST,None,())}
    def __init__(self,search=False):
        super().__init__(enable_search=search)
        self.ids=[]; self.labels=Gtk.StringList()
        # Search needs an expression; PyGObject before 3.44 (Debian 12) cannot pass one, so those lists don't search.
        try: self.set_expression(Gtk.PropertyExpression.new(Gtk.StringObject,None,"string"))
        except TypeError: self.set_enable_search(False)
        self.set_model(self.labels)
        self.connect("notify::selected",lambda *_:self.emit("changed"))
    def append(self,id,label): self.ids.append(id); self.labels.append(label)
    def append_text(self,label): self.append(label,label)
    def remove_all(self): self.ids=[]; self.labels.splice(0,self.labels.get_n_items(),[])
    def get_active_id(self):
        index=self.get_selected(); return self.ids[index] if index<len(self.ids) else None
    def get_active_text(self):
        index=self.get_selected(); return self.labels.get_string(index) if index<len(self.ids) else None
    def set_active_id(self,id):
        if id in self.ids: self.set_selected(self.ids.index(id))
