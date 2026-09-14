import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// The network card: what `nm-connection-editor` was being opened for, in the
// bar's own style. Functionality ported from Omarchy's network panel
// (omacom/omarchy, MIT, DHH) - status, throughput, latency, captive portal,
// a DNS provider picker, saved-network management and the radio toggle.
//
// All the reading lives here rather than in WifiWidget, and every poll is
// gated on the card being open: closed, this costs nothing at all.
Item {
    id: panel

    required property var ctl

    readonly property bool active: ctl.dropdownOpen && ctl.panelMode === "details"

    readonly property int labelSize: Theme.fontSize - 3
    readonly property int headerSize: Theme.fontSize - 5

    // ------------------------------------------------------------------
    //  Status, from scripts/network-status.sh
    // ------------------------------------------------------------------

    property var info: ({})
    property real rxRate: -1        // bytes/sec, -1 until two samples exist
    property real txRate: -1
    property real lastRx: -1
    property real lastTx: -1
    property real lastSampleMs: 0

    function num(key) {
        var v = info[key]
        if (v === undefined || v === "") return NaN
        return Number(v)
    }

    function field(key, fallback) {
        var v = info[key]
        return (v === undefined || v === "") ? (fallback === undefined ? "—" : fallback) : String(v)
    }

    // nmcli -t escapes a literal ':' inside a value as '\:', so fields cannot
    // be split on every colon - an SSID containing one would shift every
    // field after it.
    function splitNm(line) {
        var out = []
        var cur = ""
        var esc = false
        for (var i = 0; i < line.length; i++) {
            var ch = line.charAt(i)
            if (esc) { cur += ch; esc = false }
            else if (ch === "\\") { esc = true }
            else if (ch === ":") { out.push(cur); cur = "" }
            else cur += ch
        }
        out.push(cur)
        return out
    }

    function applyStatus(out) {
        var next = {}
        var lines = String(out || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
            var t = lines[i].indexOf("\t")
            if (t < 0) continue
            next[lines[i].substring(0, t)] = lines[i].substring(t + 1)
        }

        // Rates come from the delta between samples against real elapsed time,
        // not against the timer interval - a tick that runs late (the pings can
        // take up to a second) would otherwise read as a burst of traffic.
        var now = Date.now()
        var rx = Number(next["rx_bytes"])
        var tx = Number(next["tx_bytes"])
        if (!isNaN(rx) && !isNaN(tx) && panel.lastRx >= 0 && panel.lastSampleMs > 0) {
            var dt = (now - panel.lastSampleMs) / 1000
            // Counters reset when the interface changes (VPN up or down), which
            // shows as a negative delta; drop that sample rather than drawing a
            // nonsense spike.
            if (dt > 0.2 && rx >= panel.lastRx && tx >= panel.lastTx) {
                panel.rxRate = (rx - panel.lastRx) / dt
                panel.txRate = (tx - panel.lastTx) / dt
            }
        }
        if (!isNaN(rx)) panel.lastRx = rx
        if (!isNaN(tx)) panel.lastTx = tx
        panel.lastSampleMs = now

        panel.info = next
    }

    function humanRate(bytesPerSec) {
        if (bytesPerSec < 0 || isNaN(bytesPerSec)) return "—"
        var bits = bytesPerSec * 8
        if (bits >= 1000000000) return (bits / 1000000000).toFixed(1) + " Gb/s"
        if (bits >= 1000000) return (bits / 1000000).toFixed(1) + " Mb/s"
        if (bits >= 1000) return (bits / 1000).toFixed(0) + " kb/s"
        return Math.round(bits) + " b/s"
    }

    function humanBytes(b) {
        if (isNaN(b)) return "—"
        if (b >= 1073741824) return (b / 1073741824).toFixed(2) + " GB"
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB"
        if (b >= 1024) return (b / 1024).toFixed(0) + " kB"
        return b + " B"
    }

    function bandLabel() {
        var f = num("freq")
        if (isNaN(f)) return "—"
        if (f >= 5925) return "6 GHz"
        if (f >= 4900) return "5 GHz"
        return "2.4 GHz"
    }

    Process {
        id: statusProc
        property string buf: ""
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/network-status.sh"]
        stdout: SplitParser {
            onRead: data => { if (data) statusProc.buf += data + "\n" }
        }
        onRunningChanged: {
            if (running) buf = ""
            else if (buf) panel.applyStatus(buf)
        }
    }

    // The pings inside the script take up to a second, so never stack calls.
    Timer {
        interval: 3000
        running: panel.active
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!statusProc.running) statusProc.running = true
    }

    // ------------------------------------------------------------------
    //  Connectivity, radio, saved profiles
    // ------------------------------------------------------------------

    property string connectivity: ""     // full / portal / limited / none
    property bool wifiRadioOn: true
    property var savedNets: []           // [{name, autoconnect}]
    property string activeConn: ""
    property string busy: ""             // what an action is doing, "" when idle

    readonly property bool captive: connectivity === "portal" || connectivity === "limited"

    Process {
        id: generalProc
        property string buf: ""
        // Connectivity, radio state and the active wifi profile in one call.
        command: ["sh", "-c",
            "printf 'connectivity\\t%s\\n' \"$(nmcli -t -f CONNECTIVITY general 2>/dev/null)\"; " +
            "printf 'radio\\t%s\\n' \"$(nmcli -t -f WIFI radio 2>/dev/null)\"; " +
            "printf 'active\\t%s\\n' \"$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | grep ':802-11-wireless$' | head -1 | sed 's/:802-11-wireless$//')\""]
        stdout: SplitParser {
            onRead: data => { if (data) generalProc.buf += data + "\n" }
        }
        onRunningChanged: {
            if (running) { buf = ""; return }
            var lines = buf.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var t = lines[i].indexOf("\t")
                if (t < 0) continue
                var k = lines[i].substring(0, t)
                var v = lines[i].substring(t + 1).trim()
                if (k === "connectivity") panel.connectivity = v
                else if (k === "radio") panel.wifiRadioOn = (v === "enabled")
                else if (k === "active") panel.activeConn = v
            }
        }
    }

    Process {
        id: savedProc
        property string buf: ""
        command: ["sh", "-c",
            "nmcli -t -f NAME,TYPE,AUTOCONNECT connection show 2>/dev/null | grep ':802-11-wireless:'"]
        stdout: SplitParser {
            onRead: data => { if (data) savedProc.buf += data + "\n" }
        }
        onRunningChanged: {
            if (running) { buf = ""; return }
            var out = []
            var lines = buf.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i]
                if (!line) continue
                var parts = panel.splitNm(line)
                if (parts.length < 3) continue
                // NAME is everything before the trailing TYPE and AUTOCONNECT.
                var auto = parts[parts.length - 1]
                var name = parts.slice(0, parts.length - 2).join(":")
                if (name) out.push({ name: name, autoconnect: auto === "yes" })
            }
            panel.savedNets = out
        }
    }

    // One runner for every mutation, so two cannot be in flight at once.
    Process {
        id: actionProc
        onRunningChanged: {
            if (running) return
            panel.busy = ""
            panel.refresh()
        }
    }

    function run(what, cmd) {
        if (actionProc.running) return
        panel.busy = what
        actionProc.command = ["sh", "-c", cmd]
        actionProc.running = true
    }

    function shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }

    function forget(name) {
        run("forget", "nmcli connection delete " + shq(name))
    }

    function setAutoconnect(name, on) {
        run("autoconnect", "nmcli connection modify " + shq(name)
            + " connection.autoconnect " + (on ? "yes" : "no"))
    }

    function toggleRadio() {
        run("radio", "nmcli radio wifi " + (panel.wifiRadioOn ? "off" : "on"))
    }

    function openPortal() {
        // The probe URL NetworkManager itself uses, so the portal answers it.
        Quickshell.execDetached(["xdg-open", "http://ping.archlinux.org/nm-check.txt"])
    }

    // DNS provider. This edits the active profile, so it is deliberately
    // limited to the three unambiguous choices - anything more belongs in
    // nm-connection-editor, which is still installed.
    readonly property var dnsChoices: [
        { label: "DHCP",       servers: "" },
        { label: "Cloudflare", servers: "1.1.1.1 1.0.0.1" },
        { label: "Google",     servers: "8.8.8.8 8.8.4.4" }
    ]

    readonly property string currentDns: panel.field("dns", "")

    function dnsIsActive(choice) {
        if (choice.servers === "") {
            // DHCP is "none of the pinned sets are in force".
            for (var i = 1; i < dnsChoices.length; i++)
                if (currentDns.indexOf(dnsChoices[i].servers.split(" ")[0]) !== -1) return false
            return currentDns !== ""
        }
        return currentDns.indexOf(choice.servers.split(" ")[0]) !== -1
    }

    function setDns(choice) {
        if (!panel.activeConn) return
        var n = shq(panel.activeConn)
        var cmd = choice.servers === ""
            ? "nmcli connection modify " + n + " ipv4.ignore-auto-dns no ipv4.dns ''"
            : "nmcli connection modify " + n + " ipv4.ignore-auto-dns yes ipv4.dns " + shq(choice.servers)
        run("dns", cmd + " && nmcli connection up " + n)
    }

    // ------------------------------------------------------------------
    //  Speed test and share-QR
    // ------------------------------------------------------------------
    //  Both replace the card's body rather than opening a window of their own
    //  (DHH gives each its own centred card, but this bar's cards are
    //  dropdowns and a second layer surface would fight the focus grab).

    property string view: "info"          // "info" | "speed" | "qr"

    // --- speed test
    property string speedPhase: ""        // "" | "down" | "up" | "done"
    property real speedDown: 0
    property real speedUp: 0
    property real speedNow: 0

    //  The run generation. Every start and every stop bumps it, and a launched
    //  process carries the generation it was launched for. An exit whose
    //  generation no longer matches is from a run we have abandoned, and is
    //  ignored - without this, killing the download phase and immediately
    //  starting a new test let the OLD exit fire against the NEW run's state
    //  and chain it straight to the upload phase, so the fresh test skipped
    //  download entirely and reported "Down —".
    property int speedRun: 0
    property bool speedPending: false
    property string speedError: ""

    readonly property string speedScript:
        "$HOME/.config/quickshell/bar/scripts/network-speedtest.sh"

    function launchSpeedPhase(phase) {
        speedProc.phase = phase
        speedProc.gen = panel.speedRun
        speedProc.command = ["sh", "-c", panel.speedScript + " " + phase + " 8"]
        speedProc.running = true
    }

    Process {
        id: speedProc
        property string phase: ""
        property int gen: -1

        stdout: SplitParser {
            onRead: data => {
                if (!data) return
                if (speedProc.gen !== panel.speedRun) return
                var v = Number(data.trim())
                if (isNaN(v)) return
                panel.speedNow = v
                // Keep the peak, not the last sample: the first second or two
                // is the workers ramping up, so the final reading understates
                // the link badly.
                if (speedProc.phase === "down") panel.speedDown = Math.max(panel.speedDown, v)
                else if (speedProc.phase === "up") panel.speedUp = Math.max(panel.speedUp, v)
            }
        }

        // The script reports why it gave up on stderr - no route, no curl, or
        // fast.com unreachable. Unread, those failures looked identical to a
        // successful run that measured nothing: both phases exited at once and
        // the card sat on "Done" showing two dashes.
        stderr: SplitParser {
            onRead: data => {
                if (!data) return
                if (speedProc.gen !== panel.speedRun) return
                var line = data.trim()
                if (line !== "") panel.speedError = line.replace(/^error:\s*/, "")
            }
        }

        onExited: {
            // A press that arrived while the previous run was still dying.
            if (panel.speedPending) {
                panel.speedPending = false
                panel.launchSpeedPhase("down")
                return
            }
            if (speedProc.gen !== panel.speedRun) return

            if (speedProc.phase === "down") {
                panel.speedNow = 0
                panel.speedPhase = "up"
                panel.launchSpeedPhase("up")
            } else if (speedProc.phase === "up") {
                panel.speedPhase = "done"
                panel.speedNow = 0
            }
        }
    }

    function startSpeedTest() {
        panel.speedRun++
        speedDown = 0; speedUp = 0; speedNow = 0
        speedError = ""
        speedPhase = "down"
        view = "speed"

        // Pressing the icon used to do nothing at all if the previous run had
        // not finished dying yet - it returned early, without even switching
        // the view. Now the restart is queued and fires from onExited.
        if (speedProc.running) {
            speedPending = true
            speedProc.signal(15)
        } else {
            speedPending = false
            launchSpeedPhase("down")
        }
    }

    function stopSpeedTest() {
        panel.speedRun++          // invalidate whatever is in flight
        panel.speedPending = false
        if (speedProc.running) speedProc.signal(15)
        speedPhase = ""
        speedNow = 0
    }

    // --- share QR
    property var qrRows: []
    property string qrSsid: ""
    property string qrSecurity: ""
    property string qrError: ""

    Process {
        id: qrProc
        property string buf: ""
        command: ["sh", "-c", "$HOME/.config/quickshell/bar/scripts/network-qr.sh"]
        stdout: SplitParser {
            onRead: data => { if (data !== undefined) qrProc.buf += data + "\n" }
        }
        onRunningChanged: {
            if (running) { buf = ""; return }
            var rows = []
            panel.qrError = ""
            var lines = buf.split("\n")
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i]
                if (!line) continue
                if (line.indexOf("error\t") === 0) {
                    panel.qrError = line.substring(6)
                    panel.qrRows = []
                    return
                }
                if (line.indexOf("meta\t") === 0) {
                    var m = line.split("\t")
                    panel.qrSecurity = m[2] || ""
                    panel.qrSsid = m[3] || ""
                    continue
                }
                if (/^[01]+$/.test(line)) rows.push(line)
            }
            panel.qrRows = rows
        }
    }

    function showQr() {
        view = "qr"
        qrError = ""
        if (!qrProc.running) qrProc.running = true
    }

    function refresh() {
        if (!panel.active) return
        if (!statusProc.running) statusProc.running = true
        if (!generalProc.running) generalProc.running = true
        if (!savedProc.running) savedProc.running = true
    }

    onActiveChanged: {
        if (active) {
            // Rates need two samples; forget the old ones so a stale counter
            // from a previous open cannot produce a bogus first reading.
            lastRx = -1; lastTx = -1; lastSampleMs = 0
            rxRate = -1; txRate = -1
            refresh()
        } else {
            // Closing the card must not leave eight curl workers saturating
            // the link, and it should come back on the info view.
            stopSpeedTest()
            view = "info"
        }
    }

    // ------------------------------------------------------------------
    //  Rendering
    // ------------------------------------------------------------------
    //  Facts are laid out as label/value PAIRS, two pairs to a row, in a
    //  4-column GridLayout - the same shape DHH uses. One pair per row read
    //  as a very tall card for what is mostly short values: fifteen rows of
    //  mostly-empty line became eight.

    component SectionHeader: Item {
        property string label: ""
        width: parent ? parent.width : 0
        height: Math.round(panel.headerSize * 1.9)

        Text {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            text: parent.label
            color: Theme.colMuted
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

    // Grid cells. The label sits at its natural width; the value takes the
    // slack and is right-aligned against it, so the two pairs in a row line
    // up as two clean label/value gutters.
    component GLabel: Text {
        color: Theme.colDim
        font.pixelSize: panel.labelSize
        font.family: Theme.fontFamily
        Layout.alignment: Qt.AlignVCenter
    }

    component GValue: Text {
        color: Theme.colWhite
        font.pixelSize: panel.labelSize
        font.family: Theme.fontFamily
        font.bold: true
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignRight
        // preferredWidth 0 + fillWidth: the two value columns share the row
        // evenly instead of one long value starving the other.
        Layout.preferredWidth: 0
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
    }

    component InfoGrid: GridLayout {
        width: parent ? parent.width : 0
        columns: 4
        columnSpacing: 14
        rowSpacing: 3
    }

    // A bare glyph that lights up on hover, for the header actions. Deliberately
    // not a Pill: these are the card's primary actions and a row of outlined
    // capsules at the top would out-shout the readings underneath them.
    component IconButton: Rectangle {
        property string glyph: ""
        property bool current: false
        signal picked()

        implicitWidth: Math.round(panel.labelSize * 1.9)
        implicitHeight: Math.round(panel.labelSize * 1.9)
        radius: 6
        color: current
            ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.16)
            : (iconMouse.containsMouse
                ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.10)
                : "transparent")
        Behavior on color { ColorAnimation { duration: 130 } }

        Text {
            anchors.centerIn: parent
            text: parent.glyph
            color: parent.current || iconMouse.containsMouse ? Theme.colWhite : Theme.colGrey
            font.pixelSize: panel.labelSize + 2
            font.family: Theme.fontFamily
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.picked()
        }
    }

    component Pill: Rectangle {
        property string label: ""
        property bool current: false
        signal picked()
        implicitWidth: pillText.implicitWidth + 18
        implicitHeight: Math.round(panel.labelSize * 1.9)
        radius: height / 2
        color: current
            ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.85)
            : (pillMouse.containsMouse
                ? Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.14)
                : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.06))
        border.width: 1
        border.color: current
            ? Theme.colWhite
            : Qt.rgba(Theme.colWhite.r, Theme.colWhite.g, Theme.colWhite.b, 0.22)
        Behavior on color { ColorAnimation { duration: 130 } }

        Text {
            id: pillText
            anchors.centerIn: parent
            text: parent.label
            color: parent.current ? Theme.colBg : Theme.colDim
            font.pixelSize: panel.labelSize
            font.family: Theme.fontFamily
            font.bold: parent.current
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.picked()
        }
    }

    readonly property real contentHeight: body.implicitHeight

    Flickable {
        anchors.fill: parent
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: body
            width: parent.width
            spacing: 3

            // ------------------------------------------------------- header
            //  The connected network as the hero, with the card's actions to
            //  its right - the shape DHH uses. The SSID lives here rather than
            //  as a "Network" row in LINK below, so the title and the actions
            //  share one line instead of taking two.
            Item {
                width: parent.width
                height: Math.round(panel.labelSize * 2.2)

                Row {
                    anchors.left: parent.left
                    anchors.right: headerActions.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.wifiRadioOn ? "󰤨" : "󰤮"
                        color: panel.wifiRadioOn ? Theme.colWhite : Theme.colMuted
                        font.pixelSize: panel.labelSize
                        font.family: Theme.fontFamily
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 26
                        text: panel.field("ssid", "Not connected")
                        color: Theme.colWhite
                        font.pixelSize: panel.labelSize
                        font.family: Theme.fontFamily
                        font.bold: true
                        elide: Text.ElideMiddle
                    }
                }

                Row {
                    id: headerActions
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    // Both toggle: pressing the icon of the view you are in
                    // returns to the readings, so neither needs a Back button.
                    IconButton {
                        glyph: "󰐲"
                        current: panel.view === "qr"
                        onPicked: {
                            if (panel.view === "qr") panel.view = "info"
                            else panel.showQr()
                        }
                    }

                    IconButton {
                        glyph: "󰓅"
                        current: panel.view === "speed"
                        onPicked: {
                            if (panel.view === "speed") { panel.stopSpeedTest(); panel.view = "info" }
                            else panel.startSpeedTest()
                        }
                    }

                    IconButton {
                        glyph: panel.busy !== "" ? "󰔟" : (panel.wifiRadioOn ? "󰖩" : "󰖪")
                        current: panel.wifiRadioOn
                        onPicked: panel.toggleRadio()
                    }
                }
            }

            Divider {}

            // ------------------------------------------------------ captive
            Rectangle {
                width: parent.width
                height: visible ? portalCol.implicitHeight + 16 : 0
                visible: panel.captive
                radius: 6
                color: Qt.rgba(Theme.colAlert.r, Theme.colAlert.g, Theme.colAlert.b, 0.18)
                border.width: 1
                border.color: Theme.colAlert

                Column {
                    id: portalCol
                    anchors.centerIn: parent
                    width: parent.width - 16
                    spacing: 3

                    Text {
                        text: panel.connectivity === "portal"
                            ? "󰀪  Sign-in required"
                            : "󰀪  Limited connectivity"
                        color: Theme.colAlert
                        font.pixelSize: panel.labelSize
                        font.family: Theme.fontFamily
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        text: "This network wants you to sign in or accept its terms before it will pass traffic."
                        color: Theme.colDim
                        font.pixelSize: panel.headerSize
                        font.family: Theme.fontFamily
                        wrapMode: Text.WordWrap
                    }

                    Pill {
                        label: "Open sign-in page"
                        onPicked: panel.openPortal()
                    }
                }
            }

            // ------------------------------------------------- info view
            Column {
                id: infoView
                width: parent.width
                spacing: 3
                visible: panel.view === "info"

            // --------------------------------------------------------- link
            SectionHeader { label: "LINK" }

            InfoGrid {
                // Band rides with the signal rather than taking a row of its
                // own. It was tried next to the rate first, where the pair
                // "5 GHz · 1170 Mbit/s" was too long for half a card and the
                // rate elided; beside the percentage both halves fit.
                GLabel { text: "Signal" }
                GValue {
                    text: {
                        var pct = panel.num("signal_pct")
                        var dbm = panel.num("signal_dbm")
                        var band = panel.bandLabel()
                        if (isNaN(pct)) return band === "—" ? "—" : band
                        var v = isNaN(dbm) ? pct + "%" : pct + "% (" + dbm + ")"
                        return band === "—" ? v : v + " · " + band
                    }
                    // Only a genuinely weak link earns the alert hue.
                    color: {
                        var pct = panel.num("signal_pct")
                        return (!isNaN(pct) && pct < 30) ? Theme.colAlert : Theme.colWhite
                    }
                }
                GLabel { text: "Link" }
                GValue { text: panel.field("bitrate") }
            }

            // --------------------------------------------------- connection
            Divider {}
            SectionHeader { label: "CONNECTION" }

            InfoGrid {
                GLabel { text: "Iface" }
                GValue {
                    text: panel.field("iface")
                        + (panel.info["type"] === "vpn" ? " (vpn)" : "")
                }
                GLabel { text: "IP" }
                GValue {
                    text: panel.info["prefix"]
                        ? panel.field("ip") + "/" + panel.field("prefix")
                        : panel.field("ip")
                }

                GLabel { text: "Gateway" }
                GValue { text: panel.field("gateway") }
                GLabel { text: "Router" }
                GValue {
                    text: {
                        var ms = panel.num("router_ping_ms")
                        return isNaN(ms) ? "—" : ms.toFixed(0) + " ms"
                    }
                }

                // DNS runs the full width: two IPv4 servers do not fit in half
                // a card, and eliding the second one hides which resolver is
                // actually in force - the thing the picker below it changes.
                GLabel { text: "DNS" }
                GValue {
                    text: panel.field("dns")
                    Layout.columnSpan: 3
                }
            }

            // --------------------------------------------------- throughput
            Divider {}
            SectionHeader { label: "TRAFFIC" }

            InfoGrid {
                GLabel { text: "Down" }
                GValue { text: panel.humanRate(panel.rxRate) }
                GLabel { text: "Up" }
                GValue { text: panel.humanRate(panel.txRate) }

                GLabel { text: "Recv" }
                GValue { text: panel.humanBytes(panel.num("rx_bytes")) }
                GLabel { text: "Sent" }
                GValue { text: panel.humanBytes(panel.num("tx_bytes")) }

                GLabel { text: "Ping" }
                GValue {
                    text: {
                        var ms = panel.num("internet_ping_ms")
                        return isNaN(ms) ? "—" : ms.toFixed(0) + " ms"
                    }
                    color: {
                        var ms = panel.num("internet_ping_ms")
                        return (!isNaN(ms) && ms > 250) ? Theme.colAlert : Theme.colWhite
                    }
                }
                GLabel { text: "Loss" }
                GValue {
                    text: {
                        var l = panel.num("loss_pct")
                        return isNaN(l) ? "—" : l + "%"
                    }
                    color: {
                        var l = panel.num("loss_pct")
                        return (!isNaN(l) && l > 0) ? Theme.colAlert : Theme.colWhite
                    }
                }
            }

            // ------------------------------------------------ dns and radio
            Divider {}

            Item {
                width: parent.width
                height: Math.round(panel.labelSize * 2.6)

                Text {
                    id: dnsHeader
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DNS"
                    color: Theme.colMuted
                    font.pixelSize: panel.headerSize
                    font.family: Theme.fontFamily
                    font.bold: true
                }

                Row {
                    anchors.left: dnsHeader.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: panel.dnsChoices
                        Pill {
                            required property var modelData
                            label: modelData.label
                            current: panel.dnsIsActive(modelData)
                            onPicked: panel.setDns(modelData)
                        }
                    }
                }
            }

            Text {
                width: parent.width
                visible: panel.activeConn === ""
                text: "No active Wi-Fi profile to change"
                color: Theme.colMuted
                font.pixelSize: panel.headerSize
                font.family: Theme.fontFamily
            }

            }   // end info view

            // ------------------------------------------------- speed view
            Column {
                width: parent.width
                spacing: 6
                visible: panel.view === "speed"

                SectionHeader { label: "SPEED TEST" }

                InfoGrid {
                    GLabel { text: "Down" }
                    GValue {
                        text: panel.speedDown > 0 ? panel.speedDown + " Mb/s" : "—"
                        color: panel.speedPhase === "down" ? Theme.colAlert : Theme.colWhite
                    }
                    GLabel { text: "Up" }
                    GValue {
                        text: panel.speedUp > 0 ? panel.speedUp + " Mb/s" : "—"
                        color: panel.speedPhase === "up" ? Theme.colAlert : Theme.colWhite
                    }
                }

                Text {
                    width: parent.width
                    visible: panel.speedError === ""
                    // "Starting" is a real state, not a cosmetic one: the
                    // script spends its first moment asking fast.com for CDN
                    // endpoints, and a restart additionally waits for the
                    // previous run's workers to die. Both showed as
                    // "Measuring… 0 Mb/s", which reads as broken.
                    text: panel.speedPhase === "" ? "Stopped"
                        : panel.speedPhase === "done" ? "Done - peak of each direction"
                        : panel.speedNow === 0
                            ? "Starting…"
                        : panel.speedPhase === "down"
                            ? "Measuring download…  " + panel.speedNow + " Mb/s"
                            : "Measuring upload…  " + panel.speedNow + " Mb/s"
                    color: Theme.colDim
                    font.pixelSize: panel.headerSize
                    font.family: Theme.fontFamily
                }

                // Why it gave up, rather than a "Done" with two dashes.
                Text {
                    width: parent.width
                    visible: panel.speedError !== ""
                    text: panel.speedError
                    color: Theme.colAlert
                    font.pixelSize: panel.headerSize
                    font.family: Theme.fontFamily
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    visible: panel.speedPhase === "down" || panel.speedPhase === "up"
                    text: "This saturates the connection while it runs."
                    color: Theme.colMuted
                    font.pixelSize: panel.headerSize
                    font.family: Theme.fontFamily
                }

                // Only while something is actually running - the speedometer
                // in the header is what leaves the view again.
                Pill {
                    visible: panel.speedPhase === "down" || panel.speedPhase === "up"
                    label: "Stop"
                    onPicked: panel.stopSpeedTest()
                }
            }

            // ---------------------------------------------------- qr view
            Column {
                width: parent.width
                spacing: 6
                visible: panel.view === "qr"

                SectionHeader { label: "SHARE NETWORK" }

                Text {
                    width: parent.width
                    visible: panel.qrError !== ""
                    text: panel.qrError
                    color: Theme.colAlert
                    font.pixelSize: panel.labelSize
                    font.family: Theme.fontFamily
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    visible: panel.qrRows.length > 0
                    text: panel.qrSsid + (panel.qrSecurity === "nopass" ? "  (open)" : "")
                    color: Theme.colWhite
                    font.pixelSize: panel.labelSize
                    font.family: Theme.fontFamily
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                }

                // The matrix is drawn as plain rectangles on a white ground.
                // The quiet zone is already in the data (qrencode --margin 4),
                // and white is not optional: a scanner needs the contrast, so
                // this is the one thing in the bar that ignores the palette.
                //  Addressed by id, not by parent.parent chains. Those were
                //  wrong by one level in both places and threw
                //  "Cannot read property 'charAt' of undefined" for every cell.
                Rectangle {
                    id: qrSurface
                    visible: panel.qrRows.length > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: cell * (panel.qrRows.length > 0 ? panel.qrRows[0].length : 1)
                    height: cell * panel.qrRows.length
                    color: "white"

                    readonly property int cell: panel.qrRows.length > 0
                        ? Math.max(2, Math.floor(260 / panel.qrRows.length))
                        : 2

                    Column {
                        spacing: 0
                        Repeater {
                            model: panel.qrRows
                            Row {
                                id: qrRow
                                required property string modelData
                                spacing: 0
                                Repeater {
                                    model: qrRow.modelData.length
                                    Rectangle {
                                        required property int index
                                        width: qrSurface.cell
                                        height: width
                                        color: qrRow.modelData.charAt(index) === "1"
                                            ? "black" : "white"
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    visible: panel.qrRows.length > 0
                    text: "Scan to join"
                    color: Theme.colMuted
                    font.pixelSize: panel.headerSize
                    font.family: Theme.fontFamily
                    horizontalAlignment: Text.AlignHCenter
                }
            }

        }
    }
}
