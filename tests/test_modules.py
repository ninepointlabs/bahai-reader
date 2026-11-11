"""The split of reader.py into the bahai_reader package (UX Phase 2, step 1): nothing lost, nothing changed in behaviour,
and the layers stay apart. Needs no display."""
import ast
import re
import unittest
from pathlib import Path
from unittest.mock import patch
import reader
from bahai_reader import config, library, settings

ROOT=Path(__file__).resolve().parents[1]
PACKAGE=ROOT/"bahai_reader"
# Every top-level name and every Reader method of reader.py before the split (0.1.9 plus UX Phase 1).
TOP_LEVEL="""
    APP_NAME TAGLINE ORGANIZATION SUPPORT_EMAIL CREATED LICENSE_NAME COPYRIGHT ROOT STATE CACHE FEEDS BOOKS
    PRAYER_FEED_BOOKS AUTOSTART LIBRARY LANGUAGE_ENDPOINTS HOLY_DAYS AQDAS_SECTIONS SECTION_NAMES
    PRAYER_AUTHORS BOOK_AUTHORS shipped version SECTIONS SECTION_ROWS CHROME_FONTS FADE_HEIGHT
    WRITINGS_GROUPINGS AUTHOR_ORDER THEMES LIMITS short_path number clean_settings CITATION_GAP NARROW_WIDTH
    CONTENT_MIN_WIDTH UNSORTED CLOCK_ASSEMBLY REMINDER_SWITCHES SAID_KEY DAY_KEY clean_records
    collection_name clean_collections load_settings download_problem fetch_json atomic_json catalog
    validate_feed local_pack download_language PlainText plain fold roman citation clipping luminance
    contrast readable stylesheet word_count word_label ALIGN align heading subtitle list_title OFFICIAL
    BAHAI_ORG_NOTICE official_items official_replacements use_official load_library load_bahaiprayers
    OBLIGATORY_PRAYERS AQDAS_ON_PRAYER obligatory DIRECTION SPAN_STYLES unnumbered apply_spans directions
    REFLECTION_BOOKS REFLECTION_WORDS reflections passage_of_the_day in_flatpak desktop_quote launch_command
    autostart_entry write_autostart remove_autostart load_cities CITIES search_cities badi_days_tag
    clock_style clock AYYAM_PRAYERS FAST_PRAYERS DAYS_OF_NOTE SHORTCUTS Choice Reader usage main
""".split()
METHODS="""
    __init__ items items save notice button name_widget place activate build theme_tick window_closing
    quit_app apply_keep_running stop_scroll reader_scroll queue_scroll animate_scroll panel_layout
    window_resized fit_margins toggle_sidebar show_list show_content open_from_list panel_moved key_pressed
    counter_key page_key quit_key search_key focus_list list_key focus_view option slider navigate show_view
    rebuild add_entries change_grouping filter unit_label branch build_calendar prayer_group readings_group
    prayer_opener event_opener open_in_section highlight show_passage on_passage update_star step bookmark
    copy_passage filed collection_of show_filing file_current move_passage name_problem create_collection
    rename_collection delete_collection collections_changed collections_dialog now start_ticking tick
    send_due_reminders send_reminder notification_said notification_open build_counter counter_verse_item
    show_counter leave_counter counter_show counter_announce counter_add counter_undo counter_reset
    counter_set_target counter_target_changed counter_apply_custom build_today today_content fast_card
    aqdas_opener fasted_marks mark_fasted prayer_card prayer_item obligatory_group open_obligatory
    guidance_opener long_window mark_long said_marks mark_said clear_records said_window show_said
    said_toggled refresh_today today_row daily_passage random_passage open_passage apply_theme
    compare_languages fill_compare compare_changed second_items show_second follow_scroll language_info
    update_status use_language details privacy about_dialog small_window shortcuts_dialog set_place
    place_summary location_dialog set_keep_running running_message request_background language_dialog
""".split()
# Modules below the views: data, text and settings. They must not need GTK, so they can be tested and reused without a display.
NO_GTK=("config","settings","ui","library","search","citations","labels","theme")

class Split(unittest.TestCase):
    def test_reader_still_has_every_name(self):
        self.assertEqual([n for n in TOP_LEVEL if not hasattr(reader,n)],[])
    def test_reader_still_has_every_method(self):
        self.assertEqual([m for m in METHODS if not hasattr(reader.Reader,m)],[])
    def test_no_method_is_hidden_inside_a_function(self):
        for path in PACKAGE.glob("*.py"):
            for node in ast.walk(ast.parse(path.read_text())):
                if isinstance(node,ast.FunctionDef):
                    inner=[b.name for b in node.body if isinstance(b,ast.FunctionDef) and b.args.args and b.args.args[0].arg=="self"]
                    self.assertEqual(inner,[],f"{path.name}: {node.name}")
    def test_one_reader_class_made_of_mixins(self):
        self.assertTrue(issubclass(reader.Reader,reader.Gtk.Application))
        self.assertEqual(len([c for c in reader.Reader.__mro__ if c.__name__.endswith("Mixin")]),11)  # 10 views + the libadwaita shell
    def test_data_modules_do_not_import_gtk(self):
        for name in NO_GTK:
            source=(PACKAGE/f"{name}.py").read_text()
            self.assertIsNone(re.search(r"from gi\.repository import .*\bGtk\b",source),name)
    def test_setting_a_path_on_reader_reaches_the_package(self):
        saved=reader.STATE
        try:
            reader.STATE=Path("/tmp/elsewhere/settings.json"); self.assertEqual(config.STATE,Path("/tmp/elsewhere/settings.json"))
        finally: reader.STATE=saved
        self.assertIs(config.STATE,saved)
    def test_patching_a_function_on_reader_reaches_its_callers(self):
        with patch.object(reader,"fetch_json",side_effect=OSError("offline")):
            self.assertIs(library.fetch_json,reader.fetch_json)
            with self.assertRaises(OSError): library.fetch_json("x")
        # Restored afterwards, too.
        self.assertIs(library.fetch_json,reader.fetch_json); self.assertEqual(library.fetch_json.__module__,"bahai_reader.library")
    def test_root_is_the_folder_with_the_data(self):
        self.assertEqual(config.ROOT,ROOT)
        self.assertTrue((config.ROOT/"data"/"prayers.json").exists())
    def test_settings_module_cleans_as_before(self):
        self.assertEqual(settings.clean_settings({"section":"gleanings"}),{"section":"writings"})

class Packaging(unittest.TestCase):
    """Every package format ships the bahai_reader package beside reader.py."""
    def test_nfpm(self):
        text=(ROOT/"packaging/nfpm.yaml").read_text()
        self.assertIn("- src: bahai_reader/*.py\n    dst: /usr/share/bahai-reader/bahai_reader/",text)
    def test_appimage(self):
        self.assertIn('cp bahai_reader/*.py "$ROOT/usr/share/bahai-reader/bahai_reader/"',(ROOT/"scripts/build-appimage.sh").read_text())
    def test_flatpak(self):
        text=(ROOT/"packaging/flatpak/org.bahai.Reader.yml").read_text()
        self.assertIn("install -Dm644 -t /app/share/bahai-reader/bahai_reader bahai_reader/*.py",text)
        self.assertIn("path: ../../bahai_reader\n        dest: bahai_reader",text)

if __name__=="__main__": unittest.main()
