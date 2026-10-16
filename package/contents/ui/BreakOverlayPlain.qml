import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

// One fullscreen break overlay. Instantiated once per screen, because a single
// window only covers the display it is on, which left every other monitor
// uncovered during a break (gitlab #19).
//
// Plain fullscreen window. The variant that also keeps the overlay on every virtual
// desktop is BreakOverlayLayer.qml, which adds the layer-shell properties on top of
// this file - that module is optional and missing on some distributions, so importing
// it here would take the whole applet down with it (gitlab #58).
//
// The unblurred flavour. Its layer-shell counterpart is BreakOverlayPlainLayer.qml;
// see BreakOverlay.qml for why the import lives there and not here (gitlab #58).
//
// DashboardWindow enables blur AND Plasma's background
// contrast effect in C++, and neither can be turned off from QML. Contrast takes
// its region from the window's alpha mask, so at a low background opacity the only
// alpha left is the buttons' own drop shadows - whose soft gradients it quantises
// into jagged halos. An ordinary Window asks the compositor for nothing, so the
// overlay is exactly what it draws.
//
// Takes the applet root rather than a dozen individual properties: it is an
// internal part of the applet, and the alternative was mirroring most of the
// root's state through this file.
Window {
    id: overlay

    property var applet
    // Where this overlay belongs, in virtual desktop coordinates. The output itself
    // comes from the screen property the creator binds: geometry set before the
    // window first shows does not move it off the primary screen, and both
    // showFullScreen() and ScreenFromQWindow go by screen, so without it every
    // overlay stacked up on one monitor (#64).
    property rect screenGeometry

    signal closeRequested()

    function showOnItsScreen() {
        overlay.x = screenGeometry.x;
        overlay.y = screenGeometry.y;
        overlay.width = screenGeometry.width;
        overlay.height = screenGeometry.height;
        overlay.showFullScreen();
        overlay.raise();
    }

    flags: Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint
    // Transparent window plus a Rectangle for the tint: a plain Window has no
    // backgroundColor of its own.
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(overlay.applet.overlayBackgroundColor,
                        plasmoid.configuration.break_overlay_opacity / 100)
    }

    BreakOverlayContent {
        anchors.fill: parent
        applet: overlay.applet
        onCloseRequested: overlay.closeRequested()
    }
}
