// M4: the idle policy. Two IdleMonitors (ext-idle-notify-v1, so wayland
// idle inhibitors — fullscreen video players and friends — are respected)
// replace the hypridle daemon Omarchy used before Quattro: five idle
// minutes lock the session (Omarchy's default), thirty suspend it. The
// display itself blanks five seconds after the lock engages or the last
// lock-screen event — that lives in Lock.qml with the lock surface.
// M6 adds the stage before these: Screensaver.qml's own monitor brings
// the screensaver up at 150s (Omarchy's default), sharing the same idle
// clock, so any activity resets all three at once.
//
// Locking happens in-process (the shell owns the lock), suspending goes
// through systemctl (logind allows it for local active sessions without
// polkit). Suspend from outside the shell — the power menu and the idle
// timer both lock first; a lid close or an external `systemctl suspend`
// does not, which is the same gap Omarchy's menu-only suspend has on
// desktops.
//
// M9's first toggle: stay awake (Omarchy Quattro's "Toggle locking on
// idle"). While on, the whole idle policy stands down — no screensaver
// (Screensaver.qml's monitor gates on this too), no idle lock, no idle
// suspend — until toggled off. SUPER+CTRL+I and the bar's coffee glyph
// both flip the switch (`qs ipc call idle toggle`); the state persists
// across reloads and restarts like Omarchy's indicators/stay-awake file,
// but as granite's JSON settings (~/.local/state/granite/idle.json).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: service

  // Wired to the shell's Lock instance by shell.qml.
  property var lock: null

  // Wired to the shell's Notifications instance by shell.qml, so the
  // toggle can confirm itself with a toast.
  property var notifications: null

  // ----- tuning ------------------------------------------------------------
  //
  // Omarchy Quattro's defaults: lock at 300s, suspend at 1800s (their
  // hypridle recipe before Quattro grew the idle service).

  readonly property int lockTimeoutSeconds: 300
  readonly property int suspendTimeoutSeconds: 1800

  // ----- stay awake (M9) ----------------------------------------------------

  // PersistentProperties carries stay-awake across live config reloads;
  // the idle.json file below carries it across shell restarts (Omarchy's
  // stay-awake marker file, granite's settings shape).
  PersistentProperties {
    id: persisted

    reloadableId: "granite-idle"
    property bool stayAwake: false
  }

  readonly property alias stayAwake: persisted.stayAwake

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/granite/idle.json"

  FileView {
    id: settingsFile

    path: service.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadSettings(text())
    // First run: the file doesn't exist yet — treat as defaults and let the
    // first toggle write it.
    onLoadFailed: service.loadSettings("")
  }

  Timer {
    id: settingsSaveTimer

    interval: 200
    onTriggered: settingsFile.setText(JSON.stringify({ stayAwake: persisted.stayAwake }) + "\n")
  }

  property bool settingsLoaded: false

  function loadSettings(raw) {
    // FileView can fire onLoaded more than once during startup; the first
    // read is authoritative.
    if (service.settingsLoaded) return
    service.settingsLoaded = true

    var text = String(raw || "").trim()
    if (!text) return
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed.stayAwake === "boolean")
        persisted.stayAwake = parsed.stayAwake
    } catch (e) {
      console.warn("idle: settings parse failed:", e)
    }
  }

  function toggleStayAwake() {
    setStayAwake(!persisted.stayAwake)
  }

  function setStayAwake(value) {
    persisted.stayAwake = !!value
    // The write-through is guarded so a load-time hydration can never
    // clobber the file with the default before it was read.
    if (service.settingsLoaded) settingsSaveTimer.restart()
    // Feedback for the flip — injected directly, so it shows even under
    // do-not-disturb (the user just acted; a silent toggle looks like a
    // dead keybind).
    if (service.notifications)
      service.notifications.shellToast(value ? "Stay awake on" : "Stay awake off")
  }

  // ----- idle -> lock --------------------------------------------------------

  IdleMonitor {
    id: lockMonitor

    timeout: service.lockTimeoutSeconds
    respectInhibitors: true
    enabled: !service.stayAwake

    onIsIdleChanged: {
      if (!isIdle) return
      if (!service.lock || service.lock.locked) return
      // beginLock refuses to lock without a working PAM service, so a
      // missing /etc/pam.d/granite-lock can never lock the user out.
      if (!service.lock.beginLock())
        console.warn("idle: lock unavailable (missing PAM service?)")
    }
  }

  // ----- idle -> suspend -----------------------------------------------------
  //
  // Enabled only while locked: an unlocked session sitting idle reaches the
  // lock timeout first, so by 30 minutes it is always locked, and a manual
  // unlock requires input — which resets the idle clock anyway. Enabling on
  // lock keeps the timeout anchored to the last activity, not to the moment
  // the monitor switched on.

  IdleMonitor {
    id: suspendMonitor

    timeout: service.suspendTimeoutSeconds
    respectInhibitors: true
    enabled: service.lock !== null && service.lock.locked && !service.stayAwake

    onIsIdleChanged: if (isIdle && enabled) service.suspend()
  }

  function suspend() {
    if (suspendProc.running) return
    suspendProc.running = true
  }

  // Detached, so a shell teardown during session end cannot orphan it.
  Process {
    id: suspendProc

    command: ["systemctl", "suspend"]
    running: false
  }

  // ----- IPC ---------------------------------------------------------------
  // `qs ipc call idle status` for debugging the timers; `toggle`,
  // `stayAwake`, and `allowIdle` are the stay-awake verbs (Omarchy's
  // omarchy-toggle-idle vocabulary) behind SUPER+CTRL+I and the bar glyph.

  IpcHandler {
    target: "idle"

    function status(): string {
      return JSON.stringify({
        lockTimeoutSeconds: service.lockTimeoutSeconds,
        suspendTimeoutSeconds: service.suspendTimeoutSeconds,
        stayAwake: service.stayAwake,
        idle: lockMonitor.isIdle,
        lockMonitorEnabled: lockMonitor.enabled,
        suspendIdle: suspendMonitor.isIdle,
        suspendMonitorEnabled: suspendMonitor.enabled
      })
    }

    function state(): string {
      return service.stayAwake ? "stay-awake" : "idle"
    }

    function toggle(): string {
      service.toggleStayAwake()
      return state()
    }

    function stayAwake(): string {
      service.setStayAwake(true)
      return state()
    }

    function allowIdle(): string {
      service.setStayAwake(false)
      return state()
    }

    function ping(): string {
      return "ok"
    }
  }
}
