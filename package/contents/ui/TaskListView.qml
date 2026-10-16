import "./lib/tasks.js" as Tasks
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// Todo list page. Owns no state: it reads and writes the task_list config key
// through the pure helpers in lib/tasks.js.
Item {
    id: root

    // Colours come from the caller, not from Kirigami.Theme here: the applet reads the
    // theme in exactly one place, and the note above that palette in main.qml says why a
    // read per delegate used to take plasmashell down.
    required property color dimColor
    required property color textColor

    // The stored JSON, and a way to write it back.
    required property string tasksJson
    // Currently selected task title, so the active one can be marked.
    property string activeTask: ""

    signal saveRequested(string json)
    signal taskPicked(string title)
    // Renaming has to rewrite the history too, which is not this view's business, so
    // the applet root owns it.
    signal renameRequested(int id, string title)

    // Which list is on show. Deleting a task archives it, so without a way back an
    // accidental delete would be unrecoverable.
    property bool showingArchived: false

    readonly property var allTasks: Tasks.parseTasks(tasksJson)
    // Archived tasks are the ones the user deleted: kept in the stored list so the
    // stats page can still name their past sessions.
    readonly property var tasks: showingArchived
        ? Tasks.archivedTasks(allTasks)
        : Tasks.visibleTasks(allTasks)
    readonly property int archivedCount: Tasks.archivedTasks(allTasks).length

    // Restoring the last archived task (or re-adding its title) empties the archive
    // under the user's feet; an empty archive view has nothing to do, so leave it.
    onArchivedCountChanged: if (archivedCount === 0)
        showingArchived = false

    function add() {
        var title = newTask.text;
        if (!title.trim())
            return;
        root.saveRequested(Tasks.addTask(root.tasksJson, title));
        newTask.text = "";
        // A new or restored task lands in the open list, so show that one.
        root.showingArchived = false;
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PlasmaComponents.TextField {
                id: newTask

                Layout.fillWidth: true
                placeholderText: i18n("Add a task…")
                onAccepted: root.add()
            }

            PlasmaComponents.Button {
                icon.name: "list-add"
                enabled: newTask.text.trim() !== ""
                onClicked: root.add()
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tasks.length === 0
            text: root.showingArchived
                ? i18n("Nothing archived. Tasks you delete end up here, so their recorded sessions keep their name.")
                : i18n("No tasks yet. Add one above, then pick it to focus on.")
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: root.dimColor
        }

        QQC2.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.tasks.length > 0
            clip: true

            ListView {
                id: list

                model: root.tasks
                spacing: 0

                delegate: RowLayout {
                    id: taskRow

                    required property var modelData
                    required property int index

                    // Move, delete and restore only appear for the row under the
                    // pointer: three buttons on every row turned the list into a wall
                    // of icons, and they are all one-off actions rather than things to
                    // read. Kept visible while renaming, so the row does not twitch.
                    //
                    // Faded rather than hidden: taking them out of the layout would
                    // resize the title as the pointer moved from row to row.
                    readonly property bool showActions: rowHover.hovered || taskRow.editing

                    width: list.width
                    spacing: 0

                    HoverHandler {
                        id: rowHover
                    }

                    // True while this row's title is being edited in place.
                    property bool editing: false

                    function commitRename() {
                        if (!editing)
                            return;
                        editing = false;
                        root.renameRequested(modelData.id, titleField.text);
                    }

                    PlasmaComponents.CheckBox {
                        visible: !root.showingArchived
                        checked: modelData.done
                        onToggled: root.saveRequested(Tasks.setDone(root.tasksJson, modelData.id, checked))
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        visible: !taskRow.editing
                        text: modelData.title
                        elide: Text.ElideRight
                        font.strikeout: modelData.done
                        // The task being focused on is called out rather than
                        // relying on the dial alone.
                        font.bold: !modelData.done && modelData.title === root.activeTask
                        color: modelData.done || root.showingArchived ? root.dimColor : root.textColor

                        MouseArea {
                            id: titleMouse

                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: root.showingArchived ? Qt.ArrowCursor : Qt.PointingHandCursor
                            // Renaming is on double-click rather than a fourth button:
                            // the row already carries three, and a popup-width row has
                            // no space for another.
                            onDoubleClicked: {
                                if (root.showingArchived)
                                    return;
                                taskRow.editing = true;
                                titleField.text = modelData.title;
                                titleField.selectAll();
                                titleField.forceActiveFocus();
                            }
                            onClicked: if (!modelData.done && !root.showingArchived)
                                root.taskPicked(modelData.title)

                            // A ToolTip is a Popup, so something has to show it; bound to
                            // hover rather than left to appear on its own.
                            PlasmaComponents.ToolTip {
                                visible: titleMouse.containsMouse
                                delay: Kirigami.Units.toolTipDelay
                                text: root.showingArchived
                                    ? i18n("Archived. Restore it to use it again.")
                                    : i18n("Click to focus on this task, double-click to rename it.")
                            }
                        }
                    }

                    PlasmaComponents.TextField {
                        id: titleField

                        Layout.fillWidth: true
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        visible: taskRow.editing
                        onAccepted: taskRow.commitRename()
                        // Committing on focus loss as well, so clicking away keeps the
                        // edit rather than silently discarding it.
                        onActiveFocusChanged: if (!activeFocus)
                            taskRow.commitRename()
                        Keys.onEscapePressed: {
                            taskRow.editing = false;
                            taskRow.forceActiveFocus();
                        }
                    }

                    // Reordering is a swap in the stored list. Buttons rather than
                    // drag and drop: the list is short, and a drag would fight the
                    // ScrollView it sits in.
                    PlasmaComponents.ToolButton {
                        icon.name: "edit-undo"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Restore")
                        flat: true
                        visible: root.showingArchived
                        opacity: taskRow.showActions ? 1 : 0
                        enabled: taskRow.showActions
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                        implicitHeight: implicitWidth
                        icon.width: Kirigami.Units.iconSizes.small
                        icon.height: Kirigami.Units.iconSizes.small
                        onClicked: root.saveRequested(Tasks.restoreTask(root.tasksJson, modelData.id))
                    }

                    PlasmaComponents.ToolButton {
                        visible: !root.showingArchived
                        opacity: taskRow.showActions ? 1 : 0
                        icon.name: "arrow-up"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Move up")
                        flat: true
                        enabled: taskRow.showActions && index > 0
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                        implicitHeight: implicitWidth
                        icon.width: Kirigami.Units.iconSizes.small
                        icon.height: Kirigami.Units.iconSizes.small
                        onClicked: root.saveRequested(Tasks.moveTask(root.tasksJson, modelData.id, -1))
                    }

                    PlasmaComponents.ToolButton {
                        visible: !root.showingArchived
                        opacity: taskRow.showActions ? 1 : 0
                        icon.name: "arrow-down"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Move down")
                        flat: true
                        enabled: taskRow.showActions && index < root.tasks.length - 1
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                        implicitHeight: implicitWidth
                        icon.width: Kirigami.Units.iconSizes.small
                        icon.height: Kirigami.Units.iconSizes.small
                        onClicked: root.saveRequested(Tasks.moveTask(root.tasksJson, modelData.id, 1))
                    }

                    PlasmaComponents.ToolButton {
                        visible: !root.showingArchived
                        opacity: taskRow.showActions ? 1 : 0
                        enabled: taskRow.showActions
                        icon.name: "edit-delete-remove"
                        display: QQC2.AbstractButton.IconOnly
                        text: i18n("Remove")
                        flat: true
                        // Sized explicitly: the default ToolButton icon is far
                        // larger than a list row wants.
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.smallSpacing
                        implicitHeight: implicitWidth
                        icon.width: Kirigami.Units.iconSizes.small
                        icon.height: Kirigami.Units.iconSizes.small
                        onClicked: root.saveRequested(Tasks.removeTask(root.tasksJson, modelData.id))
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            // Shown whenever there is anything to say, including an empty task list
            // with a full archive - which is exactly when the way back matters most.
            // The archive view always keeps it, or "Back to tasks" goes with it (#69).
            visible: root.showingArchived || root.tasks.length > 0 || root.archivedCount > 0

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: root.showingArchived
                    ? i18np("%1 archived task", "%1 archived tasks", root.archivedCount)
                    : i18np("%1 task open", "%1 tasks open", Tasks.countOpen(root.allTasks))
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: root.dimColor
                elide: Text.ElideRight
            }

            PlasmaComponents.Button {
                visible: root.archivedCount > 0 || root.showingArchived
                text: root.showingArchived ? i18n("Back to tasks") : i18np("Archived (%1)", "Archived (%1)", root.archivedCount)
                icon.name: root.showingArchived ? "go-previous" : "view-hidden"
                onClicked: root.showingArchived = !root.showingArchived
            }

            PlasmaComponents.Button {
                visible: !root.showingArchived
                text: i18n("Clear finished")
                icon.name: "edit-clear-history"
                enabled: Tasks.countOpen(root.tasks) < root.tasks.length
                onClicked: root.saveRequested(Tasks.removeDone(root.tasksJson))
            }
        }
    }
}
