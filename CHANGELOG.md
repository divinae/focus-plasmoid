# Changelog

Written for people using the applet, so entries describe what changed on screen rather than
which commit did it. Issue numbers refer to
[gitlab.com/divinae/focus-plasmoid](https://gitlab.com/divinae/focus-plasmoid/-/issues).

## 3.0.0 — 2026-07-29

A major version because the applet grew parts it did not have: a tasks page, a statistics
page, a break overlay that covers every screen, and sessions that survive a Plasma restart.

### Added

- **Break overlay on every screen and every virtual desktop** (#19). It is a layer-shell
  surface, so switching desktop no longer leaves it behind on the one it started on. Blur
  can be turned off, background opacity is adjustable from 0 to 100%, and the overlay can
  keep its own light or dark palette regardless of the desktop colour scheme.
- **Statistics page.** Today is drawn as a clock — each session at the hour it happened,
  focus in the task's colour, breaks dimmed, gaps left as gaps. Longer periods are bars of
  time with focus and break stacked, against a dashed line at your working day. Beneath
  them: focus, breaks and idle time, how much of the working day the timer accounted for,
  and the split by task. Period selectable: today, 7, 14 or 30 days.
- **Tasks can be renamed** in place, and **deleting a task archives it** instead, so the
  sessions recorded against its name keep that name. Archived tasks are reachable behind a
  toggle and can be restored.
- **Switching task mid-session records the stretch already worked**, rather than
  re-attributing the whole session to whichever task was selected when it ended.
- **Sessions survive a Plasma restart** — updates, crashes, `systemctl --user restart
  plasma-plasmashell`. What is stored is the deadline rather than the time left, so the
  seconds Plasma was down are counted, exactly as a suspend already was. Flowmodoro flows
  included, however long they have been running.
- **Notifications and sounds split into four events** — focus start, focus end, break start,
  break end — each with its own notification toggle, sound toggle and sound file, plus one
  global volume. The popup and the sound are independent: either, both or neither.
- **A break running past its end** keeps counting into the negative so the overrun stays
  visible, announces itself on the overlay, and can repeat its sound at an interval until
  the next session is started.
- **Focus mode**: a button that strips the popup back to the dial alone — no tabs, no task
  picker, no buttons.
- **Panel**: an option to swap the icon for the countdown while a session runs (#51), an
  option to hide the countdown inside the dial (#38), a flash when a session ends (#17), a
  play or pause glyph in the ring and wedge styles when idle, and bold digits.
- **Statistics settings**: a minimum session length, below which focus stretches are not
  recorded, and a working-day length used to account the day.

### Changed

- The flowmodoro break divisor now defaults to a fifth of the flow rather than a third.
- The flowmodoro buttons are named after what they do: the primary reads **Break**, since it
  ends the flow and begins the break, and the other reads **Stop** in both modes.
- Task colours are pastel and drawn from a band around the desktop's highlight colour, so
  the chart stays in the theme's family.
- The stats period defaults to today.
- On a panel the countdown shows `MM:SS` with minutes accumulating (`65:00`, `125:00`)
  instead of an hours field that a narrow column cannot hold.
- Durations on the statistics page read as lengths (`13h50`, `25m`) rather than clock times.

### Fixed

- **The applet held the GPU awake** by constructing a `MediaPlayer` eagerly, which kept the
  nvidia driver from idling (#45). It is now created on first use.
- **Flowmodoro flows were missing from every total**, chart and per-task breakdown: they are
  recorded as a different kind and only "focus" was counted. An afternoon of flows reported
  "nothing finished today".
- **Long flows were discarded on restart.** A flow is judged stale by when its state was
  written, not by when it started, so a two-hour flow is no longer treated as expired.
- **The countdown clipped on a vertical panel** once a session passed an hour, and the
  applet's height could grow with its own text.
- The ticking sound never played at all: setting a volume threw before reaching `play()`.
- The progress ring did not repaint when its colour changed, so the focus/break colour swap
  left the old pixels up.
- A session with nothing to count toward — a flow, or a break past its end — now shows an
  indeterminate sweep instead of a full or empty ring that read as finished.
- The panel's context menu said **Reset** where the button it drives said **Stop**.
- The dial caption vanished when the countdown was shown, and was neither centred nor
  enlarged when it was hidden.
- The panel footprint no longer shifts when the icon is swapped for the countdown.
- The break overlay's forced dark palette used a guessed grey that left the ring and caption
  muddy; Breeze's own values are used now.
- The archive toggle referenced an icon that does not exist in Breeze, so it rendered blank.

## 2.4.0 — 2026-07-28

### Added

- Tabbed popup with a task list and a statistics chart.
- Finished sessions are recorded, with the day's total in the popup and focus time
  aggregated per task.
- Duration presets, in the settings and in the panel's context menu.
- Panel context actions, a state-aware tooltip, and mode switching from the panel.
- Three panel indicator styles, two of them thinner than the original tomato frame.
- A button on the end-of-session notification.

### Changed

- Settings rebuilt as cards, with the two timer modes separated so only the options that
  apply to the selected mode are shown.
- The progress arc has rounded caps and a subtle track behind it.

### Fixed

- The timer font setting no longer builds a font model inside plasmashell.
- The ring and wedge outlines are a genuine hairline, and the wedge is drawn evenly.

## 2.3.3 — 2026-02-19

### Added

- Flowmodoro mode.
- An option to hide the icon when the countdown is visible.

### Fixed

- Visibility and colours in the panel, using Kirigami colours throughout.
- Several layout problems in the compact representation.

## Earlier

1.0.0 (2019) through 1.5.5 (2022) predate this file; see the git history.
