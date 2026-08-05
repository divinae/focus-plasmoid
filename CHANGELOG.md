# Changelog

## Unreleased

Settings reorganised: the General page had grown to twenty-four controls across four unrelated
subjects, and is now Panel, Sessions and Break overlay. The four notification events are a
table rather than four near-identical cards, and the explanations are shorter.

Removed two settings whose feature is not in this release: the panel countdown layout and the
progress line under it were reverted, so their controls have gone with them. `make check` now
audits that the config keys, the settings pages and the applet agree, which is what caught it.

Fixed two startup hazards behind a reported plasmashell crash at login on Fedora 44 (#59):
the break overlay windows were built as soon as the applet loaded rather than when a break
began, and a restored session started its timer, its overlays and its notification from inside
the applet's own construction while the shell was still coming up. The overlays are now created
only for a break in progress, and the restore happens a moment after startup instead.

Fixed the applet failing to load where layer-shell-qt is not installed, reported on Kubuntu
25.10 (#58): the optional org.kde.layershell module is now detected at runtime instead of
imported outright, and without it the break overlay is an ordinary window that still covers
every screen but does not follow a virtual desktop switch.

Also: the panel countdown can be emboldened, and on a vertical panel it shows MM:SS with the
minutes accumulating instead of an hours field the column cannot hold - which used to be
clipped. And an arc drawn before its item had a size no longer logs hundreds of "Incorrect
argument radius" errors into the journal.

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
