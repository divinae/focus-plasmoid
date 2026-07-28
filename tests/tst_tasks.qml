import QtQuick
import QtTest
import "../package/contents/ui/lib/tasks.js" as Tasks
import "../package/contents/ui/lib/timer.js" as TimerLogic

TestCase {
    name: "Tasks"

    readonly property date noon: new Date(2026, 6, 28, 12, 0, 0)

    function test_parseTasks_survivesRubbish_data() {
        return [
            { tag: "empty", json: "" },
            { tag: "truncated", json: '[{"id":1,"tit' },
            { tag: "not json", json: "nope" },
            { tag: "object not array", json: '{"id":1}' },
            // Rows missing the fields the list binds to would render blank.
            { tag: "no title", json: '[{"id":1}]' },
            { tag: "blank title", json: '[{"id":1,"title":""}]' },
            { tag: "no id", json: '[{"title":"write tests"}]' },
            { tag: "id not a number", json: '[{"id":"1","title":"x"}]' }
        ];
    }

    function test_parseTasks_survivesRubbish(data) {
        var tasks = Tasks.parseTasks(data.json);
        verify(Array.isArray(tasks));
        compare(tasks.length, 0);
    }

    function test_addTask_andReadBack() {
        var json = Tasks.addTask("", "write the tests");
        var tasks = Tasks.parseTasks(json);
        compare(tasks.length, 1);
        compare(tasks[0].title, "write the tests");
        compare(tasks[0].done, false);
        compare(tasks[0].id, 1);
    }

    function test_addTask_trimsAndRejectsBlank() {
        var json = Tasks.addTask("", "   padded   ");
        compare(Tasks.parseTasks(json)[0].title, "padded");
        // Blank input must not create an untitled row.
        json = Tasks.addTask(json, "   ");
        compare(Tasks.parseTasks(json).length, 1);
        json = Tasks.addTask(json, "");
        compare(Tasks.parseTasks(json).length, 1);
    }

    function test_ids_areUniqueAndStable() {
        var json = "";
        for (var i = 0; i < 4; i++)
            json = Tasks.addTask(json, "task " + i);
        var tasks = Tasks.parseTasks(json);
        compare(tasks.length, 4);
        var seen = {};
        for (var j = 0; j < tasks.length; j++) {
            verify(seen[tasks[j].id] === undefined, "duplicate id " + tasks[j].id);
            seen[tasks[j].id] = true;
        }
        // Removing the middle then adding again must not reuse a live id.
        json = Tasks.removeTask(json, 2);
        json = Tasks.addTask(json, "after removal");
        var after = Tasks.parseTasks(json);
        var ids = {};
        for (var k = 0; k < after.length; k++) {
            verify(ids[after[k].id] === undefined, "id reused after removal");
            ids[after[k].id] = true;
        }
    }

    function test_setDone_andCountOpen() {
        var json = Tasks.addTask(Tasks.addTask("", "one"), "two");
        compare(Tasks.countOpen(Tasks.parseTasks(json)), 2);
        json = Tasks.setDone(json, 1, true);
        compare(Tasks.countOpen(Tasks.parseTasks(json)), 1);
        // Toggling back is symmetric.
        json = Tasks.setDone(json, 1, false);
        compare(Tasks.countOpen(Tasks.parseTasks(json)), 2);
        // An unknown id changes nothing rather than throwing.
        json = Tasks.setDone(json, 999, true);
        compare(Tasks.countOpen(Tasks.parseTasks(json)), 2);
    }

    function test_removeTask_andRemoveDone() {
        var json = "";
        json = Tasks.addTask(json, "keep");
        json = Tasks.addTask(json, "finish me");
        json = Tasks.addTask(json, "finish me too");
        json = Tasks.setDone(json, 2, true);
        json = Tasks.setDone(json, 3, true);
        json = Tasks.removeDone(json);
        var tasks = Tasks.parseTasks(json);
        compare(tasks.length, 1);
        compare(tasks[0].title, "keep");
        // Removing an unknown id is a no-op.
        compare(Tasks.parseTasks(Tasks.removeTask(json, 999)).length, 1);
    }

    function test_moveTask_reorders() {
        var json = "";
        json = Tasks.addTask(json, "first");
        json = Tasks.addTask(json, "second");
        json = Tasks.addTask(json, "third");

        // Move "second" up one place.
        json = Tasks.moveTask(json, 2, -1);
        var tasks = Tasks.parseTasks(json);
        compare(tasks[0].title, "second");
        compare(tasks[1].title, "first");
        compare(tasks[2].title, "third");

        // And back down.
        json = Tasks.moveTask(json, 2, 1);
        tasks = Tasks.parseTasks(json);
        compare(tasks[0].title, "first");
        compare(tasks[1].title, "second");
    }

    function test_moveTask_atTheEndsDoesNothing() {
        var json = Tasks.addTask(Tasks.addTask("", "first"), "second");
        // Already at the top, and already at the bottom.
        compare(Tasks.parseTasks(Tasks.moveTask(json, 1, -1))[0].title, "first");
        compare(Tasks.parseTasks(Tasks.moveTask(json, 2, 1))[1].title, "second");
        // Length is never changed by a rejected move.
        compare(Tasks.parseTasks(Tasks.moveTask(json, 1, -5)).length, 2);
        compare(Tasks.parseTasks(Tasks.moveTask(json, 2, 5)).length, 2);
    }

    function test_moveTask_unknownIdIsHarmless() {
        var json = Tasks.addTask(Tasks.addTask("", "first"), "second");
        var after = Tasks.parseTasks(Tasks.moveTask(json, 999, -1));
        compare(after.length, 2);
        compare(after[0].title, "first");
    }

    function test_indexOfTask() {
        var tasks = Tasks.parseTasks(Tasks.addTask(Tasks.addTask("", "a"), "b"));
        compare(Tasks.indexOfTask(tasks, 1), 0);
        compare(Tasks.indexOfTask(tasks, 2), 1);
        compare(Tasks.indexOfTask(tasks, 42), -1);
    }

    // --- statistics aggregation -------------------------------------------

    function test_focusPerDay_hasOneBucketPerDayOldestFirst() {
        var buckets = TimerLogic.focusPerDay([], 7, noon);
        compare(buckets.length, 7);
        compare(buckets[6].day, TimerLogic.dayKey(noon));
        var yesterday = new Date(noon.getTime() - 24 * 60 * 60 * 1000);
        compare(buckets[5].day, TimerLogic.dayKey(yesterday));
        // Empty days still get a bucket so the bars keep fixed spacing.
        compare(buckets[0].count, 0);
        compare(buckets[0].seconds, 0);
    }

    function test_focusPerDay_countsIntoTheRightBucket() {
        var json = "";
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, ""), noon);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1200, noon, ""), noon);
        var twoDaysAgo = new Date(noon.getTime() - 2 * 24 * 60 * 60 * 1000);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, twoDaysAgo, ""), noon);
        // Breaks must never land in a focus bucket.
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("shortBreak", 300, 300, noon, ""), noon);

        var buckets = TimerLogic.focusPerDay(TimerLogic.parseHistory(json), 7, noon);
        compare(buckets[6].count, 2);
        compare(buckets[6].seconds, 2700);
        compare(buckets[4].count, 1);
        compare(buckets[5].count, 0);
    }

    function test_peakCount_neverZero() {
        // A chart over an empty history must still have a divisor.
        compare(TimerLogic.peakCount([]), 1);
        compare(TimerLogic.peakCount(TimerLogic.focusPerDay([], 7, noon)), 1);
        compare(TimerLogic.peakCount([{ count: 3 }, { count: 5 }, { count: 1 }]), 5);
    }
}
