"""How bahai.org's styled spans are drawn in a text view."""
from gi.repository import Pango

# How the styled spans of a bahai.org text are drawn: italics, bold, underlining (transliteration such as Ma<u>sh</u>riq),
# quotations set in from the margin, and the headings of letters and chapters.
SPAN_STYLES={"i":dict(style=Pango.Style.ITALIC),"b":dict(weight=Pango.Weight.BOLD),"u":dict(underline=Pango.Underline.SINGLE),
             "quote":dict(left_margin=36,right_margin=24),"num":dict(scale=0.75,weight=Pango.Weight.LIGHT),"heading":dict(weight=Pango.Weight.BOLD,scale=1.1)}

def apply_spans(buffer,item,offset=0):
    table=buffer.get_tag_table(); length=len(item["text"])
    for start,end,kind in item.get("spans",()):
        if kind not in SPAN_STYLES or not (isinstance(start,int) and isinstance(end,int) and 0<=start<end<=length): continue
        tag=table.lookup("span-"+kind) or buffer.create_tag("span-"+kind,**SPAN_STYLES[kind])
        buffer.apply_tag(tag,buffer.get_iter_at_offset(offset+start),buffer.get_iter_at_offset(offset+end))
