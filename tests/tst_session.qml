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

    function test_longFlow_survivesWhileItIsBeingKeptAlive() {
        // A flowmodoro flow two hours in: the mode exists to allow exactly this, so it must be
        // restored however long it has been running. What says it is still running is a recent
        // savedAt, which the keepalive in main.qml writes every minute.
        //
        // This test used to assert that a flow with a two-hour-old savedAt was fresh, which is
        // what let a suspend come back as focus: the same boot, an old timestamp and no way to
        // tell a long flow from a long sleep. A running flow now always has a recent one.
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 0, "running": true, "countingUp": true,
            "startedAt": now - 120 * minute, "savedAt": now - 30 * 1000,
            "bootId": boot
        }));
        verify(!TimerLogic.sessionIsStale(session, now, boot));
        // A reboot still ends it, whatever the timestamps say.
        verify(TimerLogic.sessionIsStale(session, now, previousBoot));
        // The restored counter keeps counting from when the flow began, so the two hours
        // already accrued survive.
        compare(TimerLogic.restoredCounterMs(session, now + 5 * minute), 125 * minute);

        // The same flow after a long gap with nothing written: the machine was asleep, and
        // resuming would bank the sleep as focus.
        verify(TimerLogic.sessionIsStale(session, now + 8 * 60 * minute, boot));
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

    // --- the two bugs the code review found -------------------------------------------

    function test_longRunningCountdown_survivesARestart() {
        // A ninety minute focus, restarted seventy minutes in. savedAt is only written at a
        // transition, so judging the age by it alone called this stale and threw away seventy
        // minutes of work. It is still counting down, so it is resumed.
        var startedAt = now - 70 * minute;
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 90 * 60, "running": true, "countingUp": false,
            "deadline": startedAt + 90 * minute, "savedAt": startedAt, "bootId": "boot-1"
        }));
        verify(!TimerLogic.sessionIsStale(session, now, "boot-1"));
        // And the counter comes back with the remaining twenty minutes.
        compare(TimerLogic.restoredCounterMs(session, now), 20 * minute);
    }

    function test_countdownPastItsEnd_isJudgedByHowLongAgoItExpired() {
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 2, "initialSeconds": 300, "running": true, "countingUp": false,
            "deadline": now - 10 * minute, "savedAt": now - 15 * minute, "bootId": "boot-1"
        }));
        // Ten minutes into an overrun: still worth coming back to.
        verify(!TimerLogic.sessionIsStale(session, now, "boot-1"));
        // Hours past its end: not.
        verify(TimerLogic.sessionIsStale(session, now + 3 * 60 * minute, "boot-1"));
    }

    function test_flowIsNotExemptFromTheAgeTest() {
        // Suspending does not change the boot id, so a flow exempted from the age test came
        // back counting the sleep as focus: started 09:00, resumed 18:00, nine hours banked.
        // The keepalive keeps savedAt recent, so the gap shows up here.
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 0, "running": true, "countingUp": true,
            "startedAt": now - 60 * minute, "savedAt": now, "bootId": "boot-1"
        }));
        // Fresh: a flow an hour in, saved a moment ago, resumes.
        verify(!TimerLogic.sessionIsStale(session, now, "boot-1"));
        // Eight hours later with no keepalive write in between - the machine was asleep.
        verify(TimerLogic.sessionIsStale(session, now + 8 * 60 * minute, "boot-1"));
    }

    function test_aRebootIsNeverResumed() {
        var session = TimerLogic.parseSession(TimerLogic.serializeSession({
            "stateVal": 1, "initialSeconds": 1500, "running": true, "countingUp": false,
            "deadline": now + 20 * minute, "savedAt": now, "bootId": "boot-1"
        }));
        // Same boot: in flight, so resumed.
        verify(!TimerLogic.sessionIsStale(session, now, "boot-1"));
        // A different boot id outranks everything else, including a deadline still ahead.
        verify(TimerLogic.sessionIsStale(session, now, "boot-2"));
        // An unknown id on either side falls back to the time tests, which still resume it.
        verify(!TimerLogic.sessionIsStale(session, now, ""));
    }
}
