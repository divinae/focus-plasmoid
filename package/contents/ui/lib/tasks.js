.pragma library

// Todo list, stored as JSON in a config key for the same reason history is: an
// applet has no file writing. Everything here is pure so it can be tested; the
// caller reads and writes the key.

function parseTasks(json) {
    if (!json)
        return [];
    try {
        var parsed = JSON.parse(json);
        if (!Array.isArray(parsed))
            return [];
        // Drop anything without the fields the UI relies on, so a hand-edited or
        // half-written value cannot produce blank rows.
        var kept = [];
        for (var i = 0; i < parsed.length; i++) {
            var task = parsed[i];
            if (task && typeof task.id === "number" && typeof task.title === "string" && task.title.length > 0)
                kept.push({
                    "id": task.id,
                    "title": task.title,
                    "done": task.done === true,
                    // Preserved deliberately: this rebuild is what would otherwise
                    // drop the flag and resurrect every archived task on next read.
                    "archived": task.archived === true
                });
        }
        return kept;
    } catch (e) {
        return [];
    }
}

function serializeTasks(tasks) {
    return JSON.stringify(tasks);
}

// Ids are one past the highest in use rather than a timestamp, so they stay
// stable, small, and cannot collide when two are added in the same millisecond.
function nextId(tasks) {
    var highest = 0;
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id > highest)
            highest = tasks[i].id;
    }
    return highest + 1;
}

// Returns the new JSON, or the input unchanged if the title is blank.
//
// Adding a title that an archived task already has restores that task instead of
// creating a second row. Two rows with one title would compete for the same history
// entries, which are matched by title, and the older one would be invisible.
function addTask(json, title) {
    var trimmed = ("" + title).trim();
    if (!trimmed)
        return json || "[]";
    var tasks = parseTasks(json);
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].archived && tasks[i].title === trimmed) {
            tasks[i].archived = false;
            tasks[i].done = false;
            return serializeTasks(tasks);
        }
    }
    tasks.push({ "id": nextId(tasks), "title": trimmed, "done": false, "archived": false });
    return serializeTasks(tasks);
}

// Renames in place, keeping done and archived. A blank title is refused rather than
// stored: an empty title is dropped by parseTasks(), so it would delete the row.
//
// Callers must carry the history with the rename - entries name their task by title,
// not by id - which main.qml's renameTask() does.
function renameTask(json, id, title) {
    var trimmed = ("" + title).trim();
    if (!trimmed)
        return json || "[]";
    var tasks = parseTasks(json);
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id === id)
            tasks[i].title = trimmed;
    }
    return serializeTasks(tasks);
}

// Brings an archived task back into the list.
function restoreTask(json, id) {
    var tasks = parseTasks(json);
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id === id)
            tasks[i].archived = false;
    }
    return serializeTasks(tasks);
}

function setDone(json, id, done) {
    var tasks = parseTasks(json);
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id === id)
            tasks[i].done = done === true;
    }
    return serializeTasks(tasks);
}

// Archives rather than deletes. History records the task by title, and a title that
// no longer exists anywhere is a title the stats page cannot label or offer, so
// deleting a task would quietly cost its past sessions their name. Archived tasks are
// hidden from the list and the pickers and are otherwise untouched.
function removeTask(json, id) {
    var tasks = parseTasks(json);
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id === id)
            tasks[i].archived = true;
    }
    return serializeTasks(tasks);
}

// Archives every finished task, for the same reason as removeTask().
function removeDone(json) {
    var tasks = parseTasks(json);
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].done)
            tasks[i].archived = true;
    }
    return serializeTasks(tasks);
}

// The tasks a user should see: everything not archived. Every list, picker and count
// goes through this, so an archived task cannot reappear in one of them.
function visibleTasks(tasks) {
    var out = [];
    for (var i = 0; i < tasks.length; i++) {
        if (!tasks[i].archived)
            out.push(tasks[i]);
    }
    return out;
}

// The deleted ones, for the archive view that offers them back.
function archivedTasks(tasks) {
    var out = [];
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].archived)
            out.push(tasks[i]);
    }
    return out;
}

// Move a task by delta places. Order is the list's own, so reordering is just a
// swap in the stored array. Out-of-range moves are ignored rather than clamped,
// so holding the button at either end does nothing instead of shuffling.
function moveTask(json, id, delta) {
    var tasks = parseTasks(json);
    var from = -1;
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id === id)
            from = i;
    }
    if (from < 0)
        return serializeTasks(tasks);
    var to = from + delta;
    if (to < 0 || to >= tasks.length)
        return serializeTasks(tasks);
    var moved = tasks[from];
    tasks[from] = tasks[to];
    tasks[to] = moved;
    return serializeTasks(tasks);
}

function indexOfTask(tasks, id) {
    for (var i = 0; i < tasks.length; i++) {
        if (tasks[i].id === id)
            return i;
    }
    return -1;
}

function countOpen(tasks) {
    var open = 0;
    for (var i = 0; i < tasks.length; i++) {
        if (!tasks[i].done && !tasks[i].archived)
            open++;
    }
    return open;
}
