import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.private.kicker as Kicker

// One fullscreen break overlay. Instantiated once per screen, because a single
// window only covers the display it is on, which left every other monitor
// uncovered during a break (gitlab #19).
//
// Plain fullscreen window. The variant that also keeps the overlay on every virtual
// desktop is BreakOverlayLayer.qml, which adds the layer-shell properties on top of
// this file - that module is optional and missing on some distributions, so importing
// it here would take the whole applet down with it (gitlab #58).
//
// Still a DashboardWindow rather than a plain Window: it enables blur behind
// itself in C++, and there is no QML binding for KWindowEffects to do that by
// hand. Replacing it with a plain Window cost the blur, which is very visible
// once the background is translucent. The layer-shell properties attach to it
// just as well.
//
// Takes the applet root rather than a dozen individual properties: it is an
// internal part of the applet, and the alternative was mirroring most of the
// root's state through this file.
Kicker.DashboardWindow {
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

    flags: Qt.WindowStaysOnTopHint
    // Painted by the window rather than by a Rectangle on top of it: this is the
    // surface the compositor blurs behind, so its own alpha is what decides how
    // much of the desktop shows through.
    backgroundColor: Qt.alpha(overlay.applet.overlayBackgroundColor,
                                      plasmoid.configuration.break_overlay_opacity / 100)

    BreakOverlayContent {
        anchors.fill: parent
        applet: overlay.applet
        onCloseRequested: overlay.closeRequested()
    }
}
