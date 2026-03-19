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

    property color borderColor: "#333333"
    property bool shouldPulse: false
    property real lightPhase: 0

    NumberAnimation {
        target: root
        property: "lightPhase"
        from: 0; to: 1
        duration: 2000
        loops: Animation.Infinite
        running: root.shouldPulse
    }

    function sc(lp, pp) {
        var bc = borderColor;
        var d = lp - pp;
        if (d > 0.5) d -= 1.0;
        if (d < -0.5) d += 1.0;
        var raw = (Math.cos(d * 2 * Math.PI) + 1) / 2;
        var t = 0.05 + 0.95 * Math.pow(raw, 3);
        return Qt.rgba(bc.r * t, bc.g * t, bc.b * t, 1.0);
    }

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

    function getColor(state) {
        switch(state) {
            case "thinking":     return "#2196F3";
            case "responding":   return "#00BCD4";
            case "tool_use":     return "#9C27B0";
            case "transcribing": return "#FF5722";
            case "delivering":   return "#00897B";
            case "error":        return "#F44336";
            case "disconnected": return "#F44336";
            default:             return "#333333";
        }
    }

    function getPulse(state) {
        switch(state) {
            case "thinking":
            case "responding":
            case "tool_use":
            case "transcribing":
            case "delivering":
            case "error":
                return true;
            default:
                return false;
        }
    }

    onCurrentStateChanged: {
        root.borderColor = getColor(currentState);
        root.shouldPulse = getPulse(currentState);
    }

    FileView {
        id: stateFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/clawpi-state.json"
        watchChanges: true
        blockLoading: true

        onFileChanged: {
            stateFile.reload();
            root.parseState(stateFile.text());
        }
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

        mask: Region {}

        // Top edge: pp 0.0 -> 0.25 (increasing, left to right)
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 10
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.0)    : root.borderColor }
                GradientStop { position: 0.25;  color: root.shouldPulse ? root.sc(root.lightPhase, 0.0625) : root.borderColor }
                GradientStop { position: 0.5;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.125)  : root.borderColor }
                GradientStop { position: 0.75;  color: root.shouldPulse ? root.sc(root.lightPhase, 0.1875) : root.borderColor }
                GradientStop { position: 1.0;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.25)   : root.borderColor }
            }
        }

        // Right edge: pp 0.25 -> 0.5 (increasing, top to bottom)
        Rectangle {
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: 10
            gradient: Gradient {
                GradientStop { position: 0.0;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.25)   : root.borderColor }
                GradientStop { position: 0.25;  color: root.shouldPulse ? root.sc(root.lightPhase, 0.3125) : root.borderColor }
                GradientStop { position: 0.5;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.375)  : root.borderColor }
                GradientStop { position: 0.75;  color: root.shouldPulse ? root.sc(root.lightPhase, 0.4375) : root.borderColor }
                GradientStop { position: 1.0;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.5)    : root.borderColor }
            }
        }

        // Bottom edge: pp 0.5 -> 0.75 (increasing, mirrored with xScale)
        Rectangle {
            id: bottomEdge
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 10
            transform: Scale { xScale: -1; origin.x: bottomEdge.width / 2 }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.5)    : root.borderColor }
                GradientStop { position: 0.25;  color: root.shouldPulse ? root.sc(root.lightPhase, 0.5625) : root.borderColor }
                GradientStop { position: 0.5;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.625)  : root.borderColor }
                GradientStop { position: 0.75;  color: root.shouldPulse ? root.sc(root.lightPhase, 0.6875) : root.borderColor }
                GradientStop { position: 1.0;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.75)   : root.borderColor }
            }
        }

        // Left edge: pp 0.75 -> 1.0 (increasing, mirrored with yScale)
        Rectangle {
            id: leftEdge
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: 10
            transform: Scale { yScale: -1; origin.y: leftEdge.height / 2 }
            gradient: Gradient {
                GradientStop { position: 0.0;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.75)   : root.borderColor }
                GradientStop { position: 0.25;  color: root.shouldPulse ? root.sc(root.lightPhase, 0.8125) : root.borderColor }
                GradientStop { position: 0.5;   color: root.shouldPulse ? root.sc(root.lightPhase, 0.875)  : root.borderColor }
                GradientStop { position: 0.75;  color: root.shouldPulse ? root.sc(root.lightPhase, 0.9375) : root.borderColor }
                GradientStop { position: 1.0;   color: root.shouldPulse ? root.sc(root.lightPhase, 1.0)    : root.borderColor }
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
