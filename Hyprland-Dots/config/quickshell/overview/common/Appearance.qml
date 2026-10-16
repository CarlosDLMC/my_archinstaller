pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "functions"

Singleton {
    id: root
    property QtObject m3colors
    property QtObject animation
    property QtObject animationCurves
    property QtObject colors
    property QtObject rounding
    property QtObject font
    property QtObject sizes

    // ------------------------------------------------------------------
    //  Palette: the bar's. wallust writes it to bar/wallust-colors.json on
    //  every wallpaper change (templates/bar-colors.json), so reading that
    //  file keeps the overview in the bar's colours and recolours it with
    //  the wallpaper - no template of its own. The literals are the
    //  sovietpunk fallbacks, for a missing or malformed file.
    //
    //  Upstream shipped a fixed Material-You palette here (lavender
    //  #E5B6F2 on #161217) that matched nothing else on this desktop.
    // ------------------------------------------------------------------
    property color palBg: "#262625"
    property color palFg: "#E8C4C0"

    //  The bar's neutral ramp (bar/Theme.qml, desat): white for what is
    //  active, grey for the rest, both keeping a whisper of the wallpaper's
    //  hue. A card this size gets no more hue than that - on a large surface
    //  wallust's slots read as solid colour.
    readonly property color colWhite: Qt.hsla(palFg.hslHue, palFg.hslSaturation * 0.12, 0.95, 1)
    readonly property color colGrey: Qt.hsla(palFg.hslHue, palFg.hslSaturation * 0.08, 0.62, 1)

    function applyPalette(text) {
        if (!text || text.length === 0)
            return
        try {
            const j = JSON.parse(text)
            if (j.bg) root.palBg = j.bg
            if (j.fg) root.palFg = j.fg
        } catch (e) {
            console.warn("Appearance: could not parse the bar's wallust-colors.json:", e)
        }
    }

    // wallust rewrites the file in place, so a change can land mid-write.
    property Timer paletteDebounce: Timer {
        interval: 80
        repeat: false
        onTriggered: root.applyPalette(root.paletteFile.text())
    }

    property FileView paletteFile: FileView {
        // An absolute path to the sibling bar config. A relative URL that
        // climbs out of this one ("../../bar/...") is resolved by Quickshell
        // to qrc:/qs-blackhole, and the file is silently never read.
        path: {
            const dir = Quickshell.shellDir.replace(/\/+$/, "")
            return dir.substring(0, dir.lastIndexOf("/")) + "/bar/wallust-colors.json"
        }
        watchChanges: true
        onFileChanged: {
            reload()
            root.paletteDebounce.restart()
        }
        onLoadedChanged: if (loaded) root.applyPalette(text())
    }

    m3colors: QtObject {
        property color m3onBackground: root.colWhite   // StyledText's default colour
        property color m3outline: root.colGrey          // frame of a window preview, drawn at 30%
        property color m3shadow: "#000000"
    }

    colors: QtObject {
        property color colLayer0: root.palBg                                          // the panel
        property color colLayer0Border: ColorUtils.applyAlpha(root.colWhite, 0.14)    // its frame, as on the bar's cards
        property color colLayer1: ColorUtils.mix(root.palBg, "#000000", 0.5)          // a workspace: a dark well in the panel
        property color colOnLayer1: root.colWhite                                     // its number, drawn at 20%
        property color colLayer1Hover: ColorUtils.mix(root.colWhite, colLayer1, 0.08) // a workspace a window is dragged over
        property color colLayer2: ColorUtils.applyAlpha(root.colWhite, 0)             // an idle window preview: no wash
        property color colLayer2Hover: ColorUtils.applyAlpha(root.colWhite, 0.4)      // hovered window (x0.3 = 12%), drop target's frame
        property color colLayer2Active: ColorUtils.applyAlpha(root.colWhite, 0.44)    // the window being dragged (x0.5 = 22%)
        property color colSecondary: root.colWhite                                    // the focused workspace's frame
        property color colTooltip: root.palBg
        property color colOnTooltip: root.colWhite
        property color colTooltipBorder: ColorUtils.applyAlpha(root.colWhite, 0.14)
        property color colShadow: ColorUtils.transparentize(root.m3colors.m3shadow, 0.7)
    }

    // Square, like every window on this desktop (Hyprland's rounding = 0).
    rounding: QtObject {
        property int unsharpen: 0
        property int verysmall: 0
        property int small: 0
        property int normal: 0
        property int large: 0
        property int full: 9999
        property int screenRounding: large
        property int windowRounding: 0
    }

    font: QtObject {
        // Terminess, the bar's face, for the workspace numbers. Window titles in
        // the tooltips are arbitrary text, which the bar gives to JetBrains Mono
        // (Theme.fontFamilyContent), so they get it here too.
        property QtObject family: QtObject {
            property string main: "JetBrainsMono Nerd Font"
            property string title: "Terminess Nerd Font"
            property string expressive: "Terminess Nerd Font"
        }
        property QtObject pixelSize: QtObject {
            property int smaller: 12
            property int small: 15
            property int normal: 16
            property int larger: 19
            property int huge: 22
        }
    }

    animationCurves: QtObject {
        readonly property list<real> expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1]
        readonly property list<real> expressiveEffects: [0.34, 0.80, 0.34, 1.00, 1, 1]
        readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1, 1, 1]
        readonly property real expressiveDefaultSpatialDuration: 500
        readonly property real expressiveEffectsDuration: 200
    }

    animation: QtObject {
        property QtObject elementMove: QtObject {
            property int duration: animationCurves.expressiveDefaultSpatialDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveDefaultSpatial
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMove.duration
                    easing.type: root.animation.elementMove.type
                    easing.bezierCurve: root.animation.elementMove.bezierCurve
                }
            }
        }

        property QtObject elementMoveEnter: QtObject {
            property int duration: 400
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.emphasizedDecel
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveEnter.duration
                    easing.type: root.animation.elementMoveEnter.type
                    easing.bezierCurve: root.animation.elementMoveEnter.bezierCurve
                }
            }
        }

        property QtObject elementMoveFast: QtObject {
            property int duration: animationCurves.expressiveEffectsDuration
            property int type: Easing.BezierSpline
            property list<real> bezierCurve: animationCurves.expressiveEffects
            property Component numberAnimation: Component {
                NumberAnimation {
                    duration: root.animation.elementMoveFast.duration
                    easing.type: root.animation.elementMoveFast.type
                    easing.bezierCurve: root.animation.elementMoveFast.bezierCurve
                }
            }
        }
    }

    sizes: QtObject {
        property real elevationMargin: 10
    }
}
