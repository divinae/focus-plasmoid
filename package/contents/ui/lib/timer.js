.pragma library

// Pure session-state logic, with no dependency on the plasmoid, its
// configuration or its UI, so it can be exercised by tests/tst_timer.qml.
//
// States are 1-based: odd values are focus sessions, even values are breaks,
// and the last even value (2 * sessions) is the long break.

function isBreak(stateVal) {
    return stateVal % 2 === 0;
}

function isLongBreak(stateVal, sessions) {
    return stateVal === 2 * sessions;
}

// Which kind of session stateVal denotes. Callers map the key to a duration and
// a translated caption, which keeps both out of this file.
function sessionKind(stateVal, sessions, flowmodoro) {
    if (flowmodoro)
        return isBreak(stateVal) ? "flowBreak" : "flow";
    if (isLongBreak(stateVal, sessions))
        return "longBreak";
    if (isBreak(stateVal))
        return "shortBreak";
    return "focus";
}

// Advance one state, wrapping after the long break. Breaks the user has set to
// zero minutes are skipped rather than run for no time. Flowmodoro derives its
// break length from the flow instead, so the two settings do not apply there.
//
// opts: { flowmodoro, skipShortBreak, skipLongBreak }
function nextState(stateVal, sessions, opts) {
    opts = opts || {};
    var next = stateVal < sessions * 2 ? stateVal + 1 : 1;
    if (opts.flowmodoro)
        return next;
    // The long break is an even state too, so it has to be matched first or the
    // short-break rule would swallow it.
    if (isLongBreak(next, sessions)) {
        if (opts.skipLongBreak)
            return nextState(next, sessions, opts);
    } else if (isBreak(next) && opts.skipShortBreak) {
        return nextState(next, sessions, opts);
    }
    return next;
}

function prevState(stateVal) {
    return stateVal > 1 ? stateVal - 1 : stateVal;
}

// Which focus session of the cycle this state belongs to, counting from 1. A
// break belongs to the session it follows, so state 2 is still session 1.
function sessionNumber(stateVal) {
    return Math.floor((stateVal + 1) / 2);
}

// A tick that arrives this much later than the last one did not measure working time: the
// machine was suspended, or frozen hard enough that nothing was happening either. The
// countdown reads the wall clock, so without this the whole gap is charged to the session -
// a flow suspended from 09:00 to 18:00 came back nine hours long, and a countdown suspended
// past its end fired end() and filed a session nobody sat through.
//
// Five minutes is well past any scheduling stall and well short of a break worth crediting.
var SESSION_GAP_LIMIT_MS = 5 * 60 * 1000;

function isTimeGap(timeDiffMs) {
    return timeDiffMs > SESSION_GAP_LIMIT_MS;
}

// How far into the current session we are, in seconds. A flowmodoro flow counts up,
// so its counter IS the elapsed time; everything else counts down from its length.
// Can exceed initialSeconds during a break overrun, which is correct - the break did
// run that long.
function elapsedSeconds(initialSeconds, counterSeconds, countingUp) {
    if (countingUp)
        return Math.max(0, counterSeconds);
    return Math.max(0, initialSeconds - counterSeconds);
}

// The stretch that ran under one task: everything since the session started or since
// the last task switch, whichever is later.
function segmentSeconds(elapsed, segmentStart) {
    return Math.max(0, elapsed - (segmentStart || 0));
}

// --- surviving a restart ----------------------------------------------------
//
// plasmashell being restarted destroys the applet, so a running session has to be
// written down to come back. Stored as JSON in a config key, like the history and
// the task list, because an applet cannot write files.
//
// What is stored differs by state, because "time left" is not one quantity:
//   running  -> the deadline, so the seconds Plasma was down are counted. The
//               countdown already derives from the wall clock, which is why
//               suspending the machine works; this extends the same property.
//   paused   -> the milliseconds left, since there is no deadline to count toward.
//   flow     -> when it started, since a flowmodoro flow counts up.

// A restart is worth resuming across; a reboot is not, because the countdown derives
// from the wall clock and would count every minute the machine was off as time spent
// focusing. The two are told apart by the kernel boot id stored with the session: the
// same id means this is the same boot, so plasmashell alone went away. That costs
// nothing to keep current - it rides along on the saves each transition makes anyway -
// where measuring the gap instead would mean writing the state every few seconds.

// How old a state may be even on the same boot. Bounds a plasmashell that was gone for
// a long time without the machine ever going down, where resuming still swallows the
// gap. See sessionIsStale() for what "old" is measured from in each state.
var SESSION_STALE_AFTER_MS = 60 * 60 * 1000;

