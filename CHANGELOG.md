# Changelog

## 3.1.3 — 2026-08-19

**Fixes a crash that took the whole desktop down.** With any recorded sessions in the
history, plasmashell segfaulted in a restart loop shortly after login - the panel, the
desktop and every other widget with it - and the backtrace held no frame of this applet at
all:

```
QCoreApplication::notifyInternal2 (receiver=0x0)
Kirigami::Platform::PlatformTheme::setHighlightColor
PlasmaTheme::syncColors   (libplasma 6.7.4, plasmatheme.cpp:150)
```

The stats page read a theme colour for every chart bar, every timeline block and every task
row - 216 reads in the seconds after startup, 180 of them coming back unresolved as black -
and each read makes libplasma's Kirigami style resolve the Plasma palette. One of those
resolves pushed a colour into a theme object whose owner was already gone and sent the
change event to nothing. A plasmoid runs inside plasmashell with no sandbox of its own, so
that segfault was the whole session's, not just this widget's.

The applet now reads the theme once, keeps the four colours it needs, and hands them to the
views: no more per-delegate reads, and none at all while Plasma is still assembling the
popup. The stats page is also built when its tab is opened rather than while the popup is
being put together, and the panel icon's inner dial no longer works out a themed colour for
a track it never draws.

Anyone who hit this can undo the workaround: the history did not need clearing, and nothing
was lost.

### Also

- `make check` gained a theme audit, which fails the build if a colour read creeps back into
  a delegate. qmllint cannot see that mistake - it is valid QML - and it needs a running
  shell to bite, which is a poor way to find out.
- Noted for the future: the break overlay writes its palette on every break. Nothing
  suggests it misbehaves, but it is the same corner of Kirigami, so it is the first place to
  look if a crash ever points there.

## 3.1.2 — 2026-08-19

Two additions for flowmodoro, where a session has no end to run into, and three fixes for
time that was being lost.

**Flowmodoro can ask whether the flow is still going.** A flow counts up with no end, so it
outlives the work: walking away leaves it running and the hours are credited as focus. An
optional notification now asks, and carries the answers with it - "Take a break" ends the
flow and starts the break it earned, "Keep going" buys another full interval. Off by
default, with the switch and the interval on the Timer page under Flowmodoro. It makes no
sound: this is a question, not a deadline.

**End for today.** During a break the popup button and the tray action take that name, and
the fullscreen overlay has one too, offered by a switch in the Break overlay settings. It
ends the break and starts nothing after it, where Skip carries on into the next session.

### Fixed

- Stop discarded the session it ended. Flowmodoro has no pause, so Stop was the only way
  out of a flow besides Break, and a flow ended that way never reached the history at all.
  It files the stretch that ran, subject to the minimum-session setting; a break that did
  not run its length is still not recorded, and the stops that come from a config change
  stay silent.
- The panel indicator showed a full ring or wedge throughout a flow and a break overrun.
  Neither has a fraction to draw, so progress sat pinned at 1 and read as a session that
  had finished. It sweeps instead, the same signal the dial in the popup already used.
- Autostart never fired whenever anything at all was stored, which is most logins (#47). A
  stored session that was not running still counted as one picked up, so the autostart it
  was meant to defer to never ran.

## 3.1.1 — 2026-08-05

Two fixes for faults that shipped in 3.1.0.

- The panel icon was drawn over the plasmoid next to it on a vertical panel thicker than 48px
  (#60). It took its size from the panel's thickness while the applet had only asked for an
  icon's worth of height, so it grew past its own box - 8px over on a 56px panel, 52px on a
  100px one. It is bounded by its box in both dimensions now, and the compact view clips, so a
  sizing mistake can never draw over a neighbour again.
- The notification settings logged around a hundred "Binding loop detected for property
  implicitWidth" warnings per session: centring each tick under its column heading derived the
  padding from the control's width, which the padding itself feeds. It comes from the column
  width instead.

## 3.1.0 — 2026-08-05

**A session is no longer resumed across a reboot, a shutdown or a long suspend.** Until now the
countdown read the wall clock and nothing checked whether the machine had been running, so a
session came back after a reboot, and hours the machine spent asleep were charged to it - a
flowmodoro flow suspended from 09:00 to 18:00 returned nine hours long, and a countdown
suspended past its end filed a session nobody sat through. Now a stored session is discarded if
the machine has rebooted since, or if nothing was written for an hour, and a session the machine
slept through is ended rather than credited: the part that really ran is recorded and the timer
stops.

**Settings reorganised.** The General page had grown to twenty-four controls across four
unrelated subjects; it is now Panel, Sessions and Break overlay. The four notification events
are one table instead of four near-identical cards, and the explanations are shorter.

### Fixed

- The applet failed to load entirely where layer-shell-qt is not installed, reported on Kubuntu
  25.10 (#58). The optional `org.kde.layershell` module is detected at runtime now; without it
  the break overlay still covers every screen, it just does not follow a switch to another
  virtual desktop. The settings say so, and name the package, when it is missing.
- plasmashell could crash at login with a session already running, reported on Fedora 44 (#59).
  The overlay windows were built as soon as the applet loaded rather than when a break began,
  and a restored session started its timer, overlays and notification from inside the applet's
  own construction while the shell was still coming up.
- Starting a session in the first moment after login no longer has it replaced by the restored
  one, or started twice with the notification and script firing twice.
- An arc drawn before its item had a size no longer logs hundreds of "Incorrect argument
  radius" errors into the journal.
- The panel settings could grey out the only switch that decided whether the panel drew
  anything, leaving no way back from that page.
- The notification settings no longer show every sound file's tooltip at once.

### Removed

- The panel countdown layout and the progress line under it, which were reverted before 3.0.0
  and never released; their settings went with them. `make check` now audits that the config
  keys, the settings pages and the applet agree, which is what caught the leftovers.

## 3.0.0 — 2026-07-29

A major version because the applet grew parts it did not have. There is a tasks page with
renaming, reordering and per-task time, and a statistics page that draws today as a clock
and longer periods as bars of focus and break time against your working day. The break
overlay now covers every screen and every virtual desktop (#19), with blur, adjustable
opacity and its own light or dark palette. Running sessions survive a Plasma restart with
the downtime counted. Notifications and sounds split into four separate events with a
global volume, and a break that runs over keeps counting and can nag until you start the
next session.

Fixed along the way: the applet held the GPU awake (#45), flowmodoro flows were missing from
every total, long flows were thrown away on restart, and the countdown clipped on a vertical
panel. Also #17, #38 and #51.

## 2.4.0 — 2026-07-28

Tabbed popup with a task list and a statistics chart, recorded sessions with daily and
per-task totals, duration presets, panel context actions and three panel indicator styles.
Settings rebuilt as cards.

## 2.3.3 — 2026-02-19

Flowmodoro mode, an option to hide the icon when the countdown is visible, and a batch of
panel colour and layout fixes.

## Earlier

1.0.0 (2019) through 1.5.5 (2022) predate this file; see the git history.
