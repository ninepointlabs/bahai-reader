"""Layout constants and the keyboard shortcut list shared by the views."""

SECTION_ROWS=(("today","Today","x-office-calendar-symbolic"),("prayers","Prayers","emoji-nature-symbolic"),("obligatory","Obligatory prayers","alarm-symbolic"),
              ("hidden","The Hidden Words","text-x-generic-symbolic"),("writings","Writings","accessories-dictionary-symbolic"),("saved","Saved passages","starred-symbolic"))

FADE_HEIGHT=28

# The citation follows the text closely: one line break and this much space, not an empty paragraph.
CITATION_GAP=10

NARROW_WIDTH=700  # below this the contents list and the right pane take turns

CONTENT_MIN_WIDTH=320

CLOCK_ASSEMBLY="Where days and nights vary greatly, prayer and fasting may follow the clock. Your National Spiritual Assembly can tell you the hours used in your country."

# Header menu → Keyboard shortcuts, and the README table.
# The same shortcuts, grouped, with GTK accelerators, for the libadwaita window's shortcuts dialog.
SHORTCUT_GROUPS=(
    ("Reading",(("Next passage","<Alt>Right <Control>Page_Down"),("Previous passage","<Alt>Left <Control>Page_Up"),("Scroll the passage","Page_Up Page_Down"),
                ("Save or unsave the passage","<Control>d"),("Copy the passage (or the selected words) with its citation","<Control><Shift>c"),
                ("Highlight the selected words and open its note","<Control>h"),("Focus mode: only the text","F11"))),
    ("Finding",(("Search all the texts, or only the open book","<Control>k"),("Search this section's contents","<Control>f"),("Today","<Control>t"),("Random passage","<Control>r"))),
    ("Alláh-u-Abhá counter",(("Open the counter","<Control><Shift>a"),("Count one","space Return"),("Undo one","BackSpace"),("Start over","<Control>0"),("Back to where you were","Escape"))),
    ("The app",(("Keyboard shortcuts","<Control>question"),("About Bahá’í Reader","F1"),("Show the sidebar again; leave focus mode; close a dialog","Escape"),("Quit","<Control>q"))),
)
SHORTCUTS=(("Ctrl+F","Show the contents panel and search this section"),("Ctrl+K","Search all the texts, or only the open book"),("Alt+Right or Ctrl+Page Down","Next passage"),("Alt+Left or Ctrl+Page Up","Previous passage"),
           ("Ctrl+D","Save or unsave the current passage"),("Ctrl+H","Highlight the selected words, and open the highlight's colour and note"),("Ctrl+Shift+C","Copy the passage (or the selected words) with its citation"),("Ctrl+T","Today"),("Ctrl+R","Random passage"),("Ctrl+Shift+A","Alláh-u-Abhá counter"),
           ("Space or Enter","In the counter: count one"),("Backspace","In the counter: undo one"),("Ctrl+0","In the counter: start over"),("Escape","In the counter: back to where you were"),
           ("Ctrl+?","Keyboard shortcuts"),("F1","About Bahá’í Reader"),("F11","Focus mode: only the text (libadwaita window); F11 or Escape again brings the sidebar and header back"),("Ctrl+Q","Quit"),("Escape","Show the contents panel again if it is hidden; in a narrow window, switch back; closes the small windows"),
           ("Tab / Shift+Tab","Move between search, the contents list and the reading pane"),("Page Up / Page Down","Scroll the passage"))
