import QtQml
import QtQuick

// One layer-shell overlay per screen, in a file of its own.
//
// This exists because a static type reference is an EAGER dependency: QML resolves every
// composite type named in a document when it loads that document, including inside a
// delegate, and including one whose Instantiator is inactive. So naming BreakOverlayLayer
// in main.qml made main.qml itself fail wherever org.kde.layershell is missing - the very
// failure #58 reported, with the runtime probe never getting a chance to run.
//
// main.qml reaches this file through a Loader source URL instead, which is resolved at
// runtime, so a machine without the module never loads it and never sees the import.
QtObject {
    id: root

    property var applet: null
    readonly property alias count: overlays.count

    signal closeRequested()

    function objectAt(index) {
        return overlays.objectAt(index);
    }

    property Instantiator overlays: Instantiator {
        id: overlays

        // Nothing is built until the applet has been handed over: main.qml assigns it from
        // the Loader's onLoaded, and a window created before that would evaluate every
        // binding through a null applet.
        active: !!root.applet
        model: Qt.application.screens
        onObjectAdded: (index, object) => {
            if (root.applet)
                root.applet.syncBreakDialog();
        }

        delegate: BreakOverlayLayer {
            applet: root.applet
            screenGeometry: Qt.rect(modelData.virtualX, modelData.virtualY, modelData.width, modelData.height)
            onCloseRequested: root.closeRequested()
        }
    }
}
