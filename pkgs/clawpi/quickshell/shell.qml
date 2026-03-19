import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

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
        } catch (e) {}
    }

    property color stateColor: {
        switch (root.currentState) {
            case "thinking":     return "#3b82f6"; // blue
            case "responding":   return "#22c55e"; // green
            case "transcribing": return "#ef4444"; // red
            case "delivering":   return "#06b6d4"; // cyan
            case "tool_use":     return "#f97316"; // orange
            case "error":        return "#dc2626"; // red
            case "disconnected": return "#6b7280"; // gray
            default:             return "transparent";
        }
    }

    property bool active: root.currentState !== "idle"
    property string stateFilePath: Quickshell.env("XDG_RUNTIME_DIR") + "/clawpi-state.json"

    // Poll state file via Process — FileView inotify doesn't reliably
    // detect writes from the Go daemon's os.WriteFile.
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

        property int borderWidth: 6

        // Top border
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: win.borderWidth
            color: root.stateColor
        }

        // Bottom border
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: win.borderWidth
            color: root.stateColor
        }

        // Left border
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: win.borderWidth
            color: root.stateColor
        }

        // Right border
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: win.borderWidth
            color: root.stateColor
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
