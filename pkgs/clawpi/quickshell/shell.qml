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
    property bool flashing: false
    property real flashOpacity: 0.0
    property string previousState: "idle"

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

    // Flash animation: bright glow that fades out when agent finishes
    SequentialAnimation {
        id: flashAnim
        onStarted: { root.flashing = true; root.flashOpacity = 1.0; }
        onStopped: { root.flashing = false; root.flashOpacity = 0.0; root.borderColor = getColor("idle"); }

        NumberAnimation {
            target: root; property: "flashOpacity"
            from: 1.0; to: 0.0; duration: 800
            easing.type: Easing.OutCubic
        }
    }

    onCurrentStateChanged: {
        // Trigger flash when transitioning from an active state to idle
        if (currentState === "idle" && previousState !== "idle" && previousState !== "disconnected") {
            // Keep the previous state's color for the flash
            root.borderColor = getColor(previousState);
            flashAnim.start();
        } else {
            root.borderColor = getColor(currentState);
        }
        root.shouldPulse = getPulse(currentState);
        root.previousState = currentState;
    }

    property string stateFilePath: Quickshell.env("XDG_RUNTIME_DIR") + "/clawpi-state.json"

    // Poll state file via Process — FileView inotify doesn't reliably
    // detect writes from the Go daemon's os.WriteFile on all compositors.
    Timer {
        interval: 200; repeat: true; running: true
        onTriggered: stateReader.running = true
    }

    Process {
        id: stateReader
        command: ["cat", root.stateFilePath]
        stdout: SplitParser {
            onRead: function(line) { root.parseState(line); }
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

        // Border color helper: during flash, show solid color with flashOpacity;
        // during pulse, show animated gradient; otherwise solid borderColor
        function edgeColor(pp) {
            if (root.flashing) return Qt.rgba(root.borderColor.r, root.borderColor.g, root.borderColor.b, root.flashOpacity);
            if (root.shouldPulse) return root.sc(root.lightPhase, pp);
            return root.borderColor;
        }

        // Top edge
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 10
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;   color: win.edgeColor(0.0) }
                GradientStop { position: 0.25;  color: win.edgeColor(0.0625) }
                GradientStop { position: 0.5;   color: win.edgeColor(0.125) }
                GradientStop { position: 0.75;  color: win.edgeColor(0.1875) }
                GradientStop { position: 1.0;   color: win.edgeColor(0.25) }
            }
        }

        // Right edge
        Rectangle {
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: 10
            gradient: Gradient {
                GradientStop { position: 0.0;   color: win.edgeColor(0.25) }
                GradientStop { position: 0.25;  color: win.edgeColor(0.3125) }
                GradientStop { position: 0.5;   color: win.edgeColor(0.375) }
                GradientStop { position: 0.75;  color: win.edgeColor(0.4375) }
                GradientStop { position: 1.0;   color: win.edgeColor(0.5) }
            }
        }

        // Bottom edge
        Rectangle {
            id: bottomEdge
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 10
            transform: Scale { xScale: -1; origin.x: bottomEdge.width / 2 }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;   color: win.edgeColor(0.5) }
                GradientStop { position: 0.25;  color: win.edgeColor(0.5625) }
                GradientStop { position: 0.5;   color: win.edgeColor(0.625) }
                GradientStop { position: 0.75;  color: win.edgeColor(0.6875) }
                GradientStop { position: 1.0;   color: win.edgeColor(0.75) }
            }
        }

        // Left edge
        Rectangle {
            id: leftEdge
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: 10
            transform: Scale { yScale: -1; origin.y: leftEdge.height / 2 }
            gradient: Gradient {
                GradientStop { position: 0.0;   color: win.edgeColor(0.75) }
                GradientStop { position: 0.25;  color: win.edgeColor(0.8125) }
                GradientStop { position: 0.5;   color: win.edgeColor(0.875) }
                GradientStop { position: 0.75;  color: win.edgeColor(0.9375) }
                GradientStop { position: 1.0;   color: win.edgeColor(1.0) }
            }
        }

        // Agent response text — bottom center
        Rectangle {
            id: messageBox
            visible: root.message.length > 0 && root.currentState !== "idle"
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                bottomMargin: 40
            }
            width: Math.min(messageText.implicitWidth + 48, parent.width * 0.85)
            height: messageText.implicitHeight + 32
            radius: 16
            color: Qt.rgba(0, 0, 0, 0.75)

            Text {
                id: messageText
                anchors {
                    fill: parent
                    margins: 16
                    leftMargin: 24
                    rightMargin: 24
                }
                text: root.message
                color: "#e0e0e0"
                font.pixelSize: 18
                font.family: "sans-serif"
                wrapMode: Text.WordWrap
                maximumLineCount: 6
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                verticalAlignment: Text.AlignVCenter
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