function serializeSession(state) {
    return JSON.stringify({
        "stateVal": state.stateVal,
        "initialSeconds": state.initialSeconds,
        "running": state.running === true,
        "breakOvertime": state.breakOvertime === true,
        "countingUp": state.countingUp === true,
        // Exactly one of these is meaningful, per the note above.
        "deadline": Math.round(state.deadline || 0),
        "remainingMs": Math.round(state.remainingMs || 0),
        "startedAt": Math.round(state.startedAt || 0),
        // Where the current task's stretch began, so a switch mid-session is not
        // recounted from zero after a restart.
        "taskSegmentStart": Math.round(state.taskSegmentStart || 0),
        "savedAt": Math.round(state.savedAt || 0),
        // Which boot wrote this. Empty when the id could not be read, which only costs
        // the reboot test, not the session.
        "bootId": state.bootId || ""
    });
}

function parseSession(json) {
    if (!json)
        return null;
    try {
        var parsed = JSON.parse(json);
        // A hand-edited or half-written value must not resurrect a broken session.
        if (!parsed || typeof parsed.stateVal !== "number" || typeof parsed.initialSeconds !== "number")
            return null;
        return parsed;
    } catch (e) {
        return null;
    }
}

// Whether a stored state is too old to resume, given the boot the machine is on now.
//
// Two tests only:
//
//   1. A different boot id: the machine went down in between, so the session is discarded
//      however fresh it looks. This is what stops a reboot, or a night switched off, from
//      coming back mid-session.
//   2. How long ago the state was written. The keepalive in main.qml rewrites it every minute
//      while anything is running, so a gap in those writes is the applet not having been
//      there - plasmashell gone, or the machine asleep - and that is exactly what must not be
//      resumed as though it had been counting.
//
// Deliberately no exemptions. Two have been tried and both let time be invented:
//
//   * exempting a counting-up flow, because suspending does not change the boot id, so a flow
//     started at 09:00 and resumed at 18:00 came back nine hours long;
//   * exempting a countdown whose deadline is still ahead, which resumed across a reboot
//     whenever the boot id could not be read - and, even on one boot, turned plasmashell
//     being gone for 85 minutes of a 90 minute session into a full session in the history.
//
// The age test needs no exemption now that the keepalive keeps savedAt honest for every
// running state, not only for flows.
function sessionIsStale(session, nowMs, bootId) {
    if (!session || !session.savedAt)
        return true;
    if (session.bootId && bootId && session.bootId !== bootId)
        return true;
    return nowMs - session.savedAt > SESSION_STALE_AFTER_MS;
}

// The counter value to restore, in milliseconds. Negative is legitimate: a break
// that ran over while Plasma was down comes back still overrunning.
function restoredCounterMs(session, nowMs) {
    if (!session)
        return 0;
    if (!session.running)
        return session.remainingMs;
    if (session.countingUp)
        return Math.max(0, nowMs - session.startedAt);
    return session.deadline - nowMs;
}

// How often to repeat the break-end sound during an overrun, in milliseconds. A
// floor keeps a hand-edited config from turning the reminder into a machine gun,
// and a missing or zero value falls back to a minute rather than firing at once.
function overrunReminderMs(seconds) {
    if (!seconds || seconds <= 0)
        return 60 * 1000;
    return Math.max(10, seconds) * 1000;
}

// How often to ask whether a flow is still running, in milliseconds. Same shape as
// overrunReminderMs: a floor so a hand-edited config cannot turn the nudge into a
// machine gun, and a missing or zero value falls back rather than firing at once.
function flowReminderMs(minutes) {
    if (!minutes || minutes <= 0)
        return 30 * 60 * 1000;
    return Math.max(1, minutes) * 60 * 1000;
}

// Whether a finished stretch is worth recording. Short focus sessions are noise -
// a couple of minutes before switching task or skipping is not a session anyone
// wants counted - so they are dropped below the configured floor. Breaks are never
// filtered: a five minute break is a normal break, not noise.
function countsAsSession(kind, actualSeconds, minimumSeconds) {
    if (!isFocusKind(kind))
        return true;
    return actualSeconds >= (minimumSeconds || 0);
}

// --- session history -------------------------------------------------------
//
// An applet cannot write files - QML has no FileIO here - so finished sessions
// are kept as JSON in a config key. Everything below is pure so it can be
// tested: the caller reads and writes the key.

