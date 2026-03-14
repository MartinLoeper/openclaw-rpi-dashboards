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

    property int cycleMs: {
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

    property var stateHues: {
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

    property bool active: root.currentState !== "idle"

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

        Timer {
            id: animTimer
            interval: 33  // ~30fps
            repeat: true
            running: root.active
            onTriggered: {
                var step = interval / root.cycleMs;
                win.phase = (win.phase + step) % 1.0;
                borderCanvas.requestPaint();
            }
            onRunningChanged: {
                if (!running) win.phase = 0.0;
            }
        }

        Canvas {
            id: borderCanvas
            anchors.fill: parent
            visible: root.active

            onVisibleChanged: if (visible) requestPaint()

            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                if (!root.active) return;

                var hues = root.stateHues;
                var h0 = hues[0];
                var h1 = hues[1];
                var ph = win.phase;
                var isDisconnected = root.currentState === "disconnected";

                var coreWidth = 6;
                var glowWidth = 20;
                var halfCore = coreWidth / 2;

                var W = width;
                var H = height;
                var perim = 2 * (W + H);
                var segsPerEdge = 40;

                function hslColor(t, alpha) {
                    var p = (t + ph) % 1.0;
                    if (p < 0) p += 1.0;
                    var hue;
                    if (isDisconnected) {
                        hue = 0;
                    } else {
                        var cycle = (p * 3) % 1.0;
                        hue = h0 + (h1 - h0) * cycle;
                    }
                    var sat = isDisconnected ? 10 : 90;
                    var lum = isDisconnected ? 30 : 55;
                    if (alpha < 1.0) {
                        return "hsla(" + Math.round(hue) + "," + sat + "%," + lum + "%," + alpha + ")";
                    }
                    return "hsl(" + Math.round(hue) + "," + sat + "%," + lum + "%)";
                }

                function drawEdge(x1, y1, x2, y2, tStart, tEnd) {
                    var segLen = tEnd - tStart;
                    for (var i = 0; i < segsPerEdge; i++) {
                        var frac0 = i / segsPerEdge;
                        var frac1 = (i + 1) / segsPerEdge;
                        var t0 = tStart + segLen * frac0;
                        var t1 = tStart + segLen * frac1;
                        var cx0 = x1 + (x2 - x1) * frac0;
                        var cx1 = x1 + (x2 - x1) * frac1;
                        var cy0 = y1 + (y2 - y1) * frac0;
                        var cy1 = y1 + (y2 - y1) * frac1;

                        // Glow pass
                        ctx.strokeStyle = hslColor((t0 + t1) / 2, 0.2);
                        ctx.lineWidth = glowWidth;
                        ctx.beginPath();
                        ctx.moveTo(cx0, cy0);
                        ctx.lineTo(cx1, cy1);
                        ctx.stroke();

                        // Core pass
                        ctx.strokeStyle = hslColor((t0 + t1) / 2, 1.0);
                        ctx.lineWidth = coreWidth;
                        ctx.beginPath();
                        ctx.moveTo(cx0, cy0);
                        ctx.lineTo(cx1, cy1);
                        ctx.stroke();
                    }
                }

                // top: left → right
                drawEdge(0, halfCore, W, halfCore, 0, W / perim);
                // right: top → bottom
                drawEdge(W - halfCore, 0, W - halfCore, H, W / perim, (W + H) / perim);
                // bottom: right → left
                drawEdge(W, H - halfCore, 0, H - halfCore, (W + H) / perim, (2 * W + H) / perim);
                // left: bottom → top
                drawEdge(halfCore, H, halfCore, 0, (2 * W + H) / perim, 1.0);
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
                text: "Stop"
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
