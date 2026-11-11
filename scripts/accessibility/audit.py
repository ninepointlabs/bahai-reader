"""Reads the running app through AT-SPI, as a screen reader does: every control must have a role and a name."""
import time, sys, json
from pathlib import Path
import pyatspi
INTERACTIVE={pyatspi.ROLE_PUSH_BUTTON,pyatspi.ROLE_TOGGLE_BUTTON,pyatspi.ROLE_CHECK_BOX,pyatspi.ROLE_RADIO_BUTTON,pyatspi.ROLE_ENTRY,
             pyatspi.ROLE_COMBO_BOX,pyatspi.ROLE_LIST_ITEM,pyatspi.ROLE_LINK,pyatspi.ROLE_SLIDER,pyatspi.ROLE_SPIN_BUTTON,pyatspi.ROLE_MENU_ITEM,
             pyatspi.ROLE_PAGE_TAB,pyatspi.ROLE_TOGGLE_BUTTON}
for name in ("ROLE_SEARCH_ENTRY","ROLE_SWITCH"):
    if hasattr(pyatspi,name): INTERACTIVE.add(getattr(pyatspi,name))
def find_app():
    desktop=pyatspi.Registry.getDesktop(0)
    for i in range(desktop.childCount):
        a=desktop.getChildAtIndex(i)
        if a and a.name and ("python" in a.name.lower() or "bahai" in a.name.lower() or "reader" in a.name.lower()): return a
    return None
def walk(node,depth=0,out=None):
    out=out if out is not None else []
    try:
        states=node.getState()
        if not states.contains(pyatspi.STATE_SHOWING): return out
        out.append(node)
        for i in range(min(node.childCount,400)): 
            c=node.getChildAtIndex(i)
            if c: walk(c,depth+1,out)
    except Exception: pass
    return out
def label_of(n):
    name=(n.name or "").strip()
    if name: return name
    try:
        for rel in n.getRelationSet():
            if rel.getRelationType()==pyatspi.RELATION_LABELLED_BY and rel.getNTargets(): return (rel.getTarget(0).name or "").strip()
    except Exception: pass
    # A list item or button named by the text inside it
    try:
        for i in range(n.childCount):
            c=n.getChildAtIndex(i)
            if c and c.getRoleName()=="label" and c.name: return c.name.strip()
    except Exception: pass
    return ""
report={}; seen=None
deadline=time.time()+300
app=None
while time.time()<deadline:
    if app is None: app=find_app()
    state=Path("/tmp/a11y-state").read_text() if Path("/tmp/a11y-state").exists() else None
    if state=="end": break
    if state and state!=seen and app is not None:
        nodes=[]
        for i in range(app.childCount):
            w=app.getChildAtIndex(i)
            if w: walk(w,0,nodes)
        controls=[n for n in nodes if n.getRole() in INTERACTIVE]
        unnamed=[f"{n.getRoleName()} (parent: {n.parent.getRoleName() if n.parent else '-'} {label_of(n.parent) if n.parent else ''})" for n in controls if not label_of(n)]
        focused=next((f"{n.getRoleName()}: {label_of(n)!r}" for n in nodes if n.getState().contains(pyatspi.STATE_FOCUSED)),"(nothing focused)")
        report[state]=dict(controls=len(controls),unnamed=unnamed,focused=focused)
        print(f"{state}: {len(controls)} controls, {len(unnamed)} unnamed; focus → {focused}",flush=True)
        def kids(n,d=0):
            out=[]
            try:
                for i in range(min(n.childCount,6)):
                    c=n.getChildAtIndex(i); out.append(("  "*d)+f"{c.getRoleName()}:{c.name!r}"); out+=kids(c,d+1) if d<2 else []
            except Exception: pass
            return out
        print("   named sample:",[label_of(n) for n in controls if label_of(n)][:8],flush=True)
        for n in [n for n in controls if not label_of(n)][:4]:
            print("   unnamed:",n.getRoleName(),"desc=",repr(n.description),"| kids:",kids(n)[:6],flush=True)
        seen=state; Path("/tmp/a11y-ack").write_text(state)
    time.sleep(0.4)
Path("/out/a11y-report.json").write_text(json.dumps(report,indent=1,ensure_ascii=False))
print("app found:",app.name if app else None)