// How many days of history to keep. Older entries are dropped on write, so the
// config value cannot grow without bound.
var HISTORY_DAYS = 30;

function parseHistory(json) {
    if (!json)
        return [];
    try {
        var parsed = JSON.parse(json);
        return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
        // A corrupt value must not take the applet down; start over instead.
        return [];
    }
}

// The inverse of dayKey(), as a LOCAL date. new Date("2026-07-29") parses as UTC
// midnight, which lands on the previous day west of Greenwich and would label a bar with
// the wrong weekday - the same trap dayKey() avoids by not using toISOString().
function dateFromDayKey(day) {
    var parts = ("" + day).split("-");
    return new Date(parseInt(parts[0], 10), parseInt(parts[1], 10) - 1, parseInt(parts[2], 10));
}

// Local calendar day as YYYY-MM-DD. Deliberately not toISOString(), which is UTC
// and would file a late-evening session under the next day.
function dayKey(date) {
    var month = date.getMonth() + 1;
    var day = date.getDate();
    return date.getFullYear() + "-" + padNumber(month, 2) + "-" + padNumber(day, 2);
}

// kind is a sessionKind() key. plannedSeconds is what the session was set to run
// for, actualSeconds what it really took - they differ when a break overran or
// the counter was scrolled.
function makeEntry(kind, plannedSeconds, actualSeconds, date, task) {
    return {
        "kind": kind,
        "day": dayKey(date),
        "at": date.getTime(),
        "planned": Math.max(0, Math.round(plannedSeconds)),
        "actual": Math.max(0, Math.round(actualSeconds)),
        "task": task || ""
    };
}

function pruneHistory(entries, now) {
    var cutoff = now.getTime() - HISTORY_DAYS * 24 * 60 * 60 * 1000;
    var kept = [];
    for (var i = 0; i < entries.length; i++) {
        if (typeof entries[i].at === "number" && entries[i].at >= cutoff)
            kept.push(entries[i]);
    }
    return kept;
}

function appendHistory(json, entry, now) {
    var entries = pruneHistory(parseHistory(json), now);
    entries.push(entry);
    return JSON.stringify(entries);
}

// Which history kinds count as focus. A flowmodoro flow is focus - it is the whole
// working half of that mode - so leaving it out meant a flowmodoro user recorded
// sessions and then saw zeroes in every total, tooltip and chart.
function isFocusKind(kind) {
    return kind === "focus" || kind === "flow";
}

// Rewrites recorded sessions to follow a task rename. History names its task by
// title, so without this a rename would leave every past session under the old name
// and the stats page would show one task's work split in two.
//
// Renaming onto a title already in use merges the two, which is accepted: it is
// sometimes what the user means, and a popup has nowhere good to report a refusal.
function renameTaskInHistory(json, oldTitle, newTitle) {
    if (!oldTitle || oldTitle === newTitle)
        return json || "[]";
    var entries = parseHistory(json);
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].task === oldTitle)
            entries[i].task = newTitle;
    }
    return JSON.stringify(entries);
}

// Focus sessions finished on the given day. Breaks are recorded too, but the
// count people care about is focus.
function countFocusOn(entries, day) {
    var total = 0;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].day === day && isFocusKind(entries[i].kind))
            total++;
    }
    return total;
}

// Seconds actually spent focusing on the given day.
function focusSecondsOn(entries, day) {
    var total = 0;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].day === day && isFocusKind(entries[i].kind))
            total += entries[i].actual;
    }
    return total;
}

// The other half of the recorded day. Kept explicit rather than "not focus", so a kind
// added later is not silently counted as a break.
function isBreakKind(kind) {
    return kind === "shortBreak" || kind === "longBreak" || kind === "flowBreak";
}

// Seconds spent on breaks that day, mirroring focusSecondsOn().
function breakSecondsOn(entries, day) {
    var total = 0;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].day === day && isBreakKind(entries[i].kind))
            total += entries[i].actual;
    }
    return total;
}

// Merges [start, end] pairs, so overlapping or touching intervals count once. Sorting
// first is what makes a single pass enough.
function mergeIntervals(intervals) {
    if (!intervals.length)
        return [];
    var sorted = intervals.slice().sort(function(a, b) {
        return a.start - b.start;
    });
    var merged = [{ "start": sorted[0].start, "end": sorted[0].end }];
    for (var i = 1; i < sorted.length; i++) {
        var last = merged[merged.length - 1];
        if (sorted[i].start <= last.end)
            last.end = Math.max(last.end, sorted[i].end);
        else
            merged.push({ "start": sorted[i].start, "end": sorted[i].end });
    }
    return merged;
}

