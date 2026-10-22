import QtQuick.Effects
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../common"
import "../../common/functions"
import "../../services"

Item { // Window
    id: root
    property var windowData
    property var monitorData
    property real reservedTop: 0
    property var scale
    property var availableWorkspaceWidth
    property var availableWorkspaceHeight
    property bool restrictToWorkspace: true
    property real initX: Math.max(((windowData?.x ?? 0) - (monitorData?.x ?? 0)) * root.scale, 0) + xOffset
    property real initY: Math.max(((windowData?.y ?? 0) - (monitorData?.y ?? 0) - reservedTop) * root.scale, 0) + yOffset
    property real xOffset: 0
    property real yOffset: 0

    property var targetWindowWidth: (windowData?.width ?? 100) * scale
    property var targetWindowHeight: (windowData?.height ?? 100) * scale
    property bool hovered: false
    property bool pressed: false

    property var iconToWindowRatio: 0.25
    property var xwaylandIndicatorToIconRatio: 0.35
    property var iconToWindowRatioCompact: 0.45
    property var entry: DesktopEntries.heuristicLookup(windowData?.appid)
    property var iconPath: Quickshell.iconPath(entry?.icon ?? windowData?.appid ?? "application-x-executable", "image-missing")
    property bool compactMode: Appearance.font.pixelSize.smaller * 4 > targetWindowHeight || Appearance.font.pixelSize.smaller * 4 > targetWindowWidth

    property bool indicateXWayland: windowData?.is_xwayland ?? false

    x: initX
    y: initY
    width: Math.min((windowData?.width ?? 100) * root.scale, availableWorkspaceWidth)
    height: Math.min((windowData?.height ?? 100) * root.scale, availableWorkspaceHeight)

    layer.enabled: true
    layer.smooth: true
    layer.mipmap: true

    Behavior on x {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    Rectangle {
        id: clipContainer
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding * root.scale
        clip: true
        color: "transparent"

        // A still of the window, taken when the overview opened
        // (MangoData.takeShots). Until it is on disk - or for a window that
        // could not be captured - the tile shows just the app's icon.
        Image {
            id: windowPreview
            anchors.fill: parent
            asynchronous: true
            cache: false
            smooth: true
            mipmap: true
            source: (GlobalStates.overviewOpen && MangoData.shotGeneration > 0 && root.windowData)
                    ? "file://" + MangoData.shotDir + "/" + root.windowData.id + ".ppm?" + MangoData.shotGeneration
                    : ""

            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.windowRounding * root.scale
                color: pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) :
                    hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) :
                    ColorUtils.transparentize(Appearance.colors.colLayer2)
                border.color : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
                border.width : 1
            }

        ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Appearance.font.pixelSize.smaller * 0.5

            Image {
                id: windowIcon
                property var iconSize: {
                    return Math.min(targetWindowWidth, targetWindowHeight) * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio) / (root.monitorData?.scale ?? 1);
                }
                Layout.alignment: Qt.AlignHCenter
                source: root.iconPath
                width: iconSize
                height: iconSize
                sourceSize: Qt.size(iconSize, iconSize)

                Behavior on width {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }
    }
    }
}
