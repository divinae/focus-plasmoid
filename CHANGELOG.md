# Changelog

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
