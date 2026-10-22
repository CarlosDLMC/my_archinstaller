import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// CRT power-off. Every monitor's picture folds into a bright horizontal line,
// the line draws in to a point, and the point dies away like phosphor - the way
// a tube set switched off. The screen then stays black until the session ends.
//
// Not part of the bar: hypr/scripts/CrtOff.sh starts this (`qs -c crt`) in front
// of the «ПУСК · ПУЛЬТ» menu's logout, reboot and power-off commands, after
// putting one frame of each monitor in $XDG_RUNTIME_DIR/crt-off/<name>.ppm.
// mango shows the layer without an animation (quickshell:crt in
// ~/.config/mango/rules.conf), so it lands exactly on the frame it shows.
ShellRoot {
    id: root

    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/crt-off"

    // Tells CrtOff.sh the picture is gone and the real command can run.
    Process { id: done; command: ["touch", root.dir + "/done"] }

    // If the machine has not gone down by now, something refused it: give the
    // desktop back rather than leave a black screen.
    Timer { interval: 30000; running: true; onTriggered: Qt.quit() }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:crt"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "black"

            // No pointer over the picture while it collapses.
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.BlankCursor
            }

            Item {
                id: tube
                anchors.fill: parent
                transform: Scale { id: squash; origin.x: tube.width / 2; origin.y: tube.height / 2 }

                Image {
                    anchors.fill: parent
                    source: "file://" + root.dir + "/" + win.modelData.name + ".ppm"
                    asynchronous: false
                    cache: false
                }
                // The beam brightening as the picture squeezes into it.
                Rectangle { id: flare; anchors.fill: parent; color: "white"; opacity: 0 }
            }

            // The last point of light and its glow.
            Item {
                id: dot
                anchors.centerIn: parent
                width: 32; height: 32
                opacity: 0
                Rectangle { anchors.centerIn: parent; width: 32; height: 32; radius: 16; color: "white"; opacity: 0.22 }
                Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "white" }
            }

            SequentialAnimation {
                id: off
                ParallelAnimation {
                    NumberAnimation { target: squash; property: "yScale"; to: 0.004; duration: 140; easing.type: Easing.InQuad }
                    NumberAnimation { target: flare; property: "opacity"; to: 1; duration: 140; easing.type: Easing.InQuad }
                }
                NumberAnimation { target: squash; property: "xScale"; to: 0.004; duration: 160; easing.type: Easing.InQuad }
                ScriptAction { script: { tube.visible = false; dot.opacity = 1 } }
                NumberAnimation { target: dot; property: "opacity"; to: 0; duration: 450; easing.type: Easing.OutQuad }
                ScriptAction { script: done.running = true }
            }

            // A beat after mapping, so the first frame of the collapse is on screen.
            Timer { interval: 60; running: true; onTriggered: off.start() }
        }
    }
}
