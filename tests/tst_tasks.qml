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

    function test_removeTask_andRemoveDone_archiveRatherThanDelete() {
        var json = "";
        json = Tasks.addTask(json, "keep");
        json = Tasks.addTask(json, "finish me");
        json = Tasks.addTask(json, "finish me too");
        json = Tasks.setDone(json, 2, true);
        json = Tasks.setDone(json, 3, true);
        json = Tasks.removeDone(json);

        // Still stored - history names its sessions by title, so losing the row would
        // cost those sessions their name on the stats page.
        var all = Tasks.parseTasks(json);
        compare(all.length, 3);
        // But hidden from everything the user sees.
        var visible = Tasks.visibleTasks(all);
        compare(visible.length, 1);
        compare(visible[0].title, "keep");
        compare(Tasks.countOpen(all), 1);

        // The flag survives a parse/serialize round trip, which is what would
        // otherwise resurrect every archived task on the next read.
        var roundTripped = Tasks.visibleTasks(Tasks.parseTasks(Tasks.serializeTasks(all)));
        compare(roundTripped.length, 1);

        json = Tasks.removeTask(json, 1);
        compare(Tasks.visibleTasks(Tasks.parseTasks(json)).length, 0);
        compare(Tasks.parseTasks(json).length, 3);
        // Removing an unknown id changes nothing.
        compare(Tasks.parseTasks(Tasks.removeTask(json, 999)).length, 3);
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

    function test_focusByTask_groupsAndSortsHeaviestFirst() {
        var json = "";
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, "writing"), noon);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, "writing"), noon);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 600, noon, "email"), noon);
        // Breaks are not focus time and must not appear.
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("shortBreak", 300, 300, noon, "writing"), noon);
        // A session run without a task is kept under the empty string rather than
        // dropped, or the totals would not add up.
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 900, noon, ""), noon);

        var rows = TimerLogic.focusByTask(TimerLogic.parseHistory(json), 14, noon);
        compare(rows.length, 3);
        compare(rows[0].task, "writing");
        compare(rows[0].count, 2);
        compare(rows[0].seconds, 3000);
        compare(rows[1].task, "");
        compare(rows[1].seconds, 900);
        compare(rows[2].task, "email");
        compare(rows[2].seconds, 600);
    }

    function test_focusByTask_respectsTheWindow() {
        var json = "";
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, "recent"), noon);
        var longAgo = new Date(noon.getTime() - 10 * 24 * 60 * 60 * 1000);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, longAgo, "old"), noon);
        var entries = TimerLogic.parseHistory(json);
        // A 14 day window includes both; a 3 day window only the recent one.
        compare(TimerLogic.focusByTask(entries, 14, noon).length, 2);
        var narrow = TimerLogic.focusByTask(entries, 3, noon);
        compare(narrow.length, 1);
        compare(narrow[0].task, "recent");
        // The window includes today, so a single day still sees today's work.
        compare(TimerLogic.focusByTask(entries, 1, noon).length, 1);
    }

    function test_focusByTask_equalTotalsKeepAStableOrder() {
        var json = "";
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, "beta"), noon);
        json = TimerLogic.appendHistory(json, TimerLogic.makeEntry("focus", 1500, 1500, noon, "alpha"), noon);
        var rows = TimerLogic.focusByTask(TimerLogic.parseHistory(json), 14, noon);
        // Same seconds, so name decides rather than insertion order.
        compare(rows[0].task, "alpha");
        compare(rows[1].task, "beta");
    }

    function test_focusByTask_emptyHistory() {
        compare(TimerLogic.focusByTask([], 14, noon).length, 0);
    }

    function test_peakCount_neverZero() {
        // A chart over an empty history must still have a divisor.
        compare(TimerLogic.peakCount([]), 1);
        compare(TimerLogic.peakCount(TimerLogic.focusPerDay([], 7, noon)), 1);
        compare(TimerLogic.peakCount([{ count: 3 }, { count: 5 }, { count: 1 }]), 5);
    }

    function test_renameTask_keepsFlagsAndTrims() {
        var json = Tasks.addTask(Tasks.addTask("", "typo"), "other");
        json = Tasks.setDone(json, 1, true);

        json = Tasks.renameTask(json, 1, "  fixed  ");
        var tasks = Tasks.parseTasks(json);
        compare(tasks[0].title, "fixed");
        // Renaming is not a state change: done and archived survive it.
        compare(tasks[0].done, true);
        compare(tasks[1].title, "other");

        // A blank title would be dropped by parseTasks(), deleting the row, so it is
        // refused instead.
        var untouched = Tasks.renameTask(json, 1, "   ");
        compare(Tasks.parseTasks(untouched)[0].title, "fixed");
        // Unknown id changes nothing.
        compare(Tasks.parseTasks(Tasks.renameTask(json, 999, "nope")).length, 2);
    }

    function test_renameTask_keepsArchivedFlag() {
        var json = Tasks.addTask("", "gone");
        json = Tasks.removeTask(json, 1);
        json = Tasks.renameTask(json, 1, "gone, renamed");
        var all = Tasks.parseTasks(json);
        compare(all[0].title, "gone, renamed");
        compare(all[0].archived, true);
        compare(Tasks.visibleTasks(all).length, 0);
    }

    function test_restoreTask_bringsItBack() {
        var json = Tasks.addTask(Tasks.addTask("", "keep"), "oops");
        json = Tasks.removeTask(json, 2);
        compare(Tasks.visibleTasks(Tasks.parseTasks(json)).length, 1);

        json = Tasks.restoreTask(json, 2);
        var visible = Tasks.visibleTasks(Tasks.parseTasks(json));
        compare(visible.length, 2);
        compare(visible[1].title, "oops");
        // Restoring something that was never archived is harmless.
        compare(Tasks.visibleTasks(Tasks.parseTasks(Tasks.restoreTask(json, 1))).length, 2);
    }

    function test_archivedTasks_isTheComplementOfVisible() {
        var json = "";
        json = Tasks.addTask(json, "a");
        json = Tasks.addTask(json, "b");
        json = Tasks.addTask(json, "c");
        json = Tasks.removeTask(json, 2);
        var all = Tasks.parseTasks(json);
        compare(Tasks.visibleTasks(all).length, 2);
        compare(Tasks.archivedTasks(all).length, 1);
        compare(Tasks.archivedTasks(all)[0].title, "b");
        compare(Tasks.visibleTasks(all).length + Tasks.archivedTasks(all).length, all.length);
    }

    function test_addTask_restoresAnArchivedTitleRatherThanDuplicating() {
        var json = Tasks.addTask("", "Report");
        json = Tasks.removeTask(json, 1);

        json = Tasks.addTask(json, "Report");
        var all = Tasks.parseTasks(json);
        // One row, not two: two rows with one title would compete for the same
        // history entries, which are matched by title.
        compare(all.length, 1);
        compare(all[0].id, 1);
        compare(all[0].archived, false);
        compare(Tasks.visibleTasks(all).length, 1);

        // A genuinely new title still adds a row.
        compare(Tasks.parseTasks(Tasks.addTask(json, "Other")).length, 2);
    }

    function test_addTask_reAddingADoneArchivedTaskComesBackOpen() {
        var json = Tasks.addTask("", "Report");
        json = Tasks.setDone(json, 1, true);
        json = Tasks.removeDone(json);
        json = Tasks.addTask(json, "Report");
        var all = Tasks.parseTasks(json);
        compare(all.length, 1);
        // Adding it again means it is wanted again, so it is not restored ticked off.
        compare(all[0].done, false);
        compare(Tasks.countOpen(all), 1);
    }
}
