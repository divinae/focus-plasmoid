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

// A state whose deadline passed longer ago than this is not restored. Without it,
// returning to the machine after an overnight shutdown would resume a break that
// expired hours ago and open on a huge negative overrun.
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
        "savedAt": Math.round(state.savedAt || 0)
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

// Whether a stored state is too old to resume. What "too old" measures is how long
// ago the applet stopped keeping the session up to date, so the reference is when
// the state was written - except for a running countdown, where the deadline is the
// sharper test: a break that expired long ago must not come back.
//
// Explicitly NOT startedAt for a counting-up flow. A flowmodoro flow running for
// two hours is the mode working as intended, and judging it by its start threw away
// every flow longer than the cutoff.
function sessionIsStale(session, nowMs) {
    if (!session)
        return true;
    var reference = session.running && !session.countingUp ? session.deadline : session.savedAt;
    if (!reference)
        return true;
    return nowMs - reference > SESSION_STALE_AFTER_MS;
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

// Focus sessions finished on the given day. Breaks are recorded too, but the
// count people care about is focus.
function countFocusOn(entries, day) {
    var total = 0;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].day === day && entries[i].kind === "focus")
            total++;
    }
    return total;
}

// Seconds actually spent focusing on the given day.
function focusSecondsOn(entries, day) {
    var total = 0;
    for (var i = 0; i < entries.length; i++) {
        if (entries[i].day === day && entries[i].kind === "focus")
            total += entries[i].actual;
    }
    return total;
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
            "seconds": focusSecondsOn(entries, key)
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
        if (entry.kind !== "focus" || entry.day < cutoff)
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
