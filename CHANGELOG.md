# Changelog

## Unreleased

Fixed the applet failing to load where layer-shell-qt is not installed, reported on Kubuntu
25.10 (#58): the optional org.kde.layershell module is now detected at runtime instead of
imported outright, and without it the break overlay is an ordinary window that still covers
every screen but does not follow a virtual desktop switch.

Also: the panel countdown can be laid out as MM:SS, minutes over seconds, or minutes alone,
with an option to embolden it and a progress line beneath it; and the vertical panel countdown
is sized from the column the panel actually grants rather than a fraction of the icon.

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
