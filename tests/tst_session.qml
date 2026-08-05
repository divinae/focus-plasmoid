import QtQuick
import QtTest
import "../package/contents/ui/lib/timer.js" as TimerLogic

TestCase {
    name: "SessionPersistence"

    // Fixed reference point: nothing here may depend on the wall clock.
    readonly property real now: new Date(2026, 6, 28, 12, 0, 0).getTime()
    readonly property real second: 1000
    readonly property real minute: 60 * 1000

    function test_parseSession_survivesRubbish_data() {
        return [
            { tag: "empty", json: "" },
            { tag: "undefined", json: undefined },
            { tag: "truncated", json: '{"stateVal":1,"initial' },
            { tag: "not json", json: "nonsense" },
            { tag: "array not object", json: '[1,2,3]' },
            // Missing the fields the restore path relies on: a half-written value
            // must not resurrect a broken session.
            { tag: "no stateVal", json: '{"initialSeconds":1500}' },
            { tag: "no initialSeconds", json: '{"stateVal":1}' },
            { tag: "stateVal not a number", json: '{"stateVal":"1","initialSeconds":1500}' }
        ];
    }

    function test_parseSession_survivesRubbish(data) {
        compare(TimerLogic.parseSession(data.json), null);
    }

    function test_runningCountdown_roundTripsThroughTheDeadline() {
        // 25 minutes long, 10 minutes in: the deadline is 15 minutes away.
        var json = TimerLogic.serializeSession({
            "stateVal": 1,
            "initialSeconds": 1500,
            "running": true,
            "countingUp": false,
            "deadline": now + 15 * minute,
            "savedAt": now
        });
        var session = TimerLogic.parseSession(json);
        compare(session.stateVal, 1);
        compare(session.initialSeconds, 1500);
        compare(session.running, true);

        // Restored immediately: still 15 minutes.
        compare(TimerLogic.restoredCounterMs(session, now), 15 * minute);
        // The point of storing a deadline: four minutes of downtime are gone, and
        // the restored counter reflects that rather than resuming at 15.
        compare(TimerLogic.restoredCounterMs(session, now + 4 * minute), 11 * minute);
    }

    function test_runningCountdown_thatExpiredWhileDownComesBackNegative() {
        // A break that ran out during the restart must return still overrunning,
        // not reset: the overrun is the feature it feeds.
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 2,
            "initialSeconds": 300,
            "running": true,
            "breakOvertime": false,
            "deadline": now + minute,
            "savedAt": now
        }));
        compare(TimerLogic.restoredCounterMs(session, now + 3 * minute), -2 * minute);
    }

    function test_pausedSession_keepsRemainingRatherThanADeadline() {
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 3,
            "initialSeconds": 1500,
            "running": false,
            "remainingMs": 7 * minute,
            "savedAt": now
        }));
        compare(session.running, false);
        // Paused means the clock is not moving, so time passing must not consume it.
        compare(TimerLogic.restoredCounterMs(session, now), 7 * minute);
        compare(TimerLogic.restoredCounterMs(session, now + 30 * minute), 7 * minute);
    }

    function test_flowSession_countsUpFromWhenItStarted() {
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1,
            "initialSeconds": 0,
            "running": true,
            "countingUp": true,
            "startedAt": now - 8 * minute,
            "savedAt": now
        }));
        compare(session.countingUp, true);
        compare(TimerLogic.restoredCounterMs(session, now), 8 * minute);
        // Downtime adds to a flow rather than eating into it.
        compare(TimerLogic.restoredCounterMs(session, now + 2 * minute), 10 * minute);
    }

    function test_overrunFlagSurvives() {
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 2,
            "initialSeconds": 300,
            "running": true,
            "breakOvertime": true,
            "deadline": now - minute,
            "savedAt": now
        }));
        compare(session.breakOvertime, true);
    }

    function test_stale_isNotRestored() {
        var running = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 1500, "running": true,
            "deadline": now + 15 * minute, "savedAt": now
        }));
        // A running session reports in every few seconds, so only a short gap is a
        // restart. Within it, resume.
        verify(!TimerLogic.sessionIsStale(running, now + 20 * second));
        // Past it the applet was not running: a reboot, or a machine switched off.
        // Resuming would count that downtime as time spent focusing.
        verify(TimerLogic.sessionIsStale(running, now + 45 * second));
        verify(TimerLogic.sessionIsStale(running, now + 14 * 60 * minute));

        var paused = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 1500, "running": false,
            "remainingMs": 5 * minute, "savedAt": now
        }));
        // A pause counts nothing down, so it is kept for much longer: an update or a
        // crash that takes minutes must not throw away the time left.
        verify(!TimerLogic.sessionIsStale(paused, now + 30 * minute));
        verify(TimerLogic.sessionIsStale(paused, now + 14 * 60 * minute));
    }

    function test_running_isJudgedBySavedAt_notByAFutureDeadline() {
        // The case the old reference could not catch: rebooted 20 minutes into a
        // session whose deadline is still ahead. nowMs - deadline is negative, so
        // nothing ever looked stale and the session came back as though the machine
        // had been on throughout.
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 1500, "running": true,
            "deadline": now + 15 * minute, "savedAt": now
        }));
        verify(TimerLogic.sessionIsStale(session, now + 5 * minute));
        verify(TimerLogic.sessionIsStale(session, now + 8 * 60 * minute));
        // And an ordinary plasmashell restart, which takes seconds, still resumes.
        verify(!TimerLogic.sessionIsStale(session, now + 25 * second));
    }

    function test_pausedOutlivesRunning_atTheSameAge() {
        // Same age, opposite verdicts: the asymmetry is the whole rule.
        var fields = { "stateVal": 1, "initialSeconds": 1500, "savedAt": now };
        var running = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": fields.stateVal, "initialSeconds": fields.initialSeconds,
            "running": true, "deadline": now + 10 * minute, "savedAt": fields.savedAt
        }));
        var paused = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": fields.stateVal, "initialSeconds": fields.initialSeconds,
            "running": false, "remainingMs": 10 * minute, "savedAt": fields.savedAt
        }));
        verify(TimerLogic.sessionIsStale(running, now + 5 * minute));
        verify(!TimerLogic.sessionIsStale(paused, now + 5 * minute));
    }

    function test_longFlow_isNotStaleJustForBeingLong() {
        // A flowmodoro flow two hours in, written a moment ago: the mode exists to
        // allow exactly this, so it must be restored. Judging it by startedAt marked
        // every flow past the one-hour cutoff stale and cleared the time on restart.
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 0, "running": true, "countingUp": true,
            "startedAt": now - 120 * minute, "savedAt": now
        }));
        verify(!TimerLogic.sessionIsStale(session, now));
        verify(!TimerLogic.sessionIsStale(session, now + 20 * second));
        // Still bounded by when it last reported in, like any running session.
        verify(TimerLogic.sessionIsStale(session, now + 45 * second));
        verify(TimerLogic.sessionIsStale(session, now + 14 * 60 * minute));
        // And the restored counter keeps counting from when the flow began, so the
        // two hours already accrued survive.
        compare(TimerLogic.restoredCounterMs(session, now + 5 * minute), 125 * minute);
    }

    function test_taskSegmentSurvivesARestart() {
        // Task switched 10 minutes into a 25 minute focus session. Without this the
        // restored session would file those first 10 minutes a second time when it
        // ended, under whichever task was current by then.
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 1500, "running": true,
            "deadline": now + 15 * minute, "taskSegmentStart": 600, "savedAt": now
        }));
        compare(session.taskSegmentStart, 600);
        // Absent in an older stored session, which must read as "no switch".
        var old = TimerLogic.parseSession('{"stateVal":1,"initialSeconds":1500,"running":false,"remainingMs":60000,"savedAt":1}');
        compare(old.taskSegmentStart || 0, 0);
    }

    function test_stale_whenThereIsNothingToJudgeBy() {
        compare(TimerLogic.sessionIsStale(null, now), true);
        // No usable reference timestamp at all: treat as stale rather than guess.
        var noReference = TimerLogic.parseSession('{"stateVal":1,"initialSeconds":1500,"running":true}');
        verify(TimerLogic.sessionIsStale(noReference, now));
    }

    function test_restoredCounter_onNothing() {
        compare(TimerLogic.restoredCounterMs(null, now), 0);
    }
}
