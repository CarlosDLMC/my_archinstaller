pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Power menu «ПУСК · ПУЛЬТ» on CTRL+ALT+P (global shortcut quickshell:powerMenu)
// and on the Arch logo. Replaces wlogout.
//
// L and U fire at once. E, R, S - and B, W, which reboot - arm a five-second
// countdown named after a real launch («ключ на старт» → «пуск»); the same key
// or Enter again fires now, Esc disarms. wlogout fired on a single key with no
// way back.
//
// Nothing before Т−0 is destructive: the only real step on the way is `sync`.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""

    // Fixed palette, the hyprlock one (SovietLock.py) - deliberately not
    // wallust, exactly like the lock screen: the menu that leads to the lock
    // screen looks like the same machine whatever the wallpaper.
    readonly property color ink: "#D8D8D0"
    readonly property color dim: "#6E7066"
    readonly property color red: "#C42B1C"
    readonly property color white: "#F2F2EC"
    readonly property color black: "#000000"
    readonly property color grey1: "#1A1B18"
    readonly property color grey2: "#2A2B27"
    readonly property color grey3: "#45463F"
    readonly property color shade: "#050505"

    readonly property var modes: [
        { k: "L", ru: "Д", name: "БЛОКИРОВКА",   slogan: "ПОСТ СДАН.",      arm: false, glyph: 0xF033E,
          ask: "Пост сдать, терминал под охрану.", readback: "",
          show: "loginctl lock-session", cmd: home + "/.config/hypr/scripts/LockScreen.sh" },
        { k: "E", ru: "У", name: "ВЫХОД",        slogan: "СМЕНА ОКОНЧЕНА.", arm: true,  glyph: 0xF0343,
          ask: "Смену закончить, сеанс сдать.", readback: "Вас понял: смену сдаю.",
          show: "hyprctl dispatch 'hl.dsp.exit()'", cmd: "hyprctl dispatch 'hl.dsp.exit()'" },
        { k: "U", ru: "Г", name: "СПЯЩИЙ РЕЖИМ", slogan: "ПЕРЕКУР.",        arm: false, glyph: 0xF04B2,
          ask: "Разрешаю перекур.", readback: "",
          show: "systemctl suspend", cmd: "systemctl suspend" },
        { k: "R", ru: "К", name: "ПЕРЕЗАГРУЗКА", slogan: "ПОЕХАЛИ!",        arm: true,  glyph: 0xF0709,
          ask: "Повторный старт. Поехали!", readback: "Вас понял: к повторному старту готов.",
          show: "systemctl reboot", cmd: "systemctl reboot" },
        { k: "S", ru: "Ы", name: "ВЫКЛЮЧЕНИЕ",   slogan: "ОТБОЙ, ТОВАРИЩ.", arm: true,  glyph: 0xF0425,
          ask: "Приказ на отбой. Как поняли?", readback: "Вас понял: отбой.",
          show: "systemctl poweroff", cmd: "systemctl poweroff" }
    ]
    // The quiet extras, each shown only where the machine can do it.
    readonly property var extras: ({
        "B": { ru: "И", name: "ПЕРЕЗАГРУЗКА В UEFI", readback: "Вас понял: иду в машинное отделение.", cmd: "systemctl reboot --firmware-setup" },
        "W": { ru: "Ц", name: "ПЕРЕЗАГРУЗКА В WINDOWS", readback: "Вас понял: ухожу на чужую ОС.",
               cmd: "pkexec efibootmgr --bootnext " + windowsEntry + " >/dev/null && systemctl reboot" }
    })

    readonly property var litany: ["КЛЮЧ НА СТАРТ", "ПРОТЯЖКА-1", "ПРОДУВКА", "КЛЮЧ НА ДРЕНАЖ", "ПУСК"]
    readonly property int countdown: 5

    property bool dialogOpen: false
    property int selected: 0
    property string armedKey: ""
    property real armedAt: 0
    property real elapsed: 0
    readonly property bool armed: armedKey !== ""
    readonly property int step: Math.min(litany.length - 1, Math.floor(elapsed))
    readonly property int secondsLeft: Math.max(0, Math.ceil(countdown - elapsed))

    property bool canFirmware: false
    property string windowsEntry: ""
    property real uptime: 0

    function modeOf(k) {
        for (var i = 0; i < modes.length; i++)
            if (modes[i].k === k) return modes[i]
        return null
    }
    function armedName() {
        var m = modeOf(armedKey)
        return m ? m.name : (extras[armedKey] ? extras[armedKey].name : "")
    }
    function armedCommand() {
        var m = modeOf(armedKey)
        return m ? m.show : (extras[armedKey] ? extras[armedKey].cmd.split(" >")[0] : "")
    }
    // What the computer does at each second of the litany.
    function stepAction(i) {
        return ["приказ принят", "журнал на ленту", "sync", "проверка блокировок", armedCommand()][i]
    }
    // The radio: Заря (ground) gives the order for whatever is selected;
    // once armed, Кедр (the machine) reads it back.
    function armedRu() {
        var m = modeOf(armedKey)
        return m ? m.ru : (extras[armedKey] ? extras[armedKey].ru : "")
    }
    function radioWho() { return armed ? "КЕДР" : "ЗАРЯ" }
    function radioText() {
        if (armed) {
            var m = modeOf(armedKey)
            return "Заря, я Кедр. " + (m ? m.readback : (extras[armedKey] ? extras[armedKey].readback : ""))
        }
        return "Кедр, я Заря. " + modes[selected].ask
    }

    function available(k) {
        if (k === "B") return canFirmware
        if (k === "W") return windowsEntry !== ""
        return modeOf(k) !== null
    }

    function clock(secs) {
        secs = Math.max(0, Math.floor(secs))
        var h = Math.floor(secs / 3600), m = Math.floor(secs / 60) % 60, s = secs % 60
        function two(n) { return (n < 10 ? "0" : "") + n }
        return two(h) + ":" + two(m) + ":" + two(s)
    }

    function open() {
        uptimeFile.reload()
        root.uptime = parseFloat(uptimeFile.text()) || 0
        selected = 0
        disarm()
        dialogOpen = true
    }
    function close() {
        disarm()
        dialogOpen = false
    }
    function toggle() {
        if (dialogOpen) close()
        else open()
    }

    // A key or click on an order.
    function press(k) {
        if (!available(k)) return
        if (armed) {
            if (k === armedKey) fire()
            return
        }
        var m = modeOf(k)
        if (m && !m.arm) {
            run(m.cmd)
            return
        }
        if (m) selected = modes.indexOf(m)
        armedKey = k
        armedAt = Date.now()
        elapsed = 0
        syncDone = false
    }
    function disarm() {
        armedKey = ""
        elapsed = 0
    }
    function fire() {
        var m = modeOf(armedKey)
        var cmd = m ? m.cmd : (extras[armedKey] ? extras[armedKey].cmd : "")
        if (cmd) run(cmd)
    }

    // Close first, run after the fade, so nothing (hyprlock, the polkit
    // prompt for W) has to share the screen with the overlay.
    property string pending: ""
    function run(cmd) {
        pending = cmd
        close()
        settle.restart()
    }
    Timer {
        id: settle
        interval: 250
        onTriggered: {
            runProc.command = ["sh", "-c", "( " + root.pending + " ) >/dev/null 2>&1 &"]
            runProc.running = true
        }
    }
    Process { id: runProc; command: ["true"] }

    // The countdown. Wall clock, so a busy frame cannot stretch it.
    property bool syncDone: false
    Timer {
        interval: 100
        repeat: true
        running: root.armed
        onTriggered: {
            root.elapsed = (Date.now() - root.armedAt) / 1000
            if (root.step >= 2 && !root.syncDone) {
                root.syncDone = true
                syncProc.running = true          // «ПРОДУВКА»: buffers to disk
            }
            if (root.elapsed >= root.countdown) root.fire()
        }
    }
    Process { id: syncProc; command: ["sync"] }

    // Uptime as mission time, ticking while the menu is open.
    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        blockAllReads: true
        printErrors: false
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.dialogOpen
        onTriggered: {
            uptimeFile.reload()
            root.uptime = parseFloat(uptimeFile.text()) || root.uptime + 1
        }
    }

    // What this machine can do beyond the five orders - asked once.
    Process {
        running: true
        command: ["busctl", "call", "org.freedesktop.login1", "/org/freedesktop/login1",
                  "org.freedesktop.login1.Manager", "CanRebootToFirmwareSetup"]
        stdout: StdioCollector {
            onStreamFinished: root.canFirmware = text.indexOf("\"yes\"") >= 0
        }
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v efibootmgr >/dev/null && efibootmgr 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var m = text.match(/^Boot([0-9A-Fa-f]{4})\*?\s+Windows Boot Manager/m)
                root.windowsEntry = m ? m[1] : ""
            }
        }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "powerMenu"
        description: "Power menu"
        onPressed: root.toggle()
    }
}
