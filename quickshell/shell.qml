import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

ShellRoot {
    id: root

    property string currentState: "idle"
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

    function parseStatus() {
        let content = statusFile.text();
        if (!content || content.trim() === "") {
            root.currentState = "idle";
            return;
        }
        root.currentState = content.trim();
    }

    function getColor(state) {
        switch(state) {
            case "thinking":      return "#2196F3";
            case "responding":    return "#00BCD4";
            case "tool_use":      return "#9C27B0";
            case "disconnected":  return "#F44336";
            default:              return "#333333";
        }
    }

    function getPulse(state) {
        return state === "thinking" || state === "responding" || state === "tool_use";
    }

    onCurrentStateChanged: {
        root.borderColor = getColor(currentState);
        root.shouldPulse = getPulse(currentState);
    }

    FileView {
        id: statusFile
        path: "/tmp/clawpi-status"
        watchChanges: true
        blockLoading: true

        onFileChanged: {
            statusFile.reload();
            root.parseStatus();
        }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            focusable: false
            color: "transparent"
            mask: Region {}

            // Top edge: pp 0.0→0.25 (increasing, left to right)
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

            // Right edge: pp 0.25→0.5 (increasing, top to bottom)
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

            // Bottom edge: pp 0.5→0.75 (INCREASING like all others), then mirrored with xScale
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

            // Left edge: pp 0.75→1.0 (increasing, bottom to top) - mirrored with yScale
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
        }
    }
}
