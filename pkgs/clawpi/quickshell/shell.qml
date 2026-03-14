import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls

ShellRoot {
    id: root

    property string currentState: "idle"
    property bool ttsPlaying: false
    property bool recording: false
    property string toolName: ""
    property string message: ""

    function parseState(str) {
        if (!str || str.length === 0) return;
        try {
            var obj = JSON.parse(str);
            root.currentState = obj.state || "idle";
            root.ttsPlaying = obj.ttsPlaying || false;
            root.recording = obj.recording || false;
            root.toolName = obj.toolName || "";
            root.message = obj.message || "";
        } catch (e) {
            console.log("clawpi: failed to parse state JSON:", e);
        }
    }

    function cycleMs() {
        switch (root.currentState) {
            case "thinking":     return 4000;
            case "responding":   return 2000;
            case "transcribing": return 1500;
            case "delivering":   return 2500;
            case "tool_use":     return 2000;
            case "error":        return 1000;
            case "disconnected": return 6000;
            default:             return 4000;
        }
    }

    // hue0 and hue1 in degrees (0-360)
    function stateHues() {
        switch (root.currentState) {
            case "thinking":     return [220, 280];
            case "responding":   return [140, 200];
            case "transcribing": return [0,   40];
            case "delivering":   return [180, 220];
            case "tool_use":     return [30,  60];
            case "error":        return [0,   20];
            case "disconnected": return [0,   0];
            default:             return [220, 280];
        }
    }

    FileView {
        id: stateFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/clawpi-state.json"
        watchChanges: true
        preload: true
        onFileChanged: root.parseState(stateFile.text())
    }

    PanelWindow {
        id: win
        anchors {
            left: true
            right: true
            top: true
            bottom: true
        }
        exclusiveZone: -1
        color: "transparent"

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        property real phase: 0.0

        NumberAnimation on phase {
            id: phaseAnim
            from: 0.0
            to: 1.0
            duration: root.cycleMs()
            loops: Animation.Infinite
            running: root.currentState !== "idle"
            onRunningChanged: {
                if (!running) win.phase = 0.0;
                else duration = root.cycleMs();
            }
        }

        // Re-trigger duration update when state changes
        onWidthChanged: borderCanvas.requestPaint()
        onHeightChanged: borderCanvas.requestPaint()

        Connections {
            target: root
            function onCurrentStateChanged() {
                phaseAnim.duration = root.cycleMs();
                borderCanvas.requestPaint();
            }
        }

        Canvas {
            id: borderCanvas
            anchors.fill: parent
            visible: root.currentState !== "idle"

            // Repaint whenever phase ticks
            property real phase: win.phase
            onPhaseChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                if (root.currentState === "idle") return;

                var hues = root.stateHues();
                var h0 = hues[0];
                var h1 = hues[1];
                var ph = win.phase;
                var isDisconnected = root.currentState === "disconnected";

                var coreWidth = 8;
                var glowWidth = 24;
                var halfCore = coreWidth / 2;
                var halfGlow = glowWidth / 2;

                // Perimeter segments: top, right, bottom, left
                // total perimeter = 2*(w+h)
                var W = width;
                var H = height;
                var perim = 2 * (W + H);

                // Helper: get color at normalized position t (0-1 around perimeter)
                // offset by phase so it flows
                function colorAt(t) {
                    var p = (t + ph) % 1.0;
                    // map p into hue range
                    var hue;
                    if (isDisconnected) {
                        hue = 0;
                    } else {
                        // repeat the hue band 3 times around perimeter for visual richness
                        var cycle = (p * 3) % 1.0;
                        hue = h0 + (h1 - h0) * cycle;
                    }
                    var sat = isDisconnected ? 10 : 90;
                    var lum = isDisconnected ? 30 : 55;
                    return "hsl(" + Math.round(hue) + "," + sat + "%," + lum + "%)";
                }

                function glowColorAt(t) {
                    var p = (t + ph) % 1.0;
                    var hue;
                    if (isDisconnected) {
                        hue = 0;
                    } else {
                        var cycle = (p * 3) % 1.0;
                        hue = h0 + (h1 - h0) * cycle;
                    }
                    var sat = isDisconnected ? 10 : 80;
                    return "hsla(" + Math.round(hue) + "," + sat + "%,50%,0.25)";
                }

                // Draw a gradient strip along a line from (x1,y1) to (x2,y2)
                // tStart/tEnd: normalized perimeter position of this segment
                function drawEdge(x1, y1, x2, y2, tStart, tEnd, isHoriz) {
                    var steps = Math.max(Math.round(isHoriz ? Math.abs(x2-x1) : Math.abs(y2-y1)), 4);
                    var segLen = tEnd - tStart;
                    for (var i = 0; i < steps; i++) {
                        var t0 = tStart + segLen * (i / steps);
                        var t1 = tStart + segLen * ((i + 1) / steps);
                        var cx0 = x1 + (x2 - x1) * (i / steps);
                        var cx1 = x1 + (x2 - x1) * ((i + 1) / steps);
                        var cy0 = y1 + (y2 - y1) * (i / steps);
                        var cy1 = y1 + (y2 - y1) * ((i + 1) / steps);

                        var grad = ctx.createLinearGradient(cx0, cy0, cx1, cy1);
                        grad.addColorStop(0, colorAt(t0));
                        grad.addColorStop(1, colorAt(t1));

                        var glowGrad = ctx.createLinearGradient(cx0, cy0, cx1, cy1);
                        glowGrad.addColorStop(0, glowColorAt(t0));
                        glowGrad.addColorStop(1, glowColorAt(t1));

                        // Glow pass (wide, dim)
                        ctx.strokeStyle = glowGrad;
                        ctx.lineWidth = glowWidth;
                        ctx.beginPath();
                        ctx.moveTo(cx0, cy0);
                        ctx.lineTo(cx1, cy1);
                        ctx.stroke();

                        // Core pass (narrow, bright)
                        ctx.strokeStyle = grad;
                        ctx.lineWidth = coreWidth;
                        ctx.beginPath();
                        ctx.moveTo(cx0, cy0);
                        ctx.lineTo(cx1, cy1);
                        ctx.stroke();
                    }
                }

                // top edge: left→right
                drawEdge(0, halfCore, W, halfCore, 0, W/perim, true);
                // right edge: top→bottom
                drawEdge(W - halfCore, 0, W - halfCore, H, W/perim, (W+H)/perim, false);
                // bottom edge: right→left
                drawEdge(W, H - halfCore, 0, H - halfCore, (W+H)/perim, (W+2*H)/perim, true);
                // left edge: bottom→top
                drawEdge(halfCore, H, halfCore, 0, (W+2*H)/perim, 1.0, false);
            }
        }

        // Recording badge — top-left red dot
        Rectangle {
            visible: root.recording
            width: 16
            height: 16
            radius: 8
            color: "#ff2222"
            anchors {
                top: parent.top
                left: parent.left
                topMargin: 16
                leftMargin: 16
            }

            SequentialAnimation on opacity {
                loops: Animation.Infinite
                running: root.recording
                NumberAnimation { to: 0.3; duration: 600 }
                NumberAnimation { to: 1.0; duration: 600 }
            }
        }

        // TTS stop button — bottom-right
        Rectangle {
            id: ttsStopBtn
            visible: root.ttsPlaying
            width: 120
            height: 44
            radius: 10
            color: "#cc2222"
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: 16
                rightMargin: 16
            }

            Text {
                anchors.centerIn: parent
                text: "⏹ Stop"
                color: "white"
                font.pixelSize: 18
                font.family: "sans-serif"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {
                    var xhr = new XMLHttpRequest();
                    xhr.open("POST", "http://localhost:3100/api/tts/stop");
                    xhr.send();
                }
            }
        }
    }
}
