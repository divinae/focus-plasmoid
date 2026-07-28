// ByteBau (Jörn Buchholz) @bytebau.com

import QtQml 2.2
import QtQuick 2.0
import org.kde.kirigami as Kirigami

Item {
    id: root

    property int size: 200 // The size of the circle in pixel
    property real arcBegin: 0 // start arc angle in degree
    property real arcEnd: 270 // end arc angle in degree
    property real arcOffset: 0 // rotation
    property bool isPie: false // paint a pie instead of an arc
    property bool showBackground: false // a full circle as a background of the arc
    property real lineWidth: 20 // width of the line
    // Defaults come from the Plasma colour scheme, so an instance that does not
    // override them still follows the active theme.
    property color colorCircle: Kirigami.Theme.highlightColor
    property color colorBackground: Kirigami.Theme.backgroundColor
    property alias beginAnimation: animationArcBegin.enabled
    property alias endAnimation: animationArcEnd.enabled
    property int animationDuration: 200

    function requestPaint() {
        canvas.requestPaint();
    }

    width: size
    height: size
    // Canvas does not repaint by itself, so every property the paint handler
    // reads has to ask for one. Without the colour and geometry handlers a
    // theme change - or the focus/break colour swap - left the old pixels up
    // until the arc happened to move.
    onArcBeginChanged: canvas.requestPaint()
    onArcEndChanged: canvas.requestPaint()
    onColorCircleChanged: canvas.requestPaint()
    onColorBackgroundChanged: canvas.requestPaint()
    onLineWidthChanged: canvas.requestPaint()
    onIsPieChanged: canvas.requestPaint()
    onShowBackgroundChanged: canvas.requestPaint()

    Canvas {
        id: canvas

        anchors.fill: parent
        rotation: -90 + parent.arcOffset
        onPaint: {
            var ctx = getContext("2d");
            var x = width / 2;
            var y = height / 2;
            var start = Math.PI * (parent.arcBegin / 180);
            var end = Math.PI * (parent.arcEnd / 180);
            ctx.reset();
            if (root.isPie) {
                if (root.showBackground) {
                    ctx.beginPath();
                    ctx.fillStyle = root.colorBackground;
                    ctx.moveTo(x, y);
                    ctx.arc(x, y, width / 2, 0, Math.PI * 2, false);
                    ctx.lineTo(x, y);
                    ctx.fill();
                }
                ctx.beginPath();
                ctx.fillStyle = root.colorCircle;
                ctx.moveTo(x, y);
                ctx.arc(x, y, width / 2, start, end, false);
                ctx.lineTo(x, y);
                ctx.fill();
            } else {
                if (root.showBackground) {
                    ctx.beginPath();
                    ctx.arc(x, y, (width / 2) - parent.lineWidth / 2, 0, Math.PI * 2, false);
                    ctx.lineWidth = root.lineWidth;
                    ctx.strokeStyle = root.colorBackground;
                    ctx.stroke();
                }
                ctx.beginPath();
                ctx.arc(x, y, (width / 2) - parent.lineWidth / 2, start, end, false);
                ctx.lineWidth = root.lineWidth;
                ctx.strokeStyle = root.colorCircle;
                ctx.stroke();
            }
        }
    }

    Behavior on arcBegin {
        id: animationArcBegin

        enabled: true

        NumberAnimation {
            duration: root.animationDuration
            easing.type: Easing.InOutCubic
        }

    }

    Behavior on arcEnd {
        id: animationArcEnd

        enabled: true

        NumberAnimation {
            duration: root.animationDuration
            easing.type: Easing.InOutCubic
        }

    }

}
