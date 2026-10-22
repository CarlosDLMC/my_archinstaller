import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."

// The wallpaper transition after a carousel pick: two slanted edges - the
// cards' slant - open from the centre line out to the borders, with the new
// wallpaper between them. awww has no such transition, so it is drawn here,
// on the Bottom layer: above awww's Background surface, below every window,
// so it shows exactly where the wallpaper shows. WallpaperState runs the
// timing and has awww swap instantly underneath once the reveal is full.
PanelWindow {
    id: reveal

    property var modelData
    screen: modelData

    readonly property bool active: WallpaperState.revealPhase !== ""
    readonly property real skew: -0.35
    // Half the screen plus the slant's overhang, so at 1 the band covers
    // the corners too.
    readonly property real fullWidth: width + Math.abs(skew) * height + 8

    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    WlrLayershell.namespace: "quickshell:wallpaper-reveal"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Never in the way: clicks go to whatever is under it.
    mask: Region {}

    // Report once per pick, when this screen's picture is decoded.
    property bool reported: false
    onActiveChanged: reported = false

    Item {
        anchors.fill: parent
        // The slanted edges are cut by the clip; multisampling smooths them,
        // as in the carousel.
        layer.enabled: reveal.active
        layer.samples: 4

        Item {
            id: band
            anchors.centerIn: parent
            width: reveal.fullWidth * WallpaperState.revealProgress
            // Taller than the screen, so only the two slanted sides show.
            height: parent.height + 8
            clip: true
            transform: Matrix4x4 {
                matrix: Qt.matrix4x4(1, reveal.skew, 0, -reveal.skew * band.height / 2,
                                     0, 1, 0, 0,
                                     0, 0, 1, 0,
                                     0, 0, 0, 1)
            }

            // Sheared back the other way and pinned to the screen, so the
            // band slides open over a picture that itself never moves.
            Image {
                id: pic
                x: -band.x
                y: -band.y
                width: reveal.width
                height: reveal.height
                transform: Matrix4x4 {
                    matrix: Qt.matrix4x4(1, -reveal.skew, 0, reveal.skew * band.height / 2 + reveal.skew * band.y,
                                         0, 1, 0, 0,
                                         0, 0, 1, 0,
                                         0, 0, 0, 1)
                }
                source: reveal.active && WallpaperState.revealItem ? WallpaperState.revealItem.src : ""
                // awww's default is to crop to fill the output, centred.
                fillMode: Image.PreserveAspectCrop
                sourceSize.width: reveal.width
                sourceSize.height: reveal.height
                asynchronous: true
                cache: false
                smooth: true
                onStatusChanged: {
                    if (reveal.reported) return
                    if (status === Image.Ready || status === Image.Error) {
                        reveal.reported = true
                        WallpaperState.revealLoaded()
                    }
                }
            }

            // The two edges, drawn like the carousel's frame.
            Rectangle {
                anchors.fill: parent
                visible: WallpaperState.revealPhase === "opening"
                color: "transparent"
                border.width: 2
                border.color: Theme.colWhite
                antialiasing: true
            }
        }
    }
}
