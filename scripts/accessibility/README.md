# Accessibility pass: AT-SPI audit and Orca

What a screen reader gets from the libadwaita window, checked in a throwaway container (no change to the host):

```sh
docker build -t bahai-a11y scripts/accessibility
mkdir -p /tmp/a11y-out
# AT-SPI audit only: every control on 15 screens must have a role and a name
docker run --rm -v "$PWD:/repo:ro" -v "$PWD/scripts/accessibility:/a:ro" -v /tmp/a11y-out:/out bahai-a11y /a/run.sh
# The same with Orca running; what it speaks is in /tmp/a11y-out/orca-debug.log ("SPEECH DISPATCHER: Speaking")
docker run --rm -e ORCA=1 -v "$PWD:/repo:ro" -v "$PWD/scripts/accessibility:/a:ro" -v /tmp/a11y-out:/out bahai-a11y /a/run.sh
```

- `app.py` walks the app through Home, a library card, the library, a book, its contents, the text, Save, Prayers,
  Obligatory prayers, the counter, Today, Ctrl+K search and a result, the ⋮ menu and Highlights & notes, moving keyboard
  focus as a user would (programmatically; no real key presses).
- `audit.py` reads the app through AT-SPI (pyatspi) at each step and reports controls without a name and what has focus.
- `SHELL_KIND=classic` runs the classic window instead (some steps are libadwaita-only and are skipped with a message).

This is not a substitute for a screen-reader user trying the app; see STATUS.md for what was and was not checked.
