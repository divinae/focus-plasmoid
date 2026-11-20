# KDE Store listing

Text for the [store page](https://store.kde.org/p/2117117/), ready to paste. Update the version and
the changelog with each release.

## Links to change on the page

The project moved from GitLab to GitHub. Replace any `gitlab.com/divinae/focus-plasmoid` link:

- **Source / homepage:** https://github.com/divinae/focus-plasmoid
- **Bugs and ideas:** https://github.com/divinae/focus-plasmoid/issues
- The Plasma 5 page (https://store.kde.org/p/1308861/) links the old GitLab project too: point it at
  the same GitHub repository, and say that page is the old Plasma 5 version.

## Fields

**Title**

    Fokus

**Category**

    Plasma 6 Extensions > Plasma 6 Widgets

**Version**

    3.2.0

**License**

    GPL-3.0

**Tags**

    pomodoro, flowmodoro, timer, focus, productivity, tasks, break, plasma6

**Donation link**

    https://ko-fi.com/divinae4535

**Summary (one line)**

    Work in focused stretches, rest when you've earned it: a pomodoro and flowmodoro timer with tasks, statistics and a break overlay.

**Description** (each line its own paragraph)

```
Work in focused stretches, rest when you've earned it. A pomodoro and flowmodoro timer for KDE Plasma 6, with a task list, statistics of your day, and a break overlay that makes you actually take the break.

Two ways to work: classic pomodoro (25/5/20, 50/10/30, 90/20/30 or your own) or flowmodoro, where you work as long as the flow lasts and the break is earned from it.

Breaks you take: an overlay on every screen, across virtual desktops, optionally blurred, with Postpone, Skip and Start. A break that runs over keeps counting.

Tasks and where the time went: a todo list in the popup, each session counted for the task you pick, and today drawn as a clock with the split by task.

Your sounds, your scripts: four events (focus and break, start and end), each with its own notification and sound, a ticking warning, and scripts to run at each.

Nothing lost: a running session comes back after a Plasma restart, the downtime subtracted.

Quiet in the panel: a tomato, a thin ring or a filled wedge, with or without the countdown.

Made for a Wayland session. Optional: LayerShellQt, so the break overlay follows a switch to another virtual desktop.

Source, issues and the full README: https://github.com/divinae/focus-plasmoid

Support: https://ko-fi.com/divinae4535
```

**Changelog**

```
3.2.0
Pause media when a break begins (an option, off by default).
The scroll wheel can leave the time alone (an option on the Timer page).
Fixes: a task list that could lock itself up, a stats page stuck on yesterday, an overlay that missed a monitor.
```

**Screenshots:** `screenshots/timer.png`, `stats.png`, `tasks.png`, `break_overlay.png`.
