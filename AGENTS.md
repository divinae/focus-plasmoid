# Fokus: notes for AI agents

Fokus is a pomodoro / flowmodoro timer plasmoid for KDE Plasma 6 (Wayland only; X11 is
documented as unsupported), with a task list, day statistics, a full-screen break overlay,
per-event notifications/sounds/scripts and session persistence across plasmashell restarts.
Plugin Id `com.dv.fokus` (`package/metadata.json`), author Jakub Lipiński (GitHub `divinae`).
Code lives at https://github.com/divinae/focus-plasmoid (the old GitLab project is archived);
published on the KDE Store at https://store.kde.org/p/2117117/ (the Plasma 5 version is a
separate store page, 1308861). Push target: `origin` (`git@github.com:divinae/focus-plasmoid.git`),
branch `master`, committed directly (no feature branches). Pure QML/JS, no compiled parts.

## Layout

- `package/metadata.json`: KPlugin metadata; `Version` is the single source of the version.
- `package/contents/config/main.xml`: kcfg schema (group `General`, ~65 entries).
  `config.qml`: the settings pages (`configTimer`, `configSessions`, `configPanel`,
  `configBreakOverlay`, `configNotifications`, `configScripts` in `contents/ui/`).
- `package/contents/ui/main.qml`: the `PlasmoidItem`, ~1740 lines: state machine,
  persistence, palette, overlays, notifications, MPRIS pause, DND inhibitor, startup.
- `package/contents/ui/lib/`: plain JS that is unit-tested without Plasma: `timer.js`
  (states, formatting, session staleness), `tasks.js`, `Utils.js`, plus `ExecUtil.qml`
  (runs shell commands via a `Plasma5Support.DataSource` "executable" engine).
- Views: `TimerFace`, `TaskListView`, `StatsView`, `DayTimeline`, `ProgressCircle`,
  `IndicatorIcon` (panel icon), `NotificationManager`, `Sfx`.
- Break overlay: `BreakOverlay*.qml`. `*Layer*` variants use `org.kde.layershell`
  (optional); `*Plain*` variants do not. `LayerShellProbe.qml` detects the module.
- `package/contents/icons/`: tomato SVGs. `screenshots/`: README images.
- `tests/`: `tst_*.qml` (qmltestrunner over `lib/` JS), `config_audit.py`, `theme_audit.py`.
- `Messages.sh`: i18n extraction. `Makefile`: all dev commands.
- Untracked, not yours to touch: `docs/kde-store.md` (store page text), `fokus_v*.plasmoid`
  release archives in the root (gitignored, kept as history).

## Build, run, test

