import QtQuick
import Quickshell

// Creates a dialog's window only while it is wanted, and destroys it again
// once it has faded out.
//
// Every centred dialog is its own PanelWindow, and a hidden one still costs
// 6-10MB just by existing - even with its contents loaded on demand, as the
// wallpaper carousel's are. Most of them are opened a few times a day, so they
// are created on open instead of at startup:
//
//     Variants {
//         model: Quickshell.screens
//         OnDemand {
//             id: slot
//             required property var modelData
//             open: ShotState.dialogOpen
//             ShotOsd { modelData: slot.modelData }
//         }
//     }
//
// The dialog itself must not count as shown until it is complete (its `ready`
// flag), so it sees the usual hidden-to-shown change and runs its normal open
// code, fade-in included. The global shortcuts live in the *State singletons,
// not in the windows, so they keep working while no window exists.
Scope {
    id: root

    // True while the dialog should be on screen.
    property bool open: false
    // How long the window outlives `open`: the dialogs fade out for 160ms
    // and hide 160ms later, so this covers both with room to spare.
    property int holdMs: 600

    default property Component window

    onOpenChanged: if (!open) hold.restart()

    Timer {
        id: hold
        interval: root.holdMs
    }

    LazyLoader {
        active: root.open || hold.running
        component: root.window
    }
}
