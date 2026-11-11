"""What the reading pane and the contents list call a passage."""

from .library import OBLIGATORY_PRAYERS
def word_label(item):
    count=item["word_count"]
    return f"{count} word{'s' if count != 1 else ''}"

def heading(item,context=None):
    """The reading pane's title: what the passage is, not just its number. context is the category it was opened in, if any."""
    if item["section"]=="prayers":
        # Where the prayer sits: its own name for an obligatory prayer, else its category. Never just "Prayer".
        named=next((t for t in OBLIGATORY_PRAYERS if t in item["tags"]),None)
        if named:
            # bahai.org prints the name at the top of the text; then the section says where it is instead.
            return "Obligatory prayers" if item.get("text","").lstrip().startswith(named) else named
        if context in item["tags"]: return context
        return item["tags"][0] if item["tags"] else "Prayer"
    if item.get("heading"): return item["heading"]
    number=item["title"].split(" · ")[0]; parts=item["id"].split(":"); kind=parts[-2] if len(parts)>=2 else parts[0]
    if kind=="hidden":
        origin="Arabic" if "From the Arabic" in item["tags"] else "Persian" if "From the Persian" in item["tags"] else None
        return f"{origin} no. {number}" if origin else number
    return {"Paragraphs":f"Paragraph {number}","QAs":f"Question and Answer {number}","Notes":f"Note {number}"}.get(kind,number)

def subtitle(item,context=None):
    """The line under the heading: the rest of where the passage is and how long it is, never a repeat of the heading."""
    title=heading(item,context)
    parts=item["tags"]+([item["subgroup"]] if item["subgroup"] else [])
    if item["section"]=="prayers": parts=[item.get("author")]+parts+[word_label(item)]
    elif item.get("author") and not any(item["author"] in p for p in parts+[title] if p): parts=parts+[item["author"]]
    return " · ".join(dict.fromkeys(p for p in parts if p and p!=title))

def list_title(item):
    """A passage's name in the contents list. The obligatory prayers go by their names, not their first line of directions."""
    if item["section"]=="prayers":
        named=next((t for t in OBLIGATORY_PRAYERS if t in item["tags"]),None)
        if named: return named
    return item["title"]
