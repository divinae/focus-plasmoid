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
    // override them still follows the active theme. colorBackground is the track
    // drawn behind the arc, so it has to be a dimmed foreground rather than the
    // surface colour - against the surface it would be invisible by definition.
    property color colorCircle: Kirigami.Theme.highlightColor
    property color colorBackground: Qt.alpha(Kirigami.Theme.textColor, 0.12)
    // A session with nothing to count toward - a flowmodoro flow, or a break running
    // past its end - has no fraction to draw. Rather than a full or empty ring, which
    // both read as a definite state, the arc sweeps to say "still going".
    //
    // The motion follows Material's circular indicator, whose constants come from
    // Compose's CircularProgressIndicator: per 1332ms cycle the head races 290 degrees
    // ahead, then the tail follows the same 290, all over a linear base rotation of
    // 286 degrees. So the arc stretches and contracts rather than holding one length.
    //
    // Head and tail both finish a cycle at 290, making the arc zero-length exactly
    // when the cycle resets them to 0 - which is what hides the reset, and why the
    // base rotation may jump back by (286 - 216) degrees there unseen.
    property bool indeterminate: false
    // Held back from full strength: the sweep is a background reassurance that the
    // session is running, not something to pull the eye away from the countdown.
    property real indeterminateOpacity: 0.55
    // Material's own cycle is 1332ms. Slowed here: on a dial this large a fast sweep
    // draws the eye away from the countdown, which is the thing worth reading. The
    // proportions - half the cycle for the head, half for the tail - are unchanged.
    readonly property int indCycleDuration: 2600
    readonly property int indHalfCycle: Math.round(indCycleDuration / 2)
    readonly property real indJump: 290
    readonly property real indBaseSpan: 286
    readonly property real indCycleStep: (indBaseSpan + indJump) % 360

    // Leading edge, trailing edge, and the two rotations that carry them.
    property real indHead: 0
    property real indTail: 0
    property real indBase: 0
    property real indCycleOffset: 0
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
    onIndeterminateChanged: canvas.requestPaint()
    onIndeterminateOpacityChanged: canvas.requestPaint()
    // Unlike the fixed sweep this replaced, the arc changes shape every frame, so the
    // canvas genuinely has to repaint as the edges move. The rotations below stay
    // transforms and cost nothing.
    onIndHeadChanged: if (indeterminate)
        canvas.requestPaint()
    onIndTailChanged: if (indeterminate)
        canvas.requestPaint()
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
                  + (root.indeterminate ? root.indBase + root.indCycleOffset : 0)
        onPaint: {
            var ctx = getContext("2d");
            var x = width / 2;
            var y = height / 2;
            // While indeterminate the edges come from the Material motion below; the
            // rotations are applied to the canvas, not to these angles.
            var beginDeg = root.indeterminate ? root.indTail : parent.arcBegin;
            var endDeg = root.indeterminate ? root.indHead : parent.arcEnd;
            // Clamped: with a line wider than the circle, or before the item has been given
            // a size, this goes negative and every paint logs "Incorrect argument radius" -
            // 702 of them in one session before it was caught.
            var outer = Math.max(0, width / 2);
            var inner = Math.max(0, width / 2 - root.lineWidth / 2);
            var start = Math.PI * (beginDeg / 180);
            var end = Math.PI * (endDeg / 180);
            ctx.reset();
            if (root.isPie) {
                if (root.showBackground) {
                    ctx.beginPath();
                    ctx.fillStyle = root.colorBackground;
                    ctx.moveTo(x, y);
                    ctx.arc(x, y, outer, 0, Math.PI * 2, false);
                    ctx.lineTo(x, y);
                    ctx.fill();
                }
                ctx.beginPath();
                // Dimmed while indeterminate for the same reason as the arc below: a
                // full-strength wedge sweeping past reads as progress being made.
                ctx.fillStyle = root.indeterminate
                    ? Qt.alpha(root.colorCircle, root.indeterminateOpacity)
                    : root.colorCircle;
                ctx.moveTo(x, y);
                ctx.arc(x, y, outer, start, end, false);
                ctx.lineTo(x, y);
                ctx.fill();
            } else {
                if (root.showBackground) {
                    ctx.beginPath();
                    ctx.arc(x, y, inner, 0, Math.PI * 2, false);
                    ctx.lineWidth = root.lineWidth;
                    ctx.strokeStyle = root.colorBackground;
                    ctx.stroke();
                }
                ctx.beginPath();
                ctx.arc(x, y, inner, start, end, false);
                ctx.lineWidth = root.lineWidth;
                // ctx.reset() above clears this, so it has to be set every paint.
                // Only the progress arc needs it; the track is a closed circle
                // and has no ends to round.
                ctx.lineCap = "round";
                ctx.strokeStyle = root.indeterminate
                    ? Qt.alpha(root.colorCircle, root.indeterminateOpacity)
                    : root.colorCircle;
                ctx.stroke();
            }
        }
    }

    // Linear, so the whole figure turns at a constant rate while the arc breathes.
    NumberAnimation on indBase {
        running: root.indeterminate && root.visible
        loops: Animation.Infinite
        from: 0
        to: root.indBaseSpan
        duration: root.indCycleDuration
    }

    SequentialAnimation {
        running: root.indeterminate && root.visible
        loops: Animation.Infinite

        // Material's easing for both edges: a standard-decelerate cubic bezier.
        NumberAnimation {
            target: root
            property: "indHead"
            from: 0
            to: root.indJump
            duration: root.indHalfCycle
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
        }

        NumberAnimation {
            target: root
            property: "indTail"
            from: 0
            to: root.indJump
            duration: root.indHalfCycle
            easing.type: Easing.Bezier
            easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
        }

        ScriptAction {
            script: {
                root.indHead = 0;
                root.indTail = 0;
                root.indCycleOffset = (root.indCycleOffset + root.indCycleStep) % 360;
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
