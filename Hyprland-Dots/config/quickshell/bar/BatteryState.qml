pragma Singleton

import QtQml
import QtQuick
import Quickshell
import Quickshell.Io

// Every battery reading in the shell, produced once for the whole bar.
//
// This replaces a per-screen Process that shelled out to Battery.sh, for the
// two reasons SystemStats.qml exists: the bar is instantiated per screen, so a
// widget that shells out shells out N times to produce one number; and
// /sys/class/power_supply is a pile of plain files this process can read
// itself.
//
// One file per pack does it. `uevent` carries STATUS, CAPACITY, ENERGY_*,
// POWER_NOW, CYCLE_COUNT and the rest in a single KEY=VALUE blob, so a whole
// battery costs one FileView rather than nine. The charge thresholds are the
// exception - they are not in uevent and get their own views.
//
// The trigger is `udevadm monitor`, not a timer and not FileView's watchChanges:
// sysfs attributes do not raise inotify events, so watchChanges would bind and
// then never fire. udev is the kernel's actual notification for this subsystem.
// The 60s timer behind it only has to catch the monitor having died.
Singleton {
    id: root

    // ------------------------------------------------------------------
    //  Hardware, resolved once at startup by probeProc
    // ------------------------------------------------------------------
    property var paths: []            // one /sys dir per system battery
    property string mainsPath: ""     // AC / ADP1 / ACAD - the name varies
    property bool helperInstalled: false

    readonly property bool present: paths.length > 0

    // ------------------------------------------------------------------
    //  Readings
    // ------------------------------------------------------------------
    property var packs: []            // per battery, in /sys order
    property int level: 0             // energy-weighted, see aggregate()
    property bool onAc: true
    property real drawWatts: 0        // total, in or out
    property real energyNow: 0        // uWh
    property real energyFull: 0
    property real energyDesign: 0
    property int cycles: 0            // highest of the packs
    property real secondsLeft: -1     // -1 when there is nothing to predict

    // "charging" | "discharging" | "holding" | "full" | "idle" | "unknown"
    property string chargeState: "unknown"

    // Charge thresholds. 0 means "this machine does not have them" - the bar
    // hides the limit control rather than offering one that does nothing.
    property int limitEnd: 0
    property int limitStart: 0
    property bool limitSupported: false

    // Writing a threshold needs root, and root here is the helper installed by
    // install-scripts/battery_charge_limit.sh. Without it the readout still
    // works; only the picker is withheld.
    readonly property bool limitWritable: limitSupported && helperInstalled

    // What the user just asked for, while the write is still in flight. 0 when
    // nothing is pending.
    //
    // The card binds to effectiveLimit, not limitEnd, so a click lands on the
    // pill immediately instead of after the round trip. That round trip is not
    // slow by accident: sudo is ~20ms, the helper ~14ms, and re-reading the
    // thresholds afterwards costs another ~4.3ms because
    // charge_control_*_threshold are ACPI calls rather than cached kernel
    // values - 1.07ms each against 47us for the whole of uevent. Waiting for
    // all of that before even starting the 130ms fade put the confirmation
    // around 170ms after the click, which reads as a laggy button.
    property int pendingLimit: 0
    readonly property int effectiveLimit: pendingLimit > 0 ? pendingLimit : limitEnd

    readonly property int health: energyDesign > 0
        ? Math.round(100 * energyFull / energyDesign)
        : 0

    // Charging into a limit looks exactly like a full battery from the bar:
    // the pack stops taking current well short of 100%. Say which it is.
    readonly property bool holding: chargeState === "holding"

    // ------------------------------------------------------------------
    //  One battery. dir is a /sys/class/power_supply/BAT* directory.
    // ------------------------------------------------------------------
    component Probe: QtObject {
        id: probe
        property string dir: ""

        property FileView uevent: FileView {
            path: probe.dir === "" ? "" : probe.dir + "/uevent"
            // blockAllReads, NOT blockLoading. blockLoading only makes the
            // *initial* load synchronous; after that reload() starts an async
            // read and text() keeps returning the previous contents until it
            // lands, so every reading here would be one refresh stale.
            //
            // That is not a subtle staleness. It is what made the limit pills
            // need two clicks: the write landed, the read after it returned the
            // value from before the write, pendingLimit was dropped in favour of
            // it, and the pill snapped back. Measured while chasing it - three
            // reload()+text() pairs in the same turn all returned the old value,
            // and it only caught up on the next tick.
            blockAllReads: true
            printErrors: false
        }
        // Not in uevent, so they cost a view each. They only change when
        // something writes them, which is why nothing reloads them on a tick.
        property FileView endFile: FileView {
            path: probe.dir === "" ? "" : probe.dir + "/charge_control_end_threshold"
            blockAllReads: true
            printErrors: false
        }
        property FileView startFile: FileView {
            path: probe.dir === "" ? "" : probe.dir + "/charge_control_start_threshold"
            blockAllReads: true
            printErrors: false
        }

        function read(withLimits) {
            if (probe.dir === "")
                return null

            uevent.reload()
            var kv = {}
            var lines = uevent.text().split("\n")
            for (var i = 0; i < lines.length; i++) {
                var eq = lines[i].indexOf("=")
                if (eq > 0)
                    kv[lines[i].substring(0, eq)] = lines[i].substring(eq + 1).trim()
            }
            if (Object.keys(kv).length === 0)
                return null

            function num(key) {
                var v = Number(kv["POWER_SUPPLY_" + key])
                return isNaN(v) ? 0 : v
            }

            var volts = num("VOLTAGE_NOW")

            // Two conventions in the wild: energy_* in uWh with power_now in
            // uW (most Intel laptops, including this ThinkPad), or charge_* in
            // uAh with current_now in uA (many others, and most phones-on-a-
            // laptop-board designs). Normalise everything to uWh/uW here so
            // nothing downstream has to know which kind of pack it is looking
            // at; without this the card reads 0 Wh and "—" on half the
            // machines this repo installs on.
            var eNow = num("ENERGY_NOW")
            var eFull = num("ENERGY_FULL")
            var eDesign = num("ENERGY_FULL_DESIGN")
            var pNow = num("POWER_NOW")
            if (eFull === 0 && volts > 0) {
                eNow = num("CHARGE_NOW") * volts / 1000000
                eFull = num("CHARGE_FULL") * volts / 1000000
                eDesign = num("CHARGE_FULL_DESIGN") * volts / 1000000
                pNow = num("CURRENT_NOW") * volts / 1000000
            }

            var capacity = num("CAPACITY")
            if (capacity === 0 && eFull > 0)
                capacity = Math.round(100 * eNow / eFull)

            var pack = {
                name: kv["POWER_SUPPLY_NAME"] || "BAT",
                status: kv["POWER_SUPPLY_STATUS"] || "Unknown",
                model: kv["POWER_SUPPLY_MODEL_NAME"] || "",
                capacity: capacity,
                energyNow: eNow,
                energyFull: eFull,
                energyDesign: eDesign,
                powerNow: Math.abs(pNow),
                cycles: num("CYCLE_COUNT"),
                health: eDesign > 0 ? Math.round(100 * eFull / eDesign) : 0,
                limitEnd: 0,
                limitStart: 0
            }

            if (withLimits) {
                endFile.reload()
                startFile.reload()
                var e = parseInt(endFile.text())
                var s = parseInt(startFile.text())
                pack.limitEnd = isNaN(e) ? 0 : e
                pack.limitStart = isNaN(s) ? 0 : s
            }

            return pack
        }
    }

    Instantiator {
        id: probes
        model: root.paths
        delegate: Probe { dir: modelData }
    }

    FileView {
        id: mainsFile
        path: root.mainsPath === "" ? "" : root.mainsPath + "/uevent"
        blockAllReads: true
        printErrors: false
    }

    // ------------------------------------------------------------------
    //  Aggregation
    // ------------------------------------------------------------------

    function readMains() {
        if (root.mainsPath === "") {
            // No mains device at all. Trust the packs: if none of them is
            // discharging, assume we are plugged in.
            return true
        }
        mainsFile.reload()
        return mainsFile.text().indexOf("POWER_SUPPLY_ONLINE=1") >= 0
    }

    function refresh(withLimits) {
        if (!root.present)
            return

        var list = []
        for (var i = 0; i < probes.count; i++) {
            var pack = probes.objectAt(i).read(withLimits === true)
            if (pack)
                list.push(pack)
        }
        if (list.length === 0)
            return

        root.packs = list
        root.onAc = readMains()
        aggregate(withLimits === true)
    }

    function aggregate(withLimits) {
        var eNow = 0, eFull = 0, eDesign = 0, watts = 0, cyc = 0
        var anyCharging = false, anyDischarging = false, allFull = true
        var endLimit = 0, startLimit = 0, haveLimit = false

        for (var i = 0; i < root.packs.length; i++) {
            var p = root.packs[i]
            eNow += p.energyNow
            eFull += p.energyFull
            eDesign += p.energyDesign
            watts += p.powerNow
            cyc = Math.max(cyc, p.cycles)

            if (p.status === "Charging") anyCharging = true
            if (p.status === "Discharging") anyDischarging = true
            if (p.status !== "Full") allFull = false

            if (withLimits && p.limitEnd > 0) {
                haveLimit = true
                // Packs are set together, so the first one that reports a
                // threshold speaks for the machine.
                if (endLimit === 0) {
                    endLimit = p.limitEnd
                    startLimit = p.limitStart
                }
            }
        }

        root.energyNow = eNow
        root.energyFull = eFull
        root.energyDesign = eDesign
        root.drawWatts = watts / 1000000
        root.cycles = cyc

        if (withLimits) {
            root.limitSupported = haveLimit
            root.limitEnd = endLimit
            root.limitStart = startLimit
        }

        // Energy-weighted, not the mean of the percentages. On this T480 the
        // internal pack is down to 10.7Wh against the removable one's 19.7Wh,
        // so averaging "97% and 97%" hid the fact that one of them holds less
        // than half as much charge as the other. Two packs at 100% and 20%
        // are not "60%" of anything you can run on.
        root.level = eFull > 0
            ? Math.max(0, Math.min(100, Math.round(100 * eNow / eFull)))
            : 0

        root.chargeState = classify(anyCharging, anyDischarging, allFull)
        root.secondsLeft = predict(anyDischarging)
    }

    function classify(anyCharging, anyDischarging, allFull) {
        if (anyDischarging || !root.onAc)
            return "discharging"

        // Real current flowing in. Below 0.2W the pack is topping off at best,
        // and reporting "charging" there makes the card claim a time-to-full
        // that never arrives.
        if (anyCharging && root.drawWatts > 0.2)
            return "charging"

        // Plugged in, not taking current, and short of full. Either the charge
        // limit is doing its job, or the firmware is sitting in its own
        // hysteresis band below 100%. Only the first is worth a label of its
        // own - "Holding at 100%" would be nonsense.
        if (root.limitEnd > 0 && root.limitEnd < 99 && root.level >= root.limitEnd - 2)
            return "holding"

        if (allFull || root.level >= 97)
            return "full"

        return "idle"
    }

    function predict(anyDischarging) {
        if (root.drawWatts <= 0.2)
            return -1
        if (anyDischarging)
            return (root.energyNow / 1000000) / root.drawWatts * 3600
        if (root.chargeState === "charging") {
            // Charging stops at the limit, not at the top of the pack, so the
            // target is the limit whenever one is set.
            var target = (root.limitEnd > 0 && root.limitEnd < 100)
                ? root.energyFull * root.limitEnd / 100
                : root.energyFull
            var missing = (target - root.energyNow) / 1000000
            if (missing <= 0)
                return -1
            return missing / root.drawWatts * 3600
        }
        return -1
    }

    // ------------------------------------------------------------------
    //  Setting the limit
    // ------------------------------------------------------------------

    // Writes the threshold to every pack and persists it, via the root helper
    // installed by install-scripts/battery_charge_limit.sh. sudo is
    // passwordless here (see install-scripts/sudoers_nopasswd.sh), which is
    // what lets a QML Process call it with no tty to prompt on.
    function setLimit(percent) {
        if (!root.limitWritable || limitProc.running)
            return
        root.pendingLimit = percent
        limitProc.command = ["sudo", "-n", "/usr/local/bin/battery-charge-limit",
                             "set", String(percent)]
        limitProc.running = true
    }

    Process {
        id: limitProc
        onExited: {
            // Re-read rather than trusting the write: thinkpad_acpi silently
            // clamps values some firmware will not take, and the card should
            // show what the hardware accepted, not what it was asked for. The
            // optimistic value is dropped here, so if the hardware refused,
            // the pill moves back on its own rather than lying.
            root.refresh(true)
            root.pendingLimit = 0
        }
    }

    // Re-read the thresholds alone. Called when the card opens, so a limit
    // changed from a terminal or by TLP shows up, without paying for the ACPI
    // reads on a tick nobody is looking at.
    function readThresholds() {
        if (root.present)
            root.refresh(true)
    }

    // ------------------------------------------------------------------
    //  Discovery and change notification
    // ------------------------------------------------------------------

    // Which power supplies are real system batteries, and where mains is.
    // `scope` is the filter that matters: a Bluetooth mouse or a headset shows
    // up under power_supply as type=Battery too, and counting one of those as
    // a pack puts a phantom 100% battery in the bar of a desktop.
    Process {
        id: probeProc
        command: ["sh", "-c",
            'for d in /sys/class/power_supply/*; do\n' +
            '  [ -r "$d/type" ] || continue\n' +
            '  case "$(cat "$d/type")" in\n' +
            '    Battery)\n' +
            '      [ "$(cat "$d/scope" 2>/dev/null || echo System)" = "System" ] || continue\n' +
            '      [ "$(cat "$d/present" 2>/dev/null || echo 1)" = "1" ] || continue\n' +
            '      printf "bat\\t%s\\n" "$d" ;;\n' +
            '    Mains)\n' +
            '      printf "mains\\t%s\\n" "$d" ;;\n' +
            '  esac\n' +
            'done\n' +
            '[ -x /usr/local/bin/battery-charge-limit ] && printf "helper\\t1\\n"\n' +
            'exit 0\n'
        ]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var found = []
                var mains = ""
                var helper = false
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var t = lines[i].indexOf("\t")
                    if (t < 0) continue
                    var key = lines[i].substring(0, t)
                    var val = lines[i].substring(t + 1).trim()
                    if (key === "bat") found.push(val)
                    else if (key === "mains" && mains === "") mains = val
                    else if (key === "helper") helper = true
                }
                root.mainsPath = mains
                root.helperInstalled = helper
                root.paths = found
                if (found.length > 0)
                    root.refresh(true)
            }
        }
    }

    Process {
        id: monitor
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=power_supply"]
        running: root.present
        stdout: SplitParser {
            onRead: data => {
                if (data && data.indexOf("power_supply") >= 0)
                    root.refresh(false)
            }
        }
    }

    // udev reports plug, unplug and the coarse capacity steps, but not a slow
    // drift between them, and this is also the net behind the monitor having
    // died.
    //
    // It re-reads the thresholds too, and that is a deliberate reversal. They
    // are ACPI calls - 1.07ms each against 47us for a whole uevent, so 4.3ms of
    // GUI-thread blocking with two packs - and dropping them from this tick
    // looked like free money. It is not: the limit decides whether the bar shows
    // "holding" or "full", so a limit set from a terminal, by TLP, or by this
    // shell's own helper left the wrong glyph in the bar until someone happened
    // to open the card. 4.3ms a minute is 0.007% of one core and cannot drop a
    // frame at 60Hz. Correctness wins.
    Timer {
        interval: 60000
        running: root.present
        repeat: true
        onTriggered: root.refresh(true)
    }

    Component.onCompleted: probeProc.running = true
}
