// M4: the idle policy. Two IdleMonitors (ext-idle-notify-v1, so wayland
// idle inhibitors — fullscreen video players and friends — are respected)
// replace the hypridle daemon Omarchy used before Quattro: five idle
// minutes lock the session (Omarchy's default), thirty suspend it. The
// display itself blanks five seconds after the lock engages or the last
// lock-screen event — that lives in Lock.qml with the lock surface.
//
// Locking happens in-process (the shell owns the lock), suspending goes
// through systemctl (logind allows it for local active sessions without
// polkit). Suspend from outside the shell — the power menu and the idle
// timer both lock first; a lid close or an external `systemctl suspend`
// does not, which is the same gap Omarchy's menu-only suspend has on
// desktops.
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: service

  // Wired to the shell's Lock instance by shell.qml.
  property var lock: null

  // ----- tuning ------------------------------------------------------------
  //
  // Omarchy Quattro's defaults: lock at 300s, suspend at 1800s (their
  // hypridle recipe before Quattro grew the idle service).

  readonly property int lockTimeoutSeconds: 300
  readonly property int suspendTimeoutSeconds: 1800

  // ----- idle -> lock --------------------------------------------------------

  IdleMonitor {
    id: lockMonitor

    timeout: service.lockTimeoutSeconds
    respectInhibitors: true

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
    enabled: service.lock !== null && service.lock.locked

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
  // `qs ipc call idle status` for debugging the timers.

  IpcHandler {
    target: "idle"

    function status(): string {
      return JSON.stringify({
        lockTimeoutSeconds: service.lockTimeoutSeconds,
        suspendTimeoutSeconds: service.suspendTimeoutSeconds,
        idle: lockMonitor.isIdle,
        lockMonitorEnabled: lockMonitor.enabled,
        suspendIdle: suspendMonitor.isIdle,
        suspendMonitorEnabled: suspendMonitor.enabled
      })
    }

    function ping(): string {
      return "ok"
    }
  }
}
