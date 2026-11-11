"""Bahá’í Reader: a quiet, native Linux reader for Bahá’í prayers and writings (GTK 4, PyGObject).

Modules, from the data up to the window:
  config, settings          paths, app facts, settings.json
  library, search,          the texts and how they are grouped, searched,
  citations, labels         cited and named
  theme, rendering, ui,     palettes and CSS, styled text, layout constants,
  widgets, desktop          shared widgets, desktop integration
  contents, reading, saved, today, counter, reminders,
  about, location, languages                       the views and windows, as mixins of
  app, shell                                       Reader, the Gtk.Application; shell builds its libadwaita window
"""
import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Pango", "1.0")
