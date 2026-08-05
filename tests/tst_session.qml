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

    // The boot the machine is on while these run, and the one it was on before.
    readonly property string boot: "b6e0f1a2-3c4d-5e6f-7a8b-9c0d1e2f3a4b"
    readonly property string previousBoot: "00000000-1111-2222-3333-444444444444"

    function test_rebootIsNotResumed_howeverRecentTheStateLooks() {
        // Written seconds ago by the boot before this one: a reboot so quick that no
        // age test could tell it from a plasmashell restart. The countdown derives from
        // the wall clock, so resuming would bank the downtime as time spent focusing.
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 1500, "running": true,
            "deadline": now + 15 * minute, "savedAt": now, "bootId": previousBoot
        }));
        verify(TimerLogic.sessionIsStale(session, now + 5 * second, boot));
        verify(TimerLogic.sessionIsStale(session, now + 8 * 60 * minute, boot));
        // A paused session is no different: the machine still went down.
        var paused = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 1500, "running": false,
            "remainingMs": 5 * minute, "savedAt": now, "bootId": previousBoot
        }));
        verify(TimerLogic.sessionIsStale(paused, now + 5 * second, boot));
    }

    function test_sameBoot_resumesForAsLongAsTheCutoffAllows() {
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 1500, "running": true,
            "deadline": now + 15 * minute, "savedAt": now, "bootId": boot
        }));
        // plasmashell restarted - an update, a crash - while the machine stayed up. The
        // state is only written on transitions, so it may be minutes old and must still
        // be picked up.
        verify(!TimerLogic.sessionIsStale(session, now + 5 * second, boot));
        verify(!TimerLogic.sessionIsStale(session, now + 20 * minute, boot));
        // Bounded even so: a shell that was gone for hours swallowed the gap too.
        verify(TimerLogic.sessionIsStale(session, now + 2 * 60 * minute, boot));
    }

    function test_unknownBootId_fallsBackToTheAgeAlone() {
        // A session stored before this applet knew about boot ids, or one saved while
        // the id could not be read: no reboot test is possible, so only age is left.
        var stored = TimerLogic.parseSession('{"stateVal":1,"initialSeconds":1500,"running":true,"deadline":' + (now + 15 * minute) + ',"savedAt":' + now + '}');
        verify(!TimerLogic.sessionIsStale(stored, now + 20 * minute, boot));
        verify(TimerLogic.sessionIsStale(stored, now + 2 * 60 * minute, boot));
        // Same when the current boot id is the one that is missing.
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 1500, "running": true,
            "deadline": now + 15 * minute, "savedAt": now, "bootId": previousBoot
        }));
        verify(!TimerLogic.sessionIsStale(session, now + 20 * minute, ""));
        verify(TimerLogic.sessionIsStale(session, now + 2 * 60 * minute, ""));
    }

    function test_longFlow_isNotStaleJustForBeingLong() {
        // A flowmodoro flow two hours in: the mode exists to allow exactly this, so on
        // the same boot it must be restored however long it has been running. Judging it
        // by startedAt, or by the age of a state only transitions write, marked every
        // long flow stale and cleared the time on restart.
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 0, "running": true, "countingUp": true,
            "startedAt": now - 120 * minute, "savedAt": now - 120 * minute,
            "bootId": boot
        }));
        verify(!TimerLogic.sessionIsStale(session, now, boot));
        verify(!TimerLogic.sessionIsStale(session, now + 60 * minute, boot));
        // A reboot still ends it, and so does an unknown boot id past the cutoff.
        verify(TimerLogic.sessionIsStale(session, now, previousBoot));
        verify(TimerLogic.sessionIsStale(session, now, ""));
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
        compare(TimerLogic.sessionIsStale(null, now, boot), true);
        // No usable reference timestamp at all: treat as stale rather than guess, even
        // though the boot id would have vouched for it.
        var noReference = TimerLogic.parseSession('{"stateVal":1,"initialSeconds":1500,"running":true,"bootId":"' + boot + '"}');
        verify(TimerLogic.sessionIsStale(noReference, now, boot));
    }

    function test_restoredCounter_onNothing() {
        compare(TimerLogic.restoredCounterMs(null, now), 0);
    }
}
