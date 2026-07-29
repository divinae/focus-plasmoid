import QtQuick
import QtTest
import "../package/contents/ui/lib/timer.js" as TimerLogic

TestCase {
    name: "History"

    // Fixed reference point so nothing here depends on the wall clock.
    readonly property date noon: new Date(2026, 6, 28, 12, 0, 0)

    function daysAgo(n) {
        return new Date(noon.getTime() - n * 24 * 60 * 60 * 1000);
    }

    function test_parseHistory_survivesRubbish_data() {
        return [
            { tag: "empty string", json: "" },
            { tag: "undefined", json: undefined },
            { tag: "truncated json", json: '[{"kind":"foc' },
            { tag: "not json at all", json: "nonsense" },
            // A config key holding the wrong shape must not be treated as history.
            { tag: "object not array", json: '{"kind":"focus"}' },
            { tag: "number", json: "42" }
        ];
    }

    function test_parseHistory_survivesRubbish(data) {
        var entries = TimerLogic.parseHistory(data.json);
        verify(Array.isArray(entries));
        compare(entries.length, 0);
    }

    function test_parseHistory_readsBackWhatWasWritten() {
        var json = TimerLogic.appendHistory("", TimerLogic.makeEntry("focus", 1500, 1500, noon, "writing"), noon);
        var entries = TimerLogic.parseHistory(json);
        compare(entries.length, 1);
        compare(entries[0].kind, "focus");
        compare(entries[0].planned, 1500);
        compare(entries[0].actual, 1500);
        compare(entries[0].task, "writing");
    }

    function test_dayKey_isLocalNotUtc() {
        // 23:30 local must file under its own local day. toISOString() would roll
        // this into the next day for any timezone east of UTC.
        compare(TimerLogic.dayKey(new Date(2026, 0, 5, 23, 30, 0)), "2026-01-05");
        compare(TimerLogic.dayKey(new Date(2026, 0, 5, 0, 30, 0)), "2026-01-05");
        // Months and days are zero padded so string comparison sorts correctly.
        compare(TimerLogic.dayKey(new Date(2026, 8, 9, 12, 0, 0)), "2026-09-09");
    }

    function test_makeEntry_clampsAndRounds() {
        // A break overrun means the counter went negative; the recorded actual
        // length must never be negative.
        var entry = TimerLogic.makeEntry("shortBreak", 300.4, -12, noon, "");
        compare(entry.planned, 300);
        compare(entry.actual, 0);
        compare(entry.task, "");
        // The kind and day travel with the entry so summaries need no recompute.
        compare(entry.kind, "shortBreak");
        compare(entry.day, "2026-07-28");
    }

    function test_appendHistory_accumulates() {
        var json = "";
        for (var i = 0; i < 5; i++)
            json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, ""), noon);
        compare(TimerLogic.parseHistory(json).length, 5);
    }

    function test_pruneHistory_dropsOldEntriesOnWrite() {
        var json = TimerLogic.appendHistory("", TimerLogic.makeEntry("focus", 1500, 1500, daysAgo(40), ""), noon);
        // The 40-day-old entry is already outside the window, so writing again
        // must not carry it forward.
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, ""), noon);
        var entries = TimerLogic.parseHistory(json);
        compare(entries.length, 1);
        compare(entries[0].day, TimerLogic.dayKey(noon));
    }

    function test_pruneHistory_keepsInsideWindow() {
        var json = TimerLogic.appendHistory("", TimerLogic.makeEntry("focus", 1500, 1500, daysAgo(5), ""), noon);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, ""), noon);
        compare(TimerLogic.parseHistory(json).length, 2);
    }

    function test_pruneHistory_ignoresEntriesWithNoTimestamp() {
        // Hand-edited or half-written config must not survive as undateable junk.
        var entries = TimerLogic.pruneHistory([{ kind: "focus" }, { kind: "focus", at: noon.getTime() }], noon);
        compare(entries.length, 1);
    }

    function test_countFocusOn_countsOnlyFocusOnThatDay() {
        var json = "";
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, ""), noon);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1400, noon, ""), noon);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("shortBreak", 300, 300, noon, ""), noon);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, daysAgo(1), ""), noon);
        var entries = TimerLogic.parseHistory(json);
        compare(TimerLogic.countFocusOn(entries, TimerLogic.dayKey(noon)), 2);
        compare(TimerLogic.countFocusOn(entries, TimerLogic.dayKey(daysAgo(1))), 1);
        compare(TimerLogic.countFocusOn(entries, "2000-01-01"), 0);
        // Breaks are recorded but never counted as focus.
        compare(TimerLogic.focusSecondsOn(entries, TimerLogic.dayKey(noon)), 1500 + 1400);
    }

    function test_summaries_onEmptyHistory() {
        compare(TimerLogic.countFocusOn([], TimerLogic.dayKey(noon)), 0);
        compare(TimerLogic.focusSecondsOn([], TimerLogic.dayKey(noon)), 0);
    }

    function test_flowSessions_countAsFocus() {
        // Flowmodoro records its working sessions as "flow". They are focus by any
        // reading, and counting only "focus" left that mode's users looking at zeroes.
        var entries = [
            { kind: "flow", day: "2026-07-28", at: 1, planned: 0, actual: 1800, task: "Report" },
            { kind: "focus", day: "2026-07-28", at: 2, planned: 1500, actual: 1500, task: "Report" },
            { kind: "flowBreak", day: "2026-07-28", at: 3, planned: 300, actual: 300, task: "" },
            { kind: "shortBreak", day: "2026-07-28", at: 4, planned: 300, actual: 300, task: "" }
        ];
        compare(TimerLogic.countFocusOn(entries, "2026-07-28"), 2);
        compare(TimerLogic.focusSecondsOn(entries, "2026-07-28"), 3300);
        // Breaks of either mode still do not count.
        verify(!TimerLogic.isFocusKind("flowBreak"));
        verify(!TimerLogic.isFocusKind("shortBreak"));
        verify(!TimerLogic.isFocusKind("longBreak"));

        var byTask = TimerLogic.focusByTask(entries, 7, new Date(2026, 6, 28));
        compare(byTask.length, 1);
        compare(byTask[0].task, "Report");
        compare(byTask[0].count, 2);
        compare(byTask[0].seconds, 3300);
    }

    function test_countsAsSession_dropsShortFocusButNeverBreaks() {
        // Default floor is five minutes.
        verify(!TimerLogic.countsAsSession("focus", 120, 300));
        verify(TimerLogic.countsAsSession("focus", 300, 300));
        verify(TimerLogic.countsAsSession("focus", 1500, 300));
        // A flow is focus, so the floor applies to it too.
        verify(!TimerLogic.countsAsSession("flow", 90, 300));
        // Breaks are never dropped - a five minute break is a normal break.
        verify(TimerLogic.countsAsSession("shortBreak", 60, 300));
        verify(TimerLogic.countsAsSession("flowBreak", 30, 300));
        // A floor of zero records everything.
        verify(TimerLogic.countsAsSession("focus", 1, 0));
        verify(TimerLogic.countsAsSession("focus", 1, undefined));
    }

    function test_renameTaskInHistory_followsTheRename() {
        var entries = [
            { kind: "focus", day: "2026-07-29", at: 1, planned: 1500, actual: 1500, task: "Alpha" },
            { kind: "flow", day: "2026-07-29", at: 2, planned: 0, actual: 600, task: "Alpha" },
            { kind: "focus", day: "2026-07-29", at: 3, planned: 1500, actual: 1500, task: "Beta" },
            { kind: "shortBreak", day: "2026-07-29", at: 4, planned: 300, actual: 300, task: "" }
        ];
        var renamed = TimerLogic.parseHistory(
            TimerLogic.renameTaskInHistory(JSON.stringify(entries), "Alpha", "Gamma"));

        compare(renamed.length, 4);
        compare(renamed[0].task, "Gamma");
        compare(renamed[1].task, "Gamma");
        // Everything else is untouched, including the empty task on the break.
        compare(renamed[2].task, "Beta");
        compare(renamed[3].task, "");
        // The rest of each entry survives, or the totals would change.
        compare(renamed[0].actual, 1500);
        compare(renamed[1].kind, "flow");

        // Grouping now sees one task where it saw two.
        var byTask = TimerLogic.focusByTask(renamed, 7, new Date(2026, 6, 29));
        compare(byTask.length, 2);
        compare(byTask[0].task, "Gamma");
        compare(byTask[0].seconds, 2100);
    }

    function test_renameTaskInHistory_survivesRubbish() {
        // Nothing to rename to or from: return something the caller can store.
        compare(TimerLogic.parseHistory(TimerLogic.renameTaskInHistory("", "Alpha", "Beta")).length, 0);
        compare(TimerLogic.parseHistory(TimerLogic.renameTaskInHistory("not json", "Alpha", "Beta")).length, 0);
        // A no-op rename must not rewrite the value at all.
        var json = '[{"kind":"focus","day":"2026-07-29","at":1,"planned":60,"actual":60,"task":"Alpha"}]';
        compare(TimerLogic.renameTaskInHistory(json, "Alpha", "Alpha"), json);
        compare(TimerLogic.renameTaskInHistory(json, "", "Beta"), json);
        // Renaming onto a title already in use merges them, deliberately.
        var merged = TimerLogic.parseHistory(TimerLogic.renameTaskInHistory(
            '[{"task":"A","kind":"focus","day":"d","at":1,"planned":60,"actual":60},' +
            '{"task":"B","kind":"focus","day":"d","at":2,"planned":60,"actual":60}]', "A", "B"));
        compare(merged[0].task, "B");
        compare(merged[1].task, "B");
    }

    function test_focusSegmentsOn_splitsADayByTask() {
        var entries = [
            { kind: "focus", day: "2026-07-29", at: 1, planned: 1500, actual: 1500, task: "Alpha" },
            { kind: "focus", day: "2026-07-29", at: 2, planned: 1500, actual: 1500, task: "Alpha" },
            { kind: "flow", day: "2026-07-29", at: 3, planned: 0, actual: 600, task: "Beta" },
            { kind: "focus", day: "2026-07-29", at: 4, planned: 900, actual: 900, task: "" },
            { kind: "shortBreak", day: "2026-07-29", at: 5, planned: 300, actual: 300, task: "Alpha" },
            { kind: "focus", day: "2026-07-28", at: 6, planned: 1500, actual: 1500, task: "Alpha" }
        ];
        var segments = TimerLogic.focusSegmentsOn(entries, "2026-07-29");
        // Three tasks that day, heaviest first; the break is not one of them and
        // yesterday's session is not either.
        compare(segments.length, 3);
        compare(segments[0].task, "Alpha");
        compare(segments[0].count, 2);
        compare(segments[0].seconds, 3000);
        compare(segments[1].task, "");
        compare(segments[1].seconds, 900);
        compare(segments[2].task, "Beta");
        compare(segments[2].seconds, 600);
        // The segments account for the whole bar.
        var total = 0;
        for (var i = 0; i < segments.length; i++)
            total += segments[i].count;
        compare(total, TimerLogic.countFocusOn(entries, "2026-07-29"));
        compare(TimerLogic.focusSegmentsOn(entries, "2020-01-01").length, 0);
    }

    function test_focusPerDay_carriesSegments() {
        var entries = [
            { kind: "focus", day: TimerLogic.dayKey(new Date(2026, 6, 29)), at: 1, planned: 60, actual: 60, task: "Alpha" },
            { kind: "focus", day: TimerLogic.dayKey(new Date(2026, 6, 29)), at: 2, planned: 60, actual: 60, task: "Beta" }
        ];
        var buckets = TimerLogic.focusPerDay(entries, 2, new Date(2026, 6, 29));
        compare(buckets.length, 2);
        compare(buckets[1].segments.length, 2);
        // A day with nothing still reports an empty split rather than no property.
        compare(buckets[0].segments.length, 0);
    }

    function test_taskHue_isStableAndSpread() {
        // Same name, same hue - the colour must not move between repaints.
        compare(TimerLogic.taskHue("Alpha"), TimerLogic.taskHue("Alpha"));
        // In range.
        var names = ["Alpha", "Beta", "Task 1", "Task 2", "Report", "z"];
        for (var i = 0; i < names.length; i++) {
            var hue = TimerLogic.taskHue(names[i]);
            verify(hue >= 0 && hue < 360);
        }
        // Names that differ by one character must not land on the same colour, which
        // is what the spreading multiplier is for.
        verify(Math.abs(TimerLogic.taskHue("Task 1") - TimerLogic.taskHue("Task 2")) > 10);
        // No task is not a hue at all; the caller uses a neutral colour.
        compare(TimerLogic.taskHue(""), -1);
        compare(TimerLogic.taskHue(undefined), -1);
    }
}
