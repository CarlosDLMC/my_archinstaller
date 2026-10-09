pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Polkit

// The polkit authentication agent - the password prompt graphical programs
// get when they ask for admin rights (mounting a disk in Thunar, pkexec,
// GUI settings that change the system).
//
// It replaces hyprpolkitagent, a separate Qt process that idled at 70-100MB
// for a dialog seen a few times a month. Quickshell has the agent built in, so
// the bar that is already running provides it; Polkit.sh no longer starts
// another one when this file is present (polkit takes one agent per session).
//
// A singleton because the overlay is instantiated per screen (like
// ClipboardOsd), and the agent must be registered exactly once.
Singleton {
    id: root

    readonly property var flow: agent.flow
    readonly property bool open: agent.isActive && flow !== null
    readonly property bool registered: agent.isRegistered

    // Our own line for a wrong password: polkit only says the attempt failed.
    property string error: ""

    // Between Enter and polkit's answer. A wrong password takes ~2s to come
    // back - PAM's fail delay, there to slow down guessing - and without this
    // the card sat there looking as if Enter had done nothing.
    property bool checking: false

    PolkitAgent { id: agent }

    onFlowChanged: { error = ""; checking = false }

    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onAuthenticationFailed() { root.error = "Wrong password - try again"; root.checking = false }
        function onAuthenticationSucceeded() { root.error = ""; root.checking = false }
        function onAuthenticationRequestCancelled() { root.error = ""; root.checking = false }
        function onIsResponseRequiredChanged() { if (root.flow.isResponseRequired) root.checking = false }
    }

    function submit(text) {
        if (!flow || !flow.isResponseRequired) return
        error = ""
        checking = true
        flow.submit(text)
    }

    function cancel() {
        if (flow) flow.cancelAuthenticationRequest()
    }
}
