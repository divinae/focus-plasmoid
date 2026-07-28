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
}
