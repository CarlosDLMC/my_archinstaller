import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../common"
import "../../services"
import "../../.."
import "."

// The workspace overview (SUPER+A, three fingers up): a grid of this monitor's
// workspaces with a picture of every window in it. Part of the bar - it used
// to be a second quickshell (`qs -c overview`) that stayed running for the
// rest of the session after its first use.
Scope {
    id: overviewScope
    Variants {
        id: overviewVariants
        model: Quickshell.screens
        PanelWindow {
            id: root
            required property var modelData
            readonly property var monitor: Mango.monitor(modelData ? modelData.name : "")
            property bool monitorIsFocused: !!monitor && Mango.focusedMonitorName === monitor.name
            screen: modelData
            visible: GlobalStates.overviewOpen

            WlrLayershell.namespace: "quickshell:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            mask: Region {
                item: GlobalStates.overviewOpen ? keyHandler : null
            }

            // The whole screen, so a click beside the panel lands here and
            // closes it - Hyprland's focus grab did that before. The panel
            // itself is a strip of its own width down the middle, as the
            // surface used to be.
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                anchors.fill: parent
                enabled: GlobalStates.overviewOpen
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: mouse => {
                    const half = columnLayout.implicitWidth / 2
                    const centre = width / 2
                    if (mouse.x < centre - half || mouse.x > centre + half)
                        GlobalStates.overviewOpen = false
                }
            }

            Item {
                id: keyHandler
                anchors.fill: parent
                visible: GlobalStates.overviewOpen
                focus: GlobalStates.overviewOpen

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Return) {
                        GlobalStates.overviewOpen = false;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Up || event.key === Qt.Key_Down) {
                        const workspacesPerGroup = Config.options.overview.rows * Config.options.overview.columns;
                        const focused = Mango.focusedMonitor;
                        const currentId = (focused && focused.active_tags.length > 0) ? focused.active_tags[0] : 1;
                        const currentGroup = Math.floor((currentId - 1) / workspacesPerGroup);
                        const minWorkspaceId = currentGroup * workspacesPerGroup + 1;
                        const maxWorkspaceId = minWorkspaceId + workspacesPerGroup - 1;

                        let targetId;
                        if (event.key === Qt.Key_Left) {
                            targetId = currentId - 1;
                            if (targetId < minWorkspaceId) targetId = maxWorkspaceId;
                        } else if (event.key === Qt.Key_Right) {
                            targetId = currentId + 1;
                            if (targetId > maxWorkspaceId) targetId = minWorkspaceId;
                        } else if (event.key === Qt.Key_Up) {
                            targetId = currentId - Config.options.overview.columns;
                            if (targetId < minWorkspaceId) targetId += workspacesPerGroup;
                        } else {
                            targetId = currentId + Config.options.overview.columns;
                            if (targetId > maxWorkspaceId) targetId -= workspacesPerGroup;
                        }

                        Mango.dispatch("view," + targetId + ",0");
                        event.accepted = true;
                    }
                }
            }

            ColumnLayout {
                id: columnLayout
                visible: GlobalStates.overviewOpen
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: 100
                }

                Loader {
                    id: overviewLoader
                    active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                    sourceComponent: OverviewWidget {
                        panelWindow: root
                        visible: true
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "overview"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
    }
}
