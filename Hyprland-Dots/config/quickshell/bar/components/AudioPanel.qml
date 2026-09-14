import QtQuick
import ".."

// The audio card's body. All the PipeWire reading lives in VolumeWidget and
// arrives here as `ctl`; this file only renders it, the way WifiWidget's
// popup renders the scan it was handed.
//
// Three sections, which is the whole of what the old pavucontrol launch was
// being used for: pick an output and set its level, pick an input and set its
// level, and set a level per running application.
Item {
    id: panel

    required property var ctl

    // What the body actually measures, handed back so the card can be sized to
    // its contents rather than to an arithmetic guess about row heights.
    readonly property real contentHeight: body.implicitHeight

    readonly property int rowH: 30
    readonly property int labelSize: Theme.fontSize - 2
    readonly property int headerSize: Theme.fontSize - 4

    // A section heading: small, muted, letter-spaced by the label itself.
    component SectionHeader: Item {
        property string label: ""
        property string detail: ""
        width: parent ? parent.width : 0
        height: Math.round(panel.headerSize * 1.9)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Theme.colMuted
            font.pixelSize: panel.headerSize
            font.family: Theme.fontFamily
            font.bold: true
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.detail
            color: Theme.colDim
            font.pixelSize: panel.headerSize
            font.family: Theme.fontFamily
            font.bold: true
        }
    }

    component Divider: Rectangle {
        width: parent ? parent.width : 0
        height: 1
        color: Theme.colMuted
        opacity: 0.45
    }

    // A selectable device. The current one is marked by weight and brightness,
    // never by hue - same rule the workspace pills follow.
    component DeviceRow: Rectangle {
        id: device
        property string glyph: ""
        property string label: ""
        property bool current: false
        signal picked()

        width: parent ? parent.width : 0
        height: panel.rowH
        radius: 6
        color: deviceMouse.containsMouse && !current
            ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.10)
            : "transparent"

        Row {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 8

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: device.glyph
                color: device.current ? Theme.colWhite : Theme.colGrey
                font.pixelSize: panel.labelSize
                font.family: Theme.fontFamily
                width: 20
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: device.label
                color: device.current ? Theme.colWhite : Theme.colDim
                font.pixelSize: panel.labelSize
                font.family: Theme.fontFamily
                font.bold: device.current
                elide: Text.ElideRight
                width: device.width - 12 - 20 - 8 - (tick.visible ? tick.width + 8 : 0)
            }

            Text {
                id: tick
                anchors.verticalCenter: parent.verticalCenter
                visible: device.current
                text: "󰄬"
                color: Theme.colWhite
                font.pixelSize: panel.labelSize
                font.family: Theme.fontFamily
            }
        }

        MouseArea {
            id: deviceMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: device.picked()
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: parent.width
            spacing: 4

            // ---------------------------------------------------------- output
            SectionHeader {
                label: "OUTPUT"
                detail: panel.ctl.sinkReady
                    ? Math.round(panel.ctl.sink.audio.volume * 100) + "%"
                    : "—"
            }

            Row {
                width: parent.width
                spacing: 8

                Text {
                    id: outMute
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.ctl.volumeMuted ? "󰝟" : "󰕾"
                    color: panel.ctl.volumeMuted ? Theme.colAlert : Theme.colWhite
                    font.pixelSize: panel.labelSize
                    font.family: Theme.fontFamily
                    width: 20
                    horizontalAlignment: Text.AlignHCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.ctl.toggleMute()
                    }
                }

                VolumeSlider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - outMute.width - 8
                    value: panel.ctl.sinkReady ? panel.ctl.sink.audio.volume : 0
                    muted: panel.ctl.volumeMuted
                    enabled: panel.ctl.sinkReady
                    onMoved: v => panel.ctl.setSinkVolume(v)
                    onRightClicked: panel.ctl.toggleMute()
                }
            }

            Repeater {
                model: panel.ctl.displaySinks
                DeviceRow {
                    required property var modelData
                    glyph: panel.ctl.sinkGlyph(modelData)
                    label: panel.ctl.nodeLabel(modelData)
                    current: panel.ctl.sink && modelData && panel.ctl.sink.id === modelData.id
                    onPicked: panel.ctl.setDefaultSink(modelData)
                }
            }

            // ----------------------------------------------------------- input
            Divider { visible: inputSection.visible }

            Column {
                id: inputSection
                width: parent.width
                spacing: 4
                visible: panel.ctl.displaySources.length > 0 || panel.ctl.sourceReady

                SectionHeader {
                    label: "INPUT"
                    detail: panel.ctl.sourceReady
                        ? Math.round(panel.ctl.source.audio.volume * 100) + "%"
                        : "—"
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        id: inMute
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.ctl.sourceMuted ? "󰍭" : "󰍬"
                        color: panel.ctl.sourceMuted ? Theme.colAlert : Theme.colWhite
                        font.pixelSize: panel.labelSize
                        font.family: Theme.fontFamily
                        width: 20
                        horizontalAlignment: Text.AlignHCenter

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.ctl.toggleSourceMute()
                        }
                    }

                    VolumeSlider {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - inMute.width - 8
                        value: panel.ctl.sourceReady ? panel.ctl.source.audio.volume : 0
                        muted: panel.ctl.sourceMuted
                        enabled: panel.ctl.sourceReady
                        onMoved: v => panel.ctl.setSourceVolume(v)
                        onRightClicked: panel.ctl.toggleSourceMute()
                    }
                }

                Repeater {
                    model: panel.ctl.displaySources
                    DeviceRow {
                        required property var modelData
                        glyph: panel.ctl.sourceGlyph(modelData)
                        label: panel.ctl.nodeLabel(modelData)
                        current: panel.ctl.source && modelData && panel.ctl.source.id === modelData.id
                        onPicked: panel.ctl.setDefaultSource(modelData)
                    }
                }
            }

            // ------------------------------------------------------------ apps
            Divider { visible: appsSection.visible }

            Column {
                id: appsSection
                width: parent.width
                spacing: 4
                visible: panel.ctl.displayStreams.length > 0

                SectionHeader { label: "APPS" }

                Repeater {
                    model: panel.ctl.displayStreams

                    Column {
                        id: stream
                        required property var modelData

                        readonly property bool streamMuted:
                            modelData && modelData.audio ? modelData.audio.muted : false
                        readonly property real streamVolume:
                            modelData && modelData.audio ? modelData.audio.volume : 0

                        width: appsSection.width
                        spacing: 2

                        Row {
                            width: parent.width
                            spacing: 8

                            Text {
                                id: streamIcon
                                anchors.verticalCenter: parent.verticalCenter
                                text: stream.streamMuted ? "󰝟" : "󰕾"
                                color: stream.streamMuted ? Theme.colAlert : Theme.colWhite
                                font.pixelSize: panel.labelSize
                                font.family: Theme.fontFamily
                                width: 20
                                horizontalAlignment: Text.AlignHCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.ctl.toggleStreamMute(stream.modelData)
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: panel.ctl.streamLabel(stream.modelData)
                                color: Theme.colDim
                                font.pixelSize: panel.labelSize
                                font.family: Theme.fontFamily
                                elide: Text.ElideRight
                                width: parent.width - streamIcon.width - streamPct.width - 16
                            }

                            Text {
                                id: streamPct
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(stream.streamVolume * 100) + "%"
                                color: Theme.colMuted
                                font.pixelSize: panel.headerSize
                                font.family: Theme.fontFamily
                                font.bold: true
                                width: 40
                                horizontalAlignment: Text.AlignRight
                            }
                        }

                        VolumeSlider {
                            width: parent.width
                            maximum: 1.5
                            value: stream.streamVolume
                            muted: stream.streamMuted
                            onMoved: v => panel.ctl.setStreamVolume(stream.modelData, v)
                            onRightClicked: panel.ctl.toggleStreamMute(stream.modelData)
                        }
                    }
                }
            }

            // Nothing is playing and there is nothing to pick: say so rather
            // than showing an empty card.
            Text {
                visible: panel.ctl.displaySinks.length === 0
                    && panel.ctl.displayStreams.length === 0
                width: parent.width
                text: "No audio devices"
                color: Theme.colMuted
                font.pixelSize: panel.labelSize
                font.family: Theme.fontFamily
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
