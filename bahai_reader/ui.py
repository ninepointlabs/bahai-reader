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
SHORTCUTS=(("Ctrl+F","Show the contents panel and search this section"),("Alt+Right or Ctrl+Page Down","Next passage"),("Alt+Left or Ctrl+Page Up","Previous passage"),
           ("Ctrl+D","Save or unsave the current passage"),("Ctrl+Shift+C","Copy the passage (or the selected words) with its citation"),("Ctrl+T","Today"),("Ctrl+R","Random passage"),("Ctrl+Shift+A","Alláh-u-Abhá counter"),
           ("Space or Enter","In the counter: count one"),("Backspace","In the counter: undo one"),("Ctrl+0","In the counter: start over"),("Escape","In the counter: back to where you were"),
           ("F1","About Bahá’í Reader"),("Ctrl+Q","Quit"),("Escape","Show the contents panel again if it is hidden; in a narrow window, switch back; closes the small windows"),
           ("Tab / Shift+Tab","Move between search, the contents list and the reading pane"),("Page Up / Page Down","Scroll the passage"))