// How one day was spent: focus, breaks, and the gaps between sessions.
//
// An entry records when it finished and how long it ran, so its interval is
// [at - actual, at] and the day's sessions can be laid back out on a line. Idle is the
// working window minus the time the sessions cover - so it is time between sessions, not
// time before the first or after the last, which the applet knows nothing about.
//
// The covered time is the UNION of the intervals rather than the sum: a task switch
// records a segment mid-session and the remainder is recorded when the session ends, so
// entries are contiguous by construction, but a duplicated or hand-edited entry would
// otherwise make idle negative.
function dayBreakdown(entries, day) {
    var intervals = [];
    var focusSeconds = 0;
    var breakSeconds = 0;
    var sessions = 0;
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.day !== day || typeof entry.at !== "number")
            continue;
        sessions++;
        if (isFocusKind(entry.kind))
            focusSeconds += entry.actual;
        else if (isBreakKind(entry.kind))
            breakSeconds += entry.actual;
        intervals.push({ "start": entry.at - entry.actual * 1000, "end": entry.at });
    }
    if (!sessions) {
        return {
            "focusSeconds": 0, "breakSeconds": 0, "idleSeconds": 0, "spanSeconds": 0,
            "firstStart": 0, "lastEnd": 0, "sessions": 0
        };
    }
    var merged = mergeIntervals(intervals);
    var firstStart = merged[0].start;
    var lastEnd = merged[merged.length - 1].end;
    var coveredMs = 0;
    for (var m = 0; m < merged.length; m++)
        coveredMs += merged[m].end - merged[m].start;
    var spanSeconds = Math.round((lastEnd - firstStart) / 1000);
    return {
        "focusSeconds": focusSeconds,
        "breakSeconds": breakSeconds,
        "idleSeconds": Math.max(0, spanSeconds - Math.round(coveredMs / 1000)),
        "spanSeconds": spanSeconds,
        "firstStart": firstStart,
        "lastEnd": lastEnd,
        "sessions": sessions
    };
}

// The same over a period, summed a day at a time. Idle is never measured across midnight,
// where the gap between yesterday's last session and today's first means nothing.
//
// daysWorked counts the days that recorded anything, so a target for the period can skip
// the days off rather than demanding a full day of every date in the range.
function periodBreakdown(entries, dayCount, today) {
    var out = {
        "focusSeconds": 0, "breakSeconds": 0, "idleSeconds": 0, "spanSeconds": 0,
        "sessions": 0, "daysWorked": 0
    };
    for (var d = dayCount - 1; d >= 0; d--) {
        var date = new Date(today.getTime() - d * 24 * 60 * 60 * 1000);
        var day = dayBreakdown(entries, dayKey(date));
        if (!day.sessions)
            continue;
        out.focusSeconds += day.focusSeconds;
        out.breakSeconds += day.breakSeconds;
        out.idleSeconds += day.idleSeconds;
        out.spanSeconds += day.spanSeconds;
        out.sessions += day.sessions;
        out.daysWorked++;
    }
    return out;
}

// Focus sessions on one day, split by task, heaviest first. Feeds the stacked bars:
// a day's bar used to be one block, so an afternoon spread over four tasks looked
// identical to one spent on a single task.
function focusSegmentsOn(entries, day) {
    var groups = {};
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.day !== day || !isFocusKind(entry.kind))
            continue;
        var key = entry.task || "";
        if (!groups[key])
            groups[key] = { "task": key, "count": 0, "seconds": 0 };
        groups[key].count++;
        groups[key].seconds += entry.actual;
    }
    var out = [];
    for (var name in groups)
        out.push(groups[name]);
    // Heaviest first, then by name, so the stacking order does not reshuffle between
    // repaints when two tasks hold equal time.
    out.sort(function(a, b) {
        if (b.seconds !== a.seconds)
            return b.seconds - a.seconds;
        return a.task < b.task ? -1 : (a.task > b.task ? 1 : 0);
    });
    return out;
}

// A hue for a task name, so the same task keeps the same colour between sessions and
// between the chart and the list below it. Derived from the name rather than from its
// position, which would reshuffle every time the totals change.
//
// The multiplier spreads adjacent hashes apart: without it "Task 1" and "Task 2" land
// on hues a degree apart and read as one colour.
function taskHue(task) {
    var name = "" + (task || "");
    if (!name)
        return -1; // no task: the caller picks a neutral colour instead of a hue
    var hash = 0;
    for (var i = 0; i < name.length; i++)
        hash = (hash * 31 + name.charCodeAt(i)) % 100000;
    return (hash * 137) % 360;
}

