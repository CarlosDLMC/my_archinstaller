import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import ".."

// Wallpaper carousel (SUPER W), replacing the rofi menu. A strip of slanted
// cards across the focused monitor - the centred one large and framed, the
// others shrinking and fading with distance - and a row of folder tabs above
// it. Enter applies through WallpaperSelect.sh (see WallpaperState).
//
// The behaviour follows motor-dev/wallpaperCarousel (after ilyamiro's picker):
// the slant, the falloff, the zoom on pick. The code is this bar's own, the
// folder tabs are new (upstream shows one directory and nothing under it), and
// the colours are the bar's ramp: colWhite where selected, colGrey elsewhere -
// the large-surface rule in CLAUDE.md. The overlay plumbing follows
// ClipboardOsd and ShotOsd.
//
// Keys: Left/Right browse, Up/Down or Tab change folder, Enter apply, Ctrl+R a
// random card, typing searches every folder, Esc clears the search or closes.
PanelWindow {
    id: osd

    property var modelData
    screen: modelData

    readonly property bool onFocusedMonitor:
        Hyprland.focusedMonitor && modelData
        && Hyprland.focusedMonitor.name === modelData.name

    readonly property bool shown: WallpaperState.dialogOpen && onFocusedMonitor

    property bool windowVisible: false
    readonly property int fadeMs: 160
    readonly property int moveMs: 220
    readonly property real uiScale: 1.35

    // Cards follow the screen's height, so the laptop panel and the 1440p desk
    // show about the same number of them.
    readonly property int cardH: Math.round(height * 0.42)
    readonly property int cardW: Math.round(cardH * 0.72)
    readonly property real skew: -0.35
    // How far the picture must overhang the card so the slant never shows an
    // empty corner: the shear moves the top and bottom edges by this in total.
    readonly property int skewPad: Math.ceil(Math.abs(skew) * cardH)
    readonly property real centreScale: 1.1
    readonly property real farScale: 0.74

    // Folder tabs: 24px, the bar's own Terminess size (was 19), on request.
    readonly property int tabSize: 24
    readonly property int nameSize: Math.round(13 * uiScale)
    readonly property int hintSize: Math.round(11 * uiScale)
    // The caption and key line under the cards, larger than the rest on request.
    // Even pixel sizes: Terminess is drawn from Terminus bitmaps, which come in those.
    readonly property int captionSize: 24
    readonly property int keysSize: 20
    readonly property int gap: Math.round(22 * uiScale)

    visible: windowVisible

    anchors { top: true; bottom: true; left: true; right: true }
    // Own namespace for the blur rule in hypr/UserConfigs/WindowRules.lua.
    WlrLayershell.namespace: "quickshell:wallpaper"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    onShownChanged: {
        if (shown) {
            windowVisible = true
            goneTimer.stop()
            // Reopened during the fade-out: the content is still loaded, so
            // its onCompleted will not run again.
            if (body.item) body.item.reopen()
        } else {
            goneTimer.restart()
        }
    }

    Timer {
        id: goneTimer
        interval: osd.fadeMs
        onTriggered: osd.windowVisible = false
    }

    // Dim behind the strip; a click anywhere out there dismisses.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.6)
        opacity: osd.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: osd.fadeMs } }

        MouseArea {
            anchors.fill: parent
            onClicked: WallpaperState.close()
        }
    }

    // Everything with pictures in it exists only while the overlay is on
    // screen: closing drops the cards and their decoded thumbnails.
    Loader {
        id: body
        anchors.fill: parent
        active: osd.windowVisible
        sourceComponent: content
    }

    Component {
        id: content

        FocusScope {
            id: scope
            anchors.fill: parent
            focus: true
            opacity: osd.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: osd.fadeMs } }

            readonly property var strip: WallpaperState.strip
            readonly property var centred:
                list.currentIndex >= 0 && list.currentIndex < strip.length
                    ? strip[list.currentIndex] : null

            // How the next model change picks the centred card: "current"
            // (the wallpaper on screen, if it is in this strip), "first", or
            // "keep" (the card that was centred). Folder and search changes
            // set it just before the strip changes.
            property string pending: "current"
            property string centredId: ""
            property bool instant: true

            Component.onCompleted: reopen()

            function reopen() {
                search.text = ""
                pending = "current"
                Qt.callLater(reselect)
                Qt.callLater(function () { search.forceActiveFocus() })
            }

            function indexOf(id) {
                for (var i = 0; i < strip.length; i++)
                    if (strip[i].id === id) return i
                return -1
            }

            function reselect() {
                if (strip.length === 0) { pending = "keep"; return }
                var i = -1
                if (pending === "first") i = 0
                else {
                    if (pending === "keep") i = indexOf(centredId)
                    if (i < 0) i = indexOf(WallpaperState.currentId)
                    if (i < 0) i = 0
                }
                pending = "keep"
                jump(i)
            }

            // Straight to a card with no scroll, for opening and for a new
            // strip. The animation comes back on the next turn of the event
            // loop, once the view has settled where it was put.
            function jump(i) {
                instant = true
                list.currentIndex = i
                list.positionViewAtIndex(i, ListView.Center)
                settle.restart()
            }

            Timer {
                id: settle
                interval: 30
                onTriggered: scope.instant = false
            }

            function step(delta) {
                var n = list.count
                if (n === 0) return
                WallpaperState.navigated = true
                list.currentIndex = (list.currentIndex + delta + n) % n
            }

            function goTo(i) {
                if (list.count === 0) return
                WallpaperState.navigated = true
                list.currentIndex = Math.max(0, Math.min(list.count - 1, i))
            }

            function random() {
                var n = list.count
                if (n < 2) return
                var i = list.currentIndex
                while (i === list.currentIndex) i = Math.floor(Math.random() * n)
                goTo(i)
            }

            function handleKey(event) {
                var ctrl = event.modifiers & Qt.ControlModifier
                if (event.key === Qt.Key_Escape) {
                    if (WallpaperState.filter !== "") WallpaperState.filter = ""
                    else WallpaperState.close()
                } else if (event.key === Qt.Key_Left) {
                    step(-1)
                } else if (event.key === Qt.Key_Right) {
                    step(1)
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                    WallpaperState.stepFolder(-1)
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                    WallpaperState.stepFolder(1)
                } else if (event.key === Qt.Key_Home) {
                    goTo(0)
                } else if (event.key === Qt.Key_End) {
                    goTo(list.count - 1)
                } else if (event.key === Qt.Key_PageUp) {
                    goTo(list.currentIndex - 5)
                } else if (event.key === Qt.Key_PageDown) {
                    goTo(list.currentIndex + 5)
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    WallpaperState.pick(centred)
                } else if (event.key === Qt.Key_R && ctrl) {
                    random()
                } else {
                    return
                }
                event.accepted = true
            }

            // The search field keeps focus the whole time so typing just
            // works; keys start there and the ones meant for the strip are
            // handed over first (BeforeItem), as in ClipboardOsd.
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => scope.handleKey(event)

            onCentredChanged: if (centred) centredId = centred.id

            Connections {
                target: WallpaperState
                function onFolderIndexChanged() { scope.pending = "current" }
                function onFilterChanged() {
                    scope.pending = WallpaperState.filter === "" ? "current" : "first"
                    if (search.text !== WallpaperState.filter) search.text = WallpaperState.filter
                }
                function onRecenterRequested() {
                    scope.pending = "current"
                    Qt.callLater(scope.reselect)
                }
                function onStepRequested(delta) { if (osd.shown) scope.step(delta) }
            }

            // The centred card at full size; the tabs sit above it and the
            // caption below.
            Item {
                id: band
                anchors.centerIn: parent
                width: osd.cardW * osd.centreScale
                height: osd.cardH * osd.centreScale
            }

            // --------------------------------------------------- the strip
            ListView {
                id: list
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                // Room for the centred card at its largest, and for the zoom
                // on pick - the layer below is cut at these bounds.
                height: Math.round(osd.cardH * 1.4)
                orientation: ListView.Horizontal
                spacing: Math.round(osd.cardW * 0.05)
                model: scope.strip
                interactive: false
                cacheBuffer: osd.cardW * 2
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: width / 2 - osd.cardW / 2
                preferredHighlightEnd: width / 2 + osd.cardW / 2
                highlightMoveDuration: scope.instant ? 0 : osd.moveMs

                onModelChanged: Qt.callLater(scope.reselect)

                // The slanted edges are cut by the clip, which draws whole
                // pixels: a stair down every edge. Rendering the strip into a
                // multisampled layer smooths them. ~28MB of GPU memory on a
                // 1440p screen, held only while the overlay is open.
                layer.enabled: true
                layer.samples: 4

                // One card per wheel notch; a touchpad's small steps add up.
                property real wheelAcc: 0
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        var d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        list.wheelAcc += d
                        while (list.wheelAcc >= 120) { list.wheelAcc -= 120; scope.step(-1) }
                        while (list.wheelAcc <= -120) { list.wheelAcc += 120; scope.step(1) }
                    }
                }

                delegate: Item {
                    id: cell
                    required property int index
                    required property var modelData

                    width: osd.cardW
                    height: list.height

                    readonly property bool isCentre: ListView.isCurrentItem
                    readonly property int dist: Math.abs(index - list.currentIndex)
                    readonly property real falloff: 1 / (1 + dist * dist)
                    readonly property bool picked: WallpaperState.pickedId === modelData.id
                    readonly property bool otherPicked: WallpaperState.pickedId !== "" && !picked
                    readonly property bool onScreen: WallpaperState.currentId === modelData.id

                    z: picked ? 200 : isCentre ? 100 : 50 - dist

                    Item {
                        id: card
                        anchors.centerIn: parent
                        width: osd.cardW
                        height: osd.cardH

                        scale: cell.picked ? 1.3
                             : (osd.farScale + (osd.centreScale - osd.farScale) * cell.falloff)
                               * (hover.containsMouse && !cell.isCentre ? 1.04 : 1)
                        opacity: cell.picked || cell.otherPicked ? 0
                               : hover.containsMouse ? 1
                               : 0.12 + 0.88 * cell.falloff
                        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on opacity { NumberAnimation { duration: 260 } }

                        // The slant: a shear about the card's own middle, so
                        // the card stays centred where the list puts it.
                        transform: Matrix4x4 {
                            matrix: Qt.matrix4x4(1, osd.skew, 0, -osd.skew * osd.cardH / 2,
                                                 0, 1, 0, 0,
                                                 0, 0, 1, 0,
                                                 0, 0, 0, 1)
                        }

                        Rectangle {
                            anchors.fill: parent
                            color: Theme.colBg
                        }

                        Item {
                            anchors.fill: parent
                            clip: true

                            // Sheared back the other way, so the frame slants
                            // and the picture inside it does not.
                            Item {
                                id: face
                                x: -osd.skewPad / 2
                                width: parent.width + osd.skewPad
                                height: parent.height
                                transform: Matrix4x4 {
                                    matrix: Qt.matrix4x4(1, -osd.skew, 0, osd.skew * osd.cardH / 2,
                                                         0, 1, 0, 0,
                                                         0, 0, 1, 0,
                                                         0, 0, 0, 1)
                                }

                                Image {
                                    id: pic
                                    anchors.fill: parent
                                    source: WallpaperState.thumbUrl(cell.modelData)
                                    // Decoded at card height: a thumbnail is
                                    // 720 tall, the card ~600 on a 1440p screen.
                                    sourceSize.height: osd.cardH
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: pic.status !== Image.Ready
                                    text: cell.modelData.kind === "video" ? "󰐊" : "󰋩"
                                    color: Theme.colGrey
                                    font.pixelSize: Math.round(36 * osd.uiScale)
                                    font.family: Theme.fontFamilyContent
                                }

                                // Video and GIF badge, low on the left. In this
                                // (unslanted) item the card's left edge sits
                                // |skew| * (cardH - y) in from x = 0 at height
                                // y, so the badge starts that far in at its top.
                                Rectangle {
                                    visible: cell.modelData.kind !== "image"
                                    x: Math.abs(osd.skew) * (osd.cardH - y) + 12
                                    y: parent.height - height - 12
                                    width: badgeText.implicitWidth + 14
                                    height: badgeText.implicitHeight + 6
                                    radius: 4
                                    color: Qt.rgba(0, 0, 0, 0.55)

                                    Text {
                                        id: badgeText
                                        anchors.centerIn: parent
                                        text: cell.modelData.kind === "video" ? "󰐊 VIDEO" : "GIF"
                                        color: Theme.colWhite
                                        font.pixelSize: osd.hintSize
                                        font.family: Theme.fontFamily
                                        font.letterSpacing: 1
                                    }
                                }
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            visible: cell.isCentre
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.colWhite
                            antialiasing: true
                        }

                        // Inside the sheared card, so it hits the slanted
                        // shape exactly. A side card scrolls to the centre;
                        // the centre one applies.
                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (cell.isCentre) WallpaperState.pick(cell.modelData)
                                else scope.goTo(cell.index)
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------- empty states
            Text {
                anchors.centerIn: band
                visible: list.count === 0
                horizontalAlignment: Text.AlignHCenter
                text: WallpaperState.filter !== ""
                    ? "Nothing matches “" + WallpaperState.filter + "”"
                    : WallpaperState.scanning || !WallpaperState.scanned
                        ? "Reading " + WallpaperState.wallDir.replace(WallpaperState.home, "~") + "…"
                        : "No wallpapers in " + WallpaperState.wallDir.replace(WallpaperState.home, "~")
                color: Theme.colGrey
                font.pixelSize: osd.nameSize
                font.family: Theme.fontFamilyContent
            }

            // ---------------------------------------------- tabs / search
            Item {
                id: top
                anchors.bottom: band.top
                anchors.bottomMargin: osd.gap
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * osd.gap
                height: Math.round(osd.tabSize * 2.2)

                // Folder tabs. A Row in a Flickable rather than a ListView:
                // there are a handful, and a Row knows its exact width, so the
                // tabs centre when they fit and scroll when they do not.
                Flickable {
                    id: tabsView
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(tabs.width, parent.width)
                    height: parent.height
                    contentWidth: tabs.width
                    contentHeight: height
                    interactive: tabs.width > width
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    visible: WallpaperState.hasFolders
                    opacity: WallpaperState.filter === "" ? 1 : 0
                    enabled: opacity === 1

                    // Keep the chosen tab in view when they overflow.
                    function reveal() {
                        var t = tabsRepeater.itemAt(WallpaperState.folderIndex)
                        if (!t || !interactive) return
                        if (t.x < contentX) contentX = t.x
                        else if (t.x + t.width > contentX + width) contentX = t.x + t.width - width
                    }
                    Connections {
                        target: WallpaperState
                        function onFolderIndexChanged() { tabsView.reveal() }
                    }

                    WheelHandler {
                        property real acc: 0
                        onWheel: event => {
                            acc += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                            while (acc >= 120) { acc -= 120; WallpaperState.stepFolder(-1) }
                            while (acc <= -120) { acc += 120; WallpaperState.stepFolder(1) }
                        }
                    }

                    Row {
                        id: tabs
                        height: parent.height
                        spacing: Math.round(26 * osd.uiScale)

                        Repeater {
                            id: tabsRepeater
                            model: WallpaperState.folders

                            Item {
                                id: tab
                                required property int index
                                required property var modelData
                                readonly property bool chosen: index === WallpaperState.folderIndex

                                width: tabRow.width
                                height: tabs.height

                                Row {
                                    id: tabRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Math.round(6 * osd.uiScale)

                                    Text {
                                        id: tabLabel
                                        text: tab.modelData.label
                                        font.capitalization: Font.AllUppercase
                                        font.letterSpacing: 2
                                        font.pixelSize: osd.tabSize
                                        font.family: Theme.fontFamily
                                        font.bold: tab.chosen
                                        color: tab.chosen || tabMouse.containsMouse ? Theme.colWhite : Theme.colGrey
                                    }
                                    Text {
                                        anchors.baseline: tabLabel.baseline
                                        text: tab.modelData.count
                                        font.pixelSize: Math.round(osd.tabSize * 0.75)
                                        font.family: Theme.fontFamily
                                        color: Theme.colGrey
                                    }
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: 2
                                    visible: tab.chosen
                                    color: Theme.colWhite
                                }

                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        WallpaperState.navigated = true
                                        WallpaperState.filter = ""
                                        WallpaperState.folderIndex = tab.index
                                    }
                                }
                            }
                        }
                    }
                }

                // Search. The field is always there and always focused, so
                // typing anywhere starts a search; it shows once there is
                // something in it, in the tabs' place.
                Row {
                    anchors.centerIn: parent
                    spacing: Math.round(12 * osd.uiScale)
                    opacity: WallpaperState.filter === "" ? 0 : 1

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "SEARCH"
                        font.letterSpacing: 2
                        font.pixelSize: osd.tabSize
                        font.family: Theme.fontFamily
                        color: Theme.colGrey
                    }

                    TextInput {
                        id: search
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(contentWidth + 4, Math.round(40 * osd.uiScale))
                        color: Theme.colWhite
                        font.pixelSize: osd.nameSize
                        font.family: Theme.fontFamilyContent
                        focus: true
                        onTextChanged: if (WallpaperState.filter !== text) WallpaperState.filter = text
                        Keys.priority: Keys.BeforeItem
                        Keys.onPressed: event => scope.handleKey(event)
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: list.count + (list.count === 1 ? " match" : " matches")
                        font.pixelSize: osd.hintSize
                        font.family: Theme.fontFamily
                        color: Theme.colGrey
                    }
                }
            }

            // ---------------------------------------------------- caption
            // Fixed columns, so nothing moves as you browse: the folder is
            // right-aligned up to a fixed "/", the name starts at a fixed x and
            // elides in the middle, then the position and the УСТАНОВЛЕНО stamp
            // each in a column of their own. JetBrains Mono is monospaced, so
            // the columns are counted in characters.
            FontMetrics {
                id: captionFm
                font.family: Theme.fontFamilyContent
                font.pixelSize: osd.captionSize
            }

            Item {
                id: caption
                anchors.top: band.bottom
                anchors.topMargin: osd.gap
                anchors.horizontalCenter: parent.horizontalCenter
                visible: scope.centred !== null

                readonly property real ch: captionFm.averageCharacterWidth
                readonly property int dirCols: 26     // "Dynamic-Wallpapers/Light  /  " elides
                readonly property int posCols: 13     // "  ·  25 ИЗ 54"
                readonly property int stampCols: 16   // "  ·  УСТАНОВЛЕНО"
                // The name gets whatever is left of ~95 columns, less on a narrow screen.
                readonly property int nameCols: Math.max(16, Math.min(40,
                    Math.floor((parent.width - 2 * osd.gap) / ch) - dirCols - posCols - stampCols))

                width: Math.round(ch * (dirCols + nameCols + posCols + stampCols))
                height: Math.ceil(captionFm.height)

                Text {
                    id: dirText
                    width: Math.round(caption.ch * caption.dirCols)
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideLeft
                    text: scope.centred && scope.centred.dir !== "" ? scope.centred.dir + "  /  " : ""
                    color: Theme.colGrey
                    font.pixelSize: osd.captionSize
                    font.family: Theme.fontFamilyContent
                }
                Text {
                    id: nameText
                    x: dirText.width
                    width: Math.round(caption.ch * caption.nameCols)
                    elide: Text.ElideMiddle
                    text: scope.centred ? scope.centred.name : ""
                    color: Theme.colWhite
                    font.pixelSize: osd.captionSize
                    font.family: Theme.fontFamilyContent
                }
                Text {
                    id: posText
                    x: nameText.x + nameText.width
                    width: Math.round(caption.ch * caption.posCols)
                    text: "  ·  " + (list.currentIndex + 1) + " ИЗ " + list.count
                    color: Theme.colGrey
                    font.pixelSize: osd.captionSize
                    font.family: Theme.fontFamilyContent
                }
                Text {
                    x: posText.x + posText.width
                    width: Math.round(caption.ch * caption.stampCols)
                    text: scope.centred && WallpaperState.currentId === scope.centred.id ? "  ·  УСТАНОВЛЕНО" : ""
                    color: Theme.colGrey
                    font.pixelSize: osd.captionSize
                    font.family: Theme.fontFamilyContent
                }
            }

            Text {
                anchors.top: caption.bottom
                anchors.topMargin: Math.round(osd.gap * 0.7)
                anchors.horizontalCenter: parent.horizontalCenter
                // The lock screen's footer voice (SovietLock.py): key as printed on
                // the keycap, one space, the action; groups four spaces apart.
                text: "←→ ЛИСТАТЬ" + (WallpaperState.hasFolders ? "    ↑↓ КАТАЛОГ" : "")
                    + "    ENTER УСТАНОВИТЬ    CTRL+R НАУГАД    ПОИСК ПРИ НАБОРЕ    ESC ОТМЕНА"
                color: Theme.colGrey
                font.pixelSize: osd.keysSize
                font.family: Theme.fontFamily
                font.letterSpacing: 1
            }
        }
    }
}
