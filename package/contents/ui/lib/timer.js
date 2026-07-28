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

function padNumber(num, length) {
    var r = "" + num;
    while (r.length < length)
        r = "0" + r;
    return r;
}

function formatCounter(totalSeconds) {
    var sec = totalSeconds % 60;
    var min = Math.floor(totalSeconds / 60) % 60;
    var hours = Math.floor(totalSeconds / 60 / 60);
    if (hours > 0)
        return hours + ":" + padNumber(min, 2) + ":" + padNumber(sec, 2);
    return padNumber(min, 2) + ":" + padNumber(sec, 2);
}

// Remaining fraction of the session, 0..1. A session with no known length - a
// flowmodoro flow, which counts up - reads as full.
function progressFraction(counterSeconds, initialSeconds) {
    if (initialSeconds <= 0)
        return 1;
    return Math.max(0, Math.min(1, counterSeconds / initialSeconds));
}