// One bucket per day for a chart, oldest first, including days with nothing so
// the bars keep a fixed spacing. dayCount includes today.
function focusPerDay(entries, dayCount, today) {
    var buckets = [];
    for (var d = dayCount - 1; d >= 0; d--) {
        var date = new Date(today.getTime() - d * 24 * 60 * 60 * 1000);
        var key = dayKey(date);
        buckets.push({
            "day": key,
            "count": countFocusOn(entries, key),
            "seconds": focusSecondsOn(entries, key),
            "breakSeconds": breakSecondsOn(entries, key),
            "segments": focusSegmentsOn(entries, key)
        });
    }
    return buckets;
}

// Focus time grouped by task over the last dayCount days, heaviest first.
// Sessions run without a task collect under the empty string, so the caller can
// label them; they are not dropped, or the totals would not add up.
//
// Day keys are zero-padded YYYY-MM-DD, so comparing them as strings is a valid
// date comparison and avoids re-parsing every entry.
function focusByTask(entries, dayCount, today) {
    var cutoff = dayKey(new Date(today.getTime() - (dayCount - 1) * 24 * 60 * 60 * 1000));
    var groups = {};
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (!isFocusKind(entry.kind) || entry.day < cutoff)
            continue;
        var key = entry.task || "";
        if (!groups[key])
            groups[key] = { "task": key, "count": 0, "seconds": 0 };
        groups[key].count++;
        groups[key].seconds += entry.actual;
    }
    var out = [];
    for (var name in groups)
        out.push(groups[name]);
    // Heaviest first, then by name so equal totals keep a stable order rather
    // than reshuffling on every repaint.
    out.sort(function(a, b) {
        if (b.seconds !== a.seconds)
            return b.seconds - a.seconds;
        return a.task < b.task ? -1 : (a.task > b.task ? 1 : 0);
    });
    return out;
}

// How one day looked on a clock: a block per recorded session, in order.
//
// The window is snapped out to whole hours so the hour ticks drawn under it land on real
// gridlines, and never covers less than MIN_TIMELINE_HOURS - a single 25 minute session
// stretched across the full width would suggest a day's work.
var MIN_TIMELINE_HOURS = 4;

function dayTimeline(entries, day) {
    var blocks = [];
    for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.day !== day || typeof entry.at !== "number")
            continue;
        blocks.push({
            "kind": entry.kind,
            "task": entry.task || "",
            "startMs": entry.at - entry.actual * 1000,
            "endMs": entry.at
        });
    }
    if (!blocks.length)
        return { "blocks": [], "windowStart": 0, "windowEnd": 0 };
    blocks.sort(function(a, b) {
        return a.startMs - b.startMs;
    });

    var hourMs = 60 * 60 * 1000;
    var first = blocks[0].startMs;
    var last = blocks[0].endMs;
    for (var b = 1; b < blocks.length; b++)
        last = Math.max(last, blocks[b].endMs);

    var start = Math.floor(first / hourMs) * hourMs;
    var end = Math.ceil(last / hourMs) * hourMs;
    // Grown from the end rather than the start, so the day still begins where it began.
    if (end - start < MIN_TIMELINE_HOURS * hourMs)
        end = start + MIN_TIMELINE_HOURS * hourMs;
    return { "blocks": blocks, "windowStart": start, "windowEnd": end };
}

// Tallest day in a bucket list, in seconds of focus plus break, for scaling a time chart.
// floorSeconds keeps a reference line - the working day - inside the plot; without it a
// quiet week would draw the line above the top of the chart. Never zero, since it divides.
function peakSeconds(buckets, floorSeconds) {
    var peak = floorSeconds || 0;
    for (var i = 0; i < buckets.length; i++) {
        var total = buckets[i].seconds + (buckets[i].breakSeconds || 0);
        if (total > peak)
            peak = total;
    }
    return Math.max(1, peak);
}

// Largest count in a bucket list, for scaling a chart. Never returns 0, so a
// chart over an empty history divides by something sane.
function peakCount(buckets) {
    var peak = 0;
    for (var i = 0; i < buckets.length; i++) {
        if (buckets[i].count > peak)
            peak = buckets[i].count;
    }
    return Math.max(1, peak);
}

