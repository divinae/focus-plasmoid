#!/usr/bin/env python3
"""Check that the applet reads a theme colour in exactly one place.

Every read of Kirigami.Theme's colours runs libplasma's Kirigami style through
PlasmaTheme::syncColors(). Done once, that is fine. Done per delegate - a colour per chart
bar, per timeline block, per task row - it was 676 reads in a few seconds at startup, and
one of them pushed a colour into a PlatformTheme whose target object was already gone:

    QCoreApplication::notifyInternal2 (receiver=0x0)
    Kirigami::Platform::PlatformTheme::setHighlightColor
    PlasmaTheme::syncColors  (libplasma 6.7.4, plasmatheme.cpp:150)

A plasmoid has no sandbox - it runs inside plasmashell - so that segfault took the whole
desktop down, in a loop, with no frame of this applet in the backtrace. The applet now
reads the theme once, in the palette block in main.qml, and hands the values to the views.

qmllint cannot check this: a colour read in a delegate is perfectly valid QML. So this
does, and it is why the check exists at all rather than as a note in a review.

Run from the repo root.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "package/contents/ui"

# The colour members of Kirigami.Theme. Fonts and Units are not colours and cost nothing.
COLOURS = (
    "textColor", "disabledTextColor", "highlightColor", "highlightedTextColor",
    "backgroundColor", "alternateBackgroundColor", "activeTextColor", "linkColor",
    "visitedLinkColor", "negativeTextColor", "neutralTextColor", "positiveTextColor",
    "hoverColor", "focusColor", "activeBackgroundColor", "linkBackgroundColor",
    "visitedLinkBackgroundColor", "negativeBackgroundColor", "neutralBackgroundColor",
    "positiveBackgroundColor", "hoverBackgroundColor", "focusBackgroundColor",
)

READ = re.compile(r"Kirigami\.Theme\.(" + "|".join(COLOURS) + r")\b")
# `Kirigami.Theme.textColor: value` sets the attached property - what BreakOverlayContent
# does to give the overlay its own palette - and is not a read. Anchored to the start of the
# line, because the colon of a ternary (`ready ? Kirigami.Theme.textColor : "transparent"`)
# would otherwise make every palette line look like a write.
WRITE = re.compile(r"^\s*Kirigami\.Theme\.(" + "|".join(COLOURS) + r")\s*:")
# A property default in a reusable component: at most one read per instance, and only when
# the caller leaves it alone. Allowed, but counted, so the number stays visible.
DECLARATION = re.compile(r"^\s*(readonly\s+)?property\s+color\s+\w+\s*:")
# The one place that may read: the palette block, which latches the read behind a flag.
PALETTE = "paletteReady ?"


def main():
    # Settings pages are ordinary Plasma config pages, built only when the dialog opens.
    files = [p for p in sorted(UI.glob("*.qml")) if not p.name.startswith("config")]
    files += sorted(UI.glob("lib/*.qml"))

    offenders = []
    palette_reads = 0
    declarations = []

    for path in files:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not READ.search(line) or WRITE.match(line):
                continue
            where = f"{path.relative_to(ROOT)}:{number}"
            if PALETTE in line:
                palette_reads += 1
            elif DECLARATION.match(line):
                declarations.append((where, line.strip()))
            else:
                offenders.append((where, line.strip()))

    for where, text in declarations:
        print(f"theme audit: default, evaluated only when a caller does not override: {where}: {text}")

    if offenders:
        print("theme audit FAILED: a theme colour is read outside the palette block.")
        print("Take the colour as a property from the caller instead - see the palette")
        print("note in main.qml, and this script's docstring for what it costs.")
        for where, text in offenders:
            print(f"  {where}: {text}")
        return 1

    if not palette_reads:
        print("theme audit FAILED: no palette reads found at all.")
        print("The palette block in main.qml is how colours reach the applet; if it moved,")
        print("update this check with it.")
        return 1

    print(f"theme audit: {palette_reads} palette reads, "
          f"{len(declarations)} component defaults, no per-delegate reads")
    return 0


if __name__ == "__main__":
    sys.exit(main())
