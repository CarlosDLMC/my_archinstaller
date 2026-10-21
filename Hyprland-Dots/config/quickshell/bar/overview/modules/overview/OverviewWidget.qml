import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../common"
import "../../common/functions"
import "../../common/widgets"
import "../../services"
import "../../.."
import "."

Item {
    id: root
    required property var panelWindow
    // This monitor as mango reports it: name, x, y, width, height (logical),
    // scale, active_tags.
    readonly property var monitor: Mango.monitor(panelWindow.screen ? panelWindow.screen.name : "")
    readonly property int activeWorkspace: (monitor && monitor.active_tags.length > 0) ? monitor.active_tags[0] : 1
    readonly property int workspacesShown: Config.options.overview.rows * Config.options.overview.columns
    readonly property int workspaceGroup: Math.floor((activeWorkspace - 1) / workspacesShown)
    property bool monitorIsFocused: !!monitor && Mango.focusedMonitorName === monitor.name
    property var windows: MangoData.windowList
    property real scale: Config.options.overview.scale
    property color activeBorderColor: Appearance.colors.colSecondary

    // The work area a workspace shows: the monitor below the bar. The bar is
    // 34 px tall, scaled down on narrow screens as shell.qml does it.
    readonly property real monitorWidth: monitor ? monitor.width : 1920
    readonly property real monitorHeight: monitor ? monitor.height : 1080
    readonly property real reservedTop: Math.round(34 * Math.max(0.9, Math.min(1.0, monitorWidth / 2560)))

    property real workspaceImplicitWidth: monitorWidth * root.scale
    property real workspaceImplicitHeight: (monitorHeight - reservedTop) * root.scale

    property real workspaceNumberMargin: 80
    property real workspaceNumberSize: 250 * (monitor ? monitor.scale : 1)
    property int workspaceZ: 0
    property int windowZ: 1
    property int windowDraggingZ: 99999
    property real workspaceSpacing: 5

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    // A window's workspace: the first of its tags (mango lets a window sit on
    // several; 0 is the special workspace, which the overview leaves out).
    function workspaceOf(win) {
        return (win && win.tags && win.tags.length > 0) ? win.tags[0] : 0
    }

    implicitWidth: overviewBackground.implicitWidth + Appearance.sizes.elevationMargin * 2
    implicitHeight: overviewBackground.implicitHeight + Appearance.sizes.elevationMargin * 2

    property Component windowComponent: OverviewWindow {}
    property list<OverviewWindow> windowWidgets: []

    StyledRectangularShadow {
        target: overviewBackground
    }
    Rectangle { // Background
        id: overviewBackground
        property real padding: 10
        anchors.fill: parent
        anchors.margins: Appearance.sizes.elevationMargin

        implicitWidth: workspaceColumnLayout.implicitWidth + padding * 2
        implicitHeight: workspaceColumnLayout.implicitHeight + padding * 2
        // Concentric with the workspaces' corners - and square when they are.
        radius: Appearance.rounding.screenRounding > 0 ? Appearance.rounding.screenRounding * root.scale + padding : 0
        color: Appearance.colors.colLayer0
        border.width: 1
        border.color: Appearance.colors.colLayer0Border

        ColumnLayout { // Workspaces
            id: workspaceColumnLayout

            z: root.workspaceZ
            anchors.centerIn: parent
            spacing: workspaceSpacing
            Repeater {
                model: Config.options.overview.rows
                delegate: RowLayout {
                    id: row
                    property int rowIndex: index
                    spacing: workspaceSpacing

                    Repeater { // Workspace repeater
                        model: Config.options.overview.columns
                        Rectangle { // Workspace
                            id: workspace
                            property int colIndex: index
                            property int workspaceValue: root.workspaceGroup * workspacesShown + rowIndex * Config.options.overview.columns + colIndex + 1
                            property color defaultWorkspaceColor: Appearance.colors.colLayer1
                            property color hoveredWorkspaceColor: ColorUtils.mix(defaultWorkspaceColor, Appearance.colors.colLayer1Hover, 0.1)
                            property color hoveredBorderColor: Appearance.colors.colLayer2Hover
                            property bool hoveredWhileDragging: false

                            implicitWidth: root.workspaceImplicitWidth
                            implicitHeight: root.workspaceImplicitHeight
                            color: hoveredWhileDragging ? hoveredWorkspaceColor : defaultWorkspaceColor
                            radius: Appearance.rounding.screenRounding * root.scale
                            border.width: 2
                            border.color: hoveredWhileDragging ? hoveredBorderColor : "transparent"

                            StyledText {
                                anchors.centerIn: parent
                                text: workspaceValue
                                font {
                                    pixelSize: root.workspaceNumberSize * root.scale
                                    weight: Font.DemiBold
                                    family: Appearance.font.family.expressive
                                }
                                color: ColorUtils.transparentize(Appearance.colors.colOnLayer1, 0.8)
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            MouseArea {
                                id: workspaceArea
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: {
                                    if (root.draggingTargetWorkspace === -1) {
                                        GlobalStates.overviewOpen = false
                                        Mango.dispatch("viewcrossmon," + workspaceValue + ",^" + root.monitor.name + "$")
                                    }
                                }
                            }

                            DropArea {
                                anchors.fill: parent
                                onEntered: {
                                    root.draggingTargetWorkspace = workspaceValue
                                    if (root.draggingFromWorkspace == root.draggingTargetWorkspace) return;
                                    hoveredWhileDragging = true
                                }
                                onExited: {
                                    hoveredWhileDragging = false
                                    if (root.draggingTargetWorkspace == workspaceValue) root.draggingTargetWorkspace = -1
                                }
                            }

                        }
                    }
                }
            }
        }

        Item { // Windows & focused workspace indicator
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: workspaceColumnLayout.implicitWidth
            implicitHeight: workspaceColumnLayout.implicitHeight

            Repeater { // Window repeater
                model: ScriptModel {
                    values: {
                        const lo = root.workspaceGroup * root.workspacesShown
                        const hi = (root.workspaceGroup + 1) * root.workspacesShown
                        return root.windows.filter(win => {
                            const ws = root.workspaceOf(win)
                            return root.monitor && win.monitor === root.monitor.name
                                && !win.is_minimized && lo < ws && ws <= hi
                        }).sort((a, b) => {
                            // Stacking order: windows on every workspace on top,
                            // then floating over tiled, then the focused one last.
                            if (a.is_global !== b.is_global)
                                return a.is_global ? 1 : -1
                            if (a.is_floating !== b.is_floating)
                                return a.is_floating ? 1 : -1
                            if (a.is_focused !== b.is_focused)
                                return a.is_focused ? 1 : -1
                            return 0
                        })
                    }
                }
                delegate: OverviewWindow {
                    id: window
                    required property var modelData
                    required property int index
                    windowData: modelData
                    monitorData: root.monitor
                    reservedTop: root.reservedTop

                    scale: root.scale
                    availableWorkspaceWidth: root.workspaceImplicitWidth
                    availableWorkspaceHeight: root.workspaceImplicitHeight

                    property bool atInitPosition: (initX == x && initY == y)

                    // A drag takes x/y over (the binding to initX/initY is gone),
                    // so whenever mango's list comes in again - after a drop, the
                    // window has moved to its new workspace - put the tile back
                    // where the window is. Not while it is being dragged.
                    onWindowDataChanged: {
                        if (!window.Drag.active) {
                            window.x = window.initX
                            window.y = window.initY
                        }
                    }

                    property int workspaceColIndex: (root.workspaceOf(windowData) - 1) % Config.options.overview.columns
                    property int workspaceRowIndex: Math.floor((root.workspaceOf(windowData) - 1) % root.workspacesShown / Config.options.overview.columns)
                    xOffset: (root.workspaceImplicitWidth + workspaceSpacing) * workspaceColIndex
                    yOffset: (root.workspaceImplicitHeight + workspaceSpacing) * workspaceRowIndex

                    z: atInitPosition ? (root.windowZ + index) : root.windowDraggingZ
                    Drag.hotSpot.x: targetWindowWidth / 2
                    Drag.hotSpot.y: targetWindowHeight / 2
                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: hovered = true
                        onExited: hovered = false
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        drag.target: parent
                        onPressed: (mouse) => {
                            root.draggingFromWorkspace = root.workspaceOf(windowData)
                            window.pressed = true
                            window.Drag.active = true
                            window.Drag.source = window
                            window.Drag.hotSpot.x = mouse.x
                            window.Drag.hotSpot.y = mouse.y
                        }
                        onReleased: {
                            const targetWorkspace = root.draggingTargetWorkspace
                            window.pressed = false
                            window.Drag.active = false
                            root.draggingFromWorkspace = -1
                            if (targetWorkspace !== -1 && targetWorkspace !== root.workspaceOf(windowData)) {
                                // The window list streams in again with its new
                                // workspace, which moves this tile there.
                                Mango.dispatch("tagsilent," + targetWorkspace, windowData.id)
                            }
                            else {
                                window.x = window.initX
                                window.y = window.initY
                            }
                        }
                        onClicked: (event) => {
                            if (!windowData) return;

                            if (event.button === Qt.LeftButton) {
                                GlobalStates.overviewOpen = false
                                Mango.dispatch("focusid", windowData.id)
                                event.accepted = true
                            } else if (event.button === Qt.MiddleButton) {
                                Mango.dispatch("killclient", windowData.id)
                                event.accepted = true
                            }
                        }

                        StyledToolTip {
                            extraVisibleCondition: false
                            alternativeVisibleCondition: dragArea.containsMouse && !window.Drag.active
                            text: `${windowData?.title ?? "Unknown"}\n[${windowData?.appid ?? "unknown"}] ${windowData?.is_xwayland ? "[XWayland] " : ""}`
                        }
                    }
                }
            }

            Rectangle { // Focused workspace indicator
                id: focusedWorkspaceIndicator
                property int activeWorkspaceInGroup: root.activeWorkspace - (root.workspaceGroup * root.workspacesShown)
                property int activeWorkspaceRowIndex: Math.floor((activeWorkspaceInGroup - 1) / Config.options.overview.columns)
                property int activeWorkspaceColIndex: (activeWorkspaceInGroup - 1) % Config.options.overview.columns
                x: (root.workspaceImplicitWidth + workspaceSpacing) * activeWorkspaceColIndex
                y: (root.workspaceImplicitHeight + workspaceSpacing) * activeWorkspaceRowIndex
                z: root.windowZ
                width: root.workspaceImplicitWidth
                height: root.workspaceImplicitHeight
                color: "transparent"
                radius: Appearance.rounding.screenRounding * root.scale
                border.width: 2
                border.color: root.activeBorderColor
                Behavior on x {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on y {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }
}