All via `make` (read the `Makefile`; README's command table is slightly out of date):

- `make check` = `lint` + `audit` + `test` (README says lint + test; `audit` was added later).
- `make lint`: `/usr/lib/qt6/bin/qmllint --unqualified disable --missing-property disable`
  over `ui/*.qml` and `ui/lib/*.qml` (those two categories are noise from
  `plasmoid.configuration`). Override the binary with `QMLLINT=...`.
- `make test`: `QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests`.
- `make audit`: `python3 tests/config_audit.py` (config keys vs `cfg_` aliases vs applet
  reads) and `python3 tests/theme_audit.py` (theme colours read in exactly one place). Run
  from the repo root.
- `make install` / `make upgrade` / `make uninstall`: `kpackagetool6 -t Plasma/Applet`.
- `make package`: zips `package/` to `fokus_v<Version>.plasmoid`; `make clean` removes them.

See a change live (only if the user asks; these touch the session):
`make upgrade && systemctl --user restart plasma-plasmashell`. Isolated try-out without
touching the installed copy:
`XDG_DATA_HOME=/tmp/fokus-test make install` then
`XDG_DATA_HOME=/tmp/fokus-test plasmawindowed com.dv.fokus`. `plasmawindowed` logs QML
errors to the journal: `journalctl --user --since "1 min ago" | grep -i qml`.

## Conventions

- QML: 4-space indent, semicolons in JS, `id` first, `import ... as Kirigami/PlasmaComponents/
  QQC2`. Logic that can be tested goes into `ui/lib/*.js` with a matching `tests/tst_*.qml`.
  Comments are long, explanatory prose about *why* (crash history, issue numbers); keep that
  style and keep existing comments.
- Config: every new setting needs a `main.xml` entry, a `cfg_<key>` on a config page, and
  must pass `make audit`. Internal state keys (`session_state`, `session_history`,
  `task_list`, `task_label`) are written by the applet, not exposed in settings.
- i18n: strings via `i18n()` / `i18nc()` / `i18np()`; `Messages.sh` extracts to
  `plasma_applet_com.dv.fokus.pot` (domain must stay `plasma_applet_<plugin id>`). No `po/`
  is shipped in the repo (`po/` and `*.mo` are gitignored).
- No SPDX headers in source files; license is GPL-3.0 (`LICENSE`).
- `main.qml` starts with a UTF-8 BOM; leave it as is.
- Versioning: semver in `metadata.json`. A release is one commit titled `Fokus X.Y.Z` that
  touches only `CHANGELOG.md` and `metadata.json`, tagged `vX.Y.Z`. CHANGELOG entries:
  `## X.Y.Z — YYYY-MM-DD`, a few prose paragraphs with bold leads and `(#NN)` issue refs,
  then `### Fixed` / `### Also` / `### Removed` bullets.
- Commit subjects: lowercase prefixes `fix:`, `feat:`, `refine:`, `refactor:`, `docs:`,
  `tests:` followed by a plain-English sentence ("fix: let "today" turn over at midnight
  (#67)"); bodies explain the why at length; `Co-Authored-By:` trailer when AI-assisted.

## Gotchas

- A plasmoid runs inside plasmashell with no sandbox: a bad QML path crashes the whole
  desktop. Read the history (3.1.2/3.1.3, #58, #59) before touching startup or theming.
- Theme colours (`Kirigami.Theme.*Color`) are read once, deferred, in the palette block in
  `main.qml` (`paletteReady`, `theme*Color`) and passed down. Per-delegate reads segfaulted
  plasmashell (libplasma `PlasmaTheme::syncColors`). `theme_audit.py` enforces this.
- Startup restore is deferred by a 600 ms `Timer` (`startupRestore`), not done in
  `Component.onCompleted`, to stay off plasmashell's startup path (#59).
- Layer-shell overlays are loaded only by URL through `Loader`s, never referenced by type
  name: naming them makes the file fail to load where `org.kde.layershell` is missing (#58).
  Do not add `active:` to those Loaders (forces the probe onto startup).
- Countdown state: `counterMilliseconds` is the only stored value; everything else is
  derived. Persisted state stores the deadline plus a boot id
  (`/proc/sys/kernel/random/boot_id`) to tell a Plasma restart from a reboot.
- Binding a ComboBox `currentIndex` to a value it writes caused recursion/segfaults; set it
  once in `Component.onCompleted` (see StatsView).
- Media pause uses the private Plasma MPRIS module (no stable API) and skips KDE Connect.

## Related

- Glance (`../glance-plasmoid`, `divinae/glance-plasmoid`) contains a copy
  of Fokus in `package/contents/ui/focus/` (imported 2026-11-03, Glance commit `b53b43a`):
  `lib/timer.js`, `lib/tasks.js`, the views and the break overlay, with `main.qml` split into
  `FocusController.qml` + `FocusView.qml` and settings renamed to Glance's `focus_*` keys.
  There is no sync mechanism; the copies have diverged (e.g. Glance's `timer.js` has
  `savedThisBoot`, its `StatsView` uses Glance's `PillButton`/`DrawerMenu`). This repo is the
  source of truth for the standalone widget only; a fix here does not reach Glance (or vice
  versa) unless ported by hand. Glance does not import Fokus's settings or history.
- Shift (`../shift-plasmoid`) is the sibling sit/stand widget, also copied
  into Glance (`ui/stand/`).
