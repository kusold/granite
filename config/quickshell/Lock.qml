// M4: the lock screen. Quickshell's WlSessionLock speaks ext-session-lock-v1
// (the proper Wayland session lock protocol: input is grabbed, other
// surfaces cannot cover the lock), and a PamContext authenticates the
// session password against the granite-lock PAM service the host's NixOS
// config ships (/etc/pam.d/granite-lock — home-manager cannot create it).
//
// Omarchy Quattro behaviors kept here, simplified: one password field per
// monitor sharing a single password state, dots that shrink to fit,
// "Checking…" / failure feedback, Escape and Ctrl+U clear the field, the
// display blanks five seconds after the last event while locked (input
// wakes it — see misc.key_press_enables_dpms in hyprland.lua), and a
// stranded compositor lock (shell crashed while locked; ext-session-lock
// outlives its client) is detected via hyprctl and taken over so it can be
// unlocked with the password. Still deliberately NOT here vs Omarchy:
// fingerprint auth, the lock preview mode, and wallpaper blurring (there is
// no wallpaper until M6) — the solid background matches granite's palette.
//
// Driven by keybinds (`qs ipc call lock lock`), the idle timers (Idle.qml
// and the session menu call beginLock() in-process), and suspend flows.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import QtQuick

Item {
  id: service

  // Palette shared with Bar.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"
  readonly property color critical: "#ff5555"
  readonly property color background: "#101014"

  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""

  // Dots render at dotFontSize and shrink to fit; the placeholder renders
  // at fieldFontSize (Omarchy's sizes, scaled to granite's field).
  readonly property int dotFontSize: 20
  readonly property int fieldFontSize: 15

  // ----- state -------------------------------------------------------------

  property bool lockRequested: false
  property bool authenticatingPassword: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool displayBlanked: false

  // The live config reload recreates this whole tree, but WlSessionLock
  // survives it (it is Reloadable) and keeps the protocol lock held — so
  // `locked` must stay true through a reload while locked, while a fresh
  // lockRequested alone would read false (Omarchy's lesson).
  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure

  // No lock before PAM is known good: without a working /etc/pam.d entry a
  // lock could never be unlocked.
  property bool passwordPamConfigured: false

  FileView {
    path: "/etc/pam.d/granite-lock"
    watchChanges: true
    printErrors: false
    onLoaded: service.passwordPamConfigured = true
    onLoadFailed: service.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // ----- locking / unlocking ----------------------------------------------

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    if (passwordPam.active) passwordPam.abort()
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      console.warn("lock: /etc/pam.d/granite-lock missing — refusing to lock")
      return false
    }

    resetAuthenticationState()
    displayBlanked = false
    lockRequested = true
    armBlankTimer()
    requestSessionLock()
    return true
  }

  function finishUnlock() {
    if (!locked && !lockRequested) return

    lockRequested = false
    lockRetryTimer.stop()
    resetAuthenticationState()
    blankTimer.stop()
    runWake()
    sessionLock.locked = false
  }

  // Screens may still be settling (dpms wake, hotplug); retry until the
  // compositor actually engages the lock, like Omarchy's pending timers.
  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (Quickshell.screens.length === 0) {
      if (!lockRetryTimer.running) lockRetryTimer.start()
      return
    }
    sessionLock.locked = true
    if (!lockRetryTimer.running) lockRetryTimer.start()
  }

  Timer {
    id: lockRetryTimer

    interval: 100
    repeat: true
    onTriggered: service.requestSessionLock()
  }

  // ----- display blanking ---------------------------------------------------
  //
  // Five seconds after the last event while locked, blank the display; any
  // input wakes it (key_press/mouse_move_enables_dpms). Password checks in
  // flight hold the display up, like Omarchy.

  function armBlankTimer() {
    blankTimer.armedAt = Date.now()
    blankTimer.restart()
  }

  function runWake() {
    if (displayBlanked) {
      displayBlanked = false
      dispatchDpms(true)
    }
    // locked (not lockRequested): a live config reload recreates this tree
    // with lockRequested false while the surviving WlSessionLock still
    // holds the protocol lock, and the post-reload session must keep
    // blanking and stay unlockable.
    if (locked) armBlankTimer()
  }

  function runBlank() {
    if (displayBlanked) return
    displayBlanked = true
    dispatchDpms(false)
  }

  // Hyprland >= 0.55 with a Lua config evaluates request-socket payloads as
  // Lua and hl.dispatch wants a dispatcher OBJECT, so the classic
  // "dpms on" string form is a syntax error — build the hl.dsp.* call
  // instead (the same reason Bar.qml's workspace clicks needed fixing).
  // The state must be a STRING: a Lua boolean stringifies to "true"/"false",
  // which the dispatcher treats as unrecognized and toggles instead.
  function dispatchDpms(on) {
    Hyprland.dispatch(on ? 'hl.dsp.dpms({ on = "on" })' : 'hl.dsp.dpms({ on = "off" })')
  }

  Timer {
    id: blankTimer

    interval: 5000
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock
      // time exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        service.armBlankTimer()
        return
      }
      if (service.locked && !service.authenticatingPassword) service.runBlank()
    }
  }

  // ----- password authentication --------------------------------------------

  function submitPassword(value) {
    var password = String(value || "")
    if (!locked || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true
    blankTimer.stop()

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  function handlePasswordFailure() {
    if (!locked) return

    authenticatingPassword = false
    enteredPassword = ""
    pendingPassword = ""
    failedAttempts += 1
    failureMessage = "Authentication failed (" + failedAttempts + ")"
    runWake()
  }

  PamContext {
    id: passwordPam

    config: "granite-lock"
    user: service.userName

    onResponseRequiredChanged: service.respondToPasswordPrompt()
    onPamMessage: service.respondToPasswordPrompt()

    onCompleted: function(result) {
      service.authenticatingPassword = false
      service.pendingPassword = ""

      if (!service.locked) return
      if (result === PamResult.Success) service.finishUnlock()
      else service.handlePasswordFailure()
    }

    onError: service.handlePasswordFailure()
  }

  // ----- the lock surface ----------------------------------------------------
  //
  // One WlSessionLockSurface per output (quickshell instantiates the
  // component below for every screen); all of them share the service-level
  // password state, so the dots track typing no matter which monitor has
  // keyboard focus.

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: if (secure) lockRetryTimer.stop()
    onLockStateChanged: {
      if (locked) lockRetryTimer.stop()

      // The compositor dropped the lock (unlock from elsewhere): stop
      // acting locked.
      if (!locked && lockRequested) {
        lockRequested = false
        lockRetryTimer.stop()
        resetAuthenticationState()
        runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface

      color: service.background

      // Any event wakes the display and re-arms the blank timer, like
      // Omarchy's wakeRequested.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
          service.runWake()
          passwordInput.forceActiveFocus()
        }
        onPositionChanged: service.runWake()
      }

      // Measures the masked password at full size; passwordDotScale shrinks
      // the dots once the password outgrows the field so every keystroke
      // stays visible instead of clipping away.
      TextMetrics {
        id: dotMetrics

        font.family: service.fontFamily
        font.pixelSize: service.dotFontSize
        text: "●".repeat(passwordInput.text.length)
      }

      Rectangle {
        id: inputField

        width: 340
        height: 56
        radius: 8
        anchors.centerIn: parent
        color: "#f0101014"
        border.width: 2
        border.color: service.failureMessage.length > 0 ? "#66ff5555" : service.authenticatingPassword ? service.accent : "#26ffffff"

        TextInput {
          id: passwordInput

          property bool syncingPasswordText: false

          anchors.fill: parent
          anchors.leftMargin: 16
          anchors.rightMargin: 16
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignHCenter
          activeFocusOnPress: true
          clip: true
          enabled: service.locked && !service.authenticatingPassword
          readOnly: service.authenticatingPassword
          echoMode: TextInput.Password
          passwordCharacter: "●"
          passwordMaskDelay: 0
          color: service.foreground
          selectionColor: service.accent
          selectedTextColor: "#101014"
          font.family: service.fontFamily
          font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(service.dotFontSize * lockSurface.dotScale)) : service.fieldFontSize
          cursorVisible: activeFocus && text.length > 0 && !service.authenticatingPassword && service.failureMessage.length === 0

          // The shared password state and the field's own text meet here:
          // typing pushes up to the service (which mirrors it onto every
          // surface), and a mirrored change lands back without fighting the
          // edit that caused it (Omarchy's syncingPasswordText guard).
          onTextChanged: {
            if (!syncingPasswordText) service.enteredPassword = text
            if (text.length > 0) service.runWake()
            if (text.length > 0 && service.failureMessage.length > 0) service.failureMessage = ""
          }

          onAccepted: {
            var submitted = service.enteredPassword
            service.enteredPassword = ""
            if (submitted.length > 0) service.submitPassword(submitted)
          }

          Keys.onPressed: function(event) {
            service.runWake()
            if (event.key === Qt.Key_Escape || ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_U)) {
              service.enteredPassword = ""
              event.accepted = true
            }
          }
        }

        // Placeholder / checking / failure text under the dots.
        Text {
          anchors.fill: passwordInput
          textFormat: Text.PlainText
          visible: passwordInput.text.length === 0
          text: service.authenticatingPassword ? "Checking…" : (service.failureMessage.length > 0 ? service.failureMessage : "Enter Password")
          color: service.authenticatingPassword || service.failureMessage.length > 0 ? service.critical : service.foreground
          opacity: service.failureMessage.length === 0 && !service.authenticatingPassword ? 0.5 : 1
          font.family: service.fontFamily
          font.pixelSize: service.fieldFontSize
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }
      }

      // The dots shrink to fit the field — measured against the unshrunk
      // mask so the scale knows how wide the password really wants to be.
      readonly property real dotScale: dotMetrics.advanceWidth > 0
        ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
        : 1

      onVisibleChanged: if (visible) Qt.callLater(passwordInput.forceActiveFocus)
      Component.onCompleted: Qt.callLater(passwordInput.forceActiveFocus)

      Connections {
        target: service

        // A mirrored password update from another monitor's field lands as
        // a programmatic set here (or on re-lock clearing the field).
        function onEnteredPasswordChanged() {
          if (passwordInput.text === service.enteredPassword) return
          passwordInput.syncingPasswordText = true
          passwordInput.text = service.enteredPassword
          passwordInput.syncingPasswordText = false
        }

        // Focus the field when the lock engages, wherever it lands —
        // onLockedChanged, so a lock that survived a config reload (via the
        // WlSessionLock) focuses its fresh surface too — and again once a
        // password check finishes (a disabled field loses focus).
        function onLockedChanged() {
          if (service.locked) Qt.callLater(passwordInput.forceActiveFocus)
        }

        function onAuthenticatingPasswordChanged() {
          if (!service.authenticatingPassword && service.locked)
            Qt.callLater(passwordInput.forceActiveFocus)
        }
      }
    }
  }

  // ----- stranded lock recovery ----------------------------------------------
  //
  // ext-session-lock outlives its client: if the shell dies while locked,
  // Hyprland keeps the session locked and only a new lock client can clear
  // it. Hyprland reports no lock state directly, but an active session lock
  // is one of the reasons a monitor cannot go solitary — LOCK in
  // solitaryBlockedBy (Omarchy's omarchy-hyprland-session-locked recipe).
  // Requires hyprctl in PATH, which the host's programs.hyprland provides.

  property bool strandedLock: false
  property bool strandedLockResolved: false

  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (locked || lockRequested) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function parseLockState(raw) {
    // 0 = compositor holds a lock, 1 = unlocked, 2 = undetermined.
    var monitors
    try {
      monitors = JSON.parse(String(raw || ""))
    } catch (e) {
      return 2
    }
    if (!Array.isArray(monitors) || monitors.length === 0) return 2

    var locked = false
    var readable = false
    for (var i = 0; i < monitors.length; i++) {
      var blockers = monitors[i].solitaryBlockedBy
      if (!Array.isArray(blockers)) continue
      if (blockers.indexOf("LOCK") !== -1) locked = true
      if (blockers.indexOf("WORKSPACE") === -1) readable = true
    }
    if (locked) return 0
    if (readable) return 1
    return 2
  }

  function evalStrandedLock(raw) {
    var state = parseLockState(raw)
    // Undetermined: a monitor still coming up has no workspace, so it stops
    // at the first blocker before ever reaching the lock — ask again.
    if (state === 2) return

    strandedLockResolved = true
    strandedLock = state === 0
    recoverStrandedLock()
  }

  function recoverStrandedLock() {
    if (!strandedLock || locked || !passwordPamConfigured) return

    strandedLock = false
    console.warn("lock: taking over a stranded session lock")
    beginLock()
  }

  Process {
    id: strandedLockCheckProc

    command: ["hyprctl", "-j", "monitors"]
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.evalStrandedLock(text)
    }
  }

  Timer {
    id: strandedRetryTimer

    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !service.strandedLockResolved && remaining > 0

    function rearm() {
      if (!service.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      service.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell

    function onScreensChanged() {
      requestSessionLock()
      strandedRetryTimer.rearm()
      checkStrandedLock()
    }
  }

  // No lock before PAM is known good. An answer from before then may be
  // stale — the failsafe can be cleared from a TTY — so re-ask.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: checkStrandedLock()

  // Hold the display up while a password check runs (the blank timer is
  // stopped for its duration and re-armed afterwards).
  onAuthenticatingPasswordChanged: {
    if (!locked) return
    if (authenticatingPassword) blankTimer.stop()
    else armBlankTimer()
  }

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call lock lock`.

  IpcHandler {
    target: "lock"

    function lock(): string {
      if (!service.passwordPamConfigured) return "missing-pam"
      if (!service.locked && !service.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return service.locked ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: service.locked,
        requested: service.lockRequested,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        pam: service.passwordPamConfigured,
        authenticating: service.authenticatingPassword,
        blanked: service.displayBlanked
      })
    }

    function ping(): string {
      return "ok"
    }
  }
}