// Duration presets, in minutes. Kept here rather than in a QML property so both
// the config page and the panel's context menu read one list, and so the objects
// stay plain JS instead of round-tripping through a QML var.
var PRESETS = [
    { focus: 25, shortBreak: 5, longBreak: 20 },
    { focus: 50, shortBreak: 10, longBreak: 30 },
    { focus: 90, shortBreak: 20, longBreak: 30 }
];

function presetCount() {
    return PRESETS.length;
}

function presetAt(index) {
    return PRESETS[index];
}

// Index of the preset whose three durations match, or presetCount() to mean
// "custom". Derived from the durations rather than stored, so no config key is
// needed and existing settings stay valid.
function matchPreset(focusMinutes, shortMinutes, longMinutes) {
    for (var i = 0; i < PRESETS.length; i++) {
        if (PRESETS[i].focus === focusMinutes && PRESETS[i].shortBreak === shortMinutes && PRESETS[i].longBreak === longMinutes)
            return i;
    }
    return PRESETS.length;
}

function padNumber(num, length) {
    var r = "" + num;
    while (r.length < length)
        r = "0" + r;
    return r;
}

// Negative input is how far a session has run past its end, and is rendered
// with a leading minus. The remainder and floor operators both misbehave on
// negative input, so the magnitude is formatted and the sign put back on.
function formatCounter(totalSeconds) {
    var sign = totalSeconds < 0 ? "-" : "";
    var magnitude = Math.abs(totalSeconds);
    var sec = magnitude % 60;
    var min = Math.floor(magnitude / 60) % 60;
    var hours = Math.floor(magnitude / 60 / 60);
    if (hours > 0)
        return sign + hours + ":" + padNumber(min, 2) + ":" + padNumber(sec, 2);
    return sign + padNumber(min, 2) + ":" + padNumber(sec, 2);
}

// Durations for the stats page, where seconds are noise: "5h20", "45m", "0m". The
// countdown keeps formatCounter() - there a ticking second matters - but a total of
// "13:50:00" reads as a clock time rather than as a length.
function formatDurationCompact(totalSeconds) {
    var seconds = Math.max(0, Math.round(totalSeconds));
    var hours = Math.floor(seconds / 3600);
    var minutes = Math.round((seconds % 3600) / 60);
    if (minutes === 60) {
        hours++;
        minutes = 0;
    }
    if (hours > 0)
        return minutes > 0 ? hours + "h" + padNumber(minutes, 2) : hours + "h";
    return minutes + "m";
}

// The countdown as it appears on a panel: MM:SS, with minutes accumulating rather than
// rolling into an hours field. A vertical panel is about 44 pixels across, where the
// "1:05:00" that formatCounter() produces is seven glyphs and simply does not fit - it was
// clipped. Minutes past sixty read as 65:00, which stays five glyphs.
//
// Negative input is a break overrun, formatted with a leading minus like formatCounter().
function formatCounterPanel(totalSeconds) {
    var sign = totalSeconds < 0 ? "-" : "";
    var magnitude = Math.abs(Math.round(totalSeconds));
    var minutes = Math.floor(magnitude / 60);
    var seconds = magnitude % 60;
    return sign + padNumber(minutes, 2) + ":" + padNumber(seconds, 2);
}

// Remaining fraction of the session, 0..1. A session with no known length - a
// flowmodoro flow, which counts up - reads as full.
function progressFraction(counterSeconds, initialSeconds) {
    if (initialSeconds <= 0)
        return 1;
    return Math.max(0, Math.min(1, counterSeconds / initialSeconds));
}

// A tick warns that a deadline is approaching, so it only applies to a session
// that has one. A flowmodoro flow counts up and has no length at all
// (initialSeconds 0), so warning about its end is meaningless; breaks are never
// warned about.
function shouldTick(counterSeconds, initialSeconds, tickingSeconds, isBreakSession) {
    if (isBreakSession || initialSeconds <= 0)
        return false;
    return counterSeconds > 0 && counterSeconds <= tickingSeconds;
}

// Ticks get louder as the deadline approaches. The ramp keeps a floor so the
// first tick is audible and reaches full volume on the last one - the previous
// formula, 1 - counterSeconds / tickingSeconds, made the first tick silent and
// never reached 1.
function tickVolume(counterSeconds, tickingSeconds) {
    if (tickingSeconds <= 1)
        return 1;
    var elapsed = (tickingSeconds - counterSeconds) / (tickingSeconds - 1);
    elapsed = Math.max(0, Math.min(1, elapsed));
    return 0.35 + 0.65 * elapsed;
}
