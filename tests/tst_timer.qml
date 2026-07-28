import QtQuick
import QtTest
import "../package/contents/ui/lib/timer.js" as TimerLogic

TestCase {
    name: "TimerLogic"

    function test_isBreak_data() {
        return [
            { tag: "first focus", state: 1, expected: false },
            { tag: "first break", state: 2, expected: true },
            { tag: "second focus", state: 3, expected: false },
            { tag: "last break", state: 8, expected: true }
        ];
    }

    function test_isBreak(data) {
        compare(TimerLogic.isBreak(data.state), data.expected);
    }

    function test_isLongBreak() {
        verify(!TimerLogic.isLongBreak(2, 4));
        verify(!TimerLogic.isLongBreak(6, 4));
        verify(TimerLogic.isLongBreak(8, 4));
        // A single-session run has no short break at all.
        verify(TimerLogic.isLongBreak(2, 1));
    }

    function test_sessionKind_data() {
        return [
            { tag: "focus", state: 1, flow: false, expected: "focus" },
            { tag: "short break", state: 2, flow: false, expected: "shortBreak" },
            { tag: "long break", state: 8, flow: false, expected: "longBreak" },
            { tag: "flow", state: 1, flow: true, expected: "flow" },
            { tag: "flow break", state: 2, flow: true, expected: "flowBreak" },
            // Flowmodoro has no long break, even on the state that would be one.
            { tag: "flow ignores long break", state: 8, flow: true, expected: "flowBreak" }
        ];
    }

    function test_sessionKind(data) {
        compare(TimerLogic.sessionKind(data.state, 4, data.flow), data.expected);
    }

    function test_nextState_cycles() {
        var seen = [];
        var s = 1;
        for (var i = 0; i < 8; i++) {
            s = TimerLogic.nextState(s, 4, {});
            seen.push(s);
        }
        compare(seen, [2, 3, 4, 5, 6, 7, 8, 1]);
    }

    function test_nextState_skipsShortBreaks() {
        var opts = { skipShortBreak: true };
        // 1 -> (2 skipped) -> 3
        compare(TimerLogic.nextState(1, 4, opts), 3);
        compare(TimerLogic.nextState(3, 4, opts), 5);
        // The long break is not a short break and must still run.
        compare(TimerLogic.nextState(7, 4, opts), 8);
    }

    function test_nextState_skipsLongBreak() {
        var opts = { skipLongBreak: true };
        // Short breaks are untouched...
        compare(TimerLogic.nextState(1, 4, opts), 2);
        // ...and the long break wraps straight back to the first focus session.
        compare(TimerLogic.nextState(7, 4, opts), 1);
    }

    function test_nextState_skipsBothBreaks() {
        var opts = { skipShortBreak: true, skipLongBreak: true };
        compare(TimerLogic.nextState(1, 4, opts), 3);
        compare(TimerLogic.nextState(7, 4, opts), 1);
        // Must terminate even when every break is disabled.
        compare(TimerLogic.nextState(1, 1, opts), 1);
    }

    function test_nextState_flowmodoroIgnoresBreakSettings() {
        var opts = { flowmodoro: true, skipShortBreak: true, skipLongBreak: true };
        compare(TimerLogic.nextState(1, 4, opts), 2);
        compare(TimerLogic.nextState(7, 4, opts), 8);
    }

    function test_prevState() {
        compare(TimerLogic.prevState(4), 3);
        compare(TimerLogic.prevState(2), 1);
        // Never runs off the start of the cycle.
        compare(TimerLogic.prevState(1), 1);
    }

    function test_formatCounter_data() {
        return [
            { tag: "zero", seconds: 0, expected: "00:00" },
            { tag: "seconds", seconds: 9, expected: "00:09" },
            { tag: "minutes", seconds: 25 * 60, expected: "25:00" },
            { tag: "under an hour", seconds: 59 * 60 + 59, expected: "59:59" },
            { tag: "an hour", seconds: 3600, expected: "1:00:00" },
            { tag: "over an hour", seconds: 3600 + 5 * 60 + 3, expected: "1:05:03" }
        ];
    }

    function test_formatCounter(data) {
        compare(TimerLogic.formatCounter(data.seconds), data.expected);
    }

    function test_progressFraction_data() {
        return [
            { tag: "full", left: 300, total: 300, expected: 1 },
            { tag: "half", left: 150, total: 300, expected: 0.5 },
            { tag: "empty", left: 0, total: 300, expected: 0 },
            // A counting-up flow session has no known length.
            { tag: "no length", left: 42, total: 0, expected: 1 },
            // Scrolling can push the counter past either end.
            { tag: "clamped high", left: 400, total: 300, expected: 1 },
            { tag: "clamped low", left: -5, total: 300, expected: 0 }
        ];
    }

    function test_progressFraction(data) {
        compare(TimerLogic.progressFraction(data.left, data.total), data.expected);
    }
}
