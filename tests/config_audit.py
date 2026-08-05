#!/usr/bin/env python3
"""Check that the config keys, the settings pages and the applet agree.

qmllint cannot see any of this: plasmoid.configuration is an attached property it does not
resolve, and a cfg_ alias for a key that does not exist is valid QML. So these mistakes are
invisible until someone opens the settings and finds a switch that does nothing.

Every one of these checks exists because the mistake it catches was actually shipped:

  * a settings page wrote to panel_countdown_layout and panel_progress_line, keys that were
    never declared - so the values had no default and did not survive a restart
  * those same two controls later described features whose implementation had been reverted,
    leaving dead switches in the settings
  * the preset selector read a key through a JS file it had not imported, and silently fell
    back to the first entry

Run from the repo root.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MAIN_XML = ROOT / "package/contents/config/main.xml"
UI = ROOT / "package/contents/ui"

# Keys the applet manages itself rather than exposing: state it writes and reads back.
INTERNAL = {"session_state", "session_history", "task_list", "task_label"}


def read(path):
    return path.read_text(encoding="utf-8")


def main():
    keys = set(re.findall(r'<entry name="([A-Za-z_0-9]+)"', read(MAIN_XML)))

    config_pages = sorted(UI.glob("config*.qml"))
    applet_qml = [p for p in sorted(UI.glob("*.qml")) if p not in config_pages]

    # cfg_<key> aliases: what the settings pages write.
    exposed = {}
    for page in config_pages:
        for name in re.findall(r"cfg_([A-Za-z_0-9]+)", read(page)):
            if name.endswith("Default"):
                continue
            exposed.setdefault(name, set()).add(page.name)

    # plasmoid.configuration.<key>: what the applet actually reads. Deliberately NOT the
    # config pages: a settings page reading a key back - configBreakOverlay reads
    # flowmodoro_mode_enabled to hide Postpone - would otherwise count as "the applet uses
    # this", and a control that nothing outside the settings acts on would pass as live.
    used = {}
    for qml in applet_qml + list(UI.glob("lib/*.qml")):
        for name in re.findall(r"configuration\.([A-Za-z_0-9]+)", read(qml)):
            used.setdefault(name, set()).add(qml.name)

    failures = []

    orphan_aliases = sorted(set(exposed) - keys)
    if orphan_aliases:
        failures.append(
            "settings write keys that main.xml does not declare, so they have no default "
            "and do not persist:\n    "
            + "\n    ".join(f"{k}  ({', '.join(sorted(exposed[k]))})" for k in orphan_aliases)
        )

    unknown_reads = sorted(set(used) - keys)
    if unknown_reads:
        failures.append(
            "the applet reads keys that main.xml does not declare - a typo reads as undefined:"
            "\n    " + "\n    ".join(f"{k}  ({', '.join(sorted(used[k]))})" for k in unknown_reads)
        )

    dead_switches = sorted(set(exposed) - set(used))
    if dead_switches:
        failures.append(
            "settings expose keys nothing reads - a control that decides nothing:\n    "
            + "\n    ".join(f"{k}  ({', '.join(sorted(exposed[k]))})" for k in dead_switches)
        )

    unreachable = sorted(keys - set(exposed) - INTERNAL)
    if unreachable:
        failures.append(
            "keys with no control on any settings page, and not listed as internal:\n    "
            + "\n    ".join(unreachable)
        )

    duplicated = sorted(k for k, pages in exposed.items() if len(pages) > 1)
    if duplicated:
        failures.append(
            "the same key is offered on two pages, which will fight over the value:\n    "
            + "\n    ".join(f"{k}  ({', '.join(sorted(exposed[k]))})" for k in duplicated)
        )

    if failures:
        print("config audit FAILED\n")
        for f in failures:
            print("  * " + f + "\n")
        return 1

    print(
        f"config audit: {len(keys)} keys, {len(exposed)} exposed in settings, "
        f"{len(INTERNAL)} internal, all read by the applet"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
