// Quickshell desktop shell, M1 + M2 + M3 + M4: one bar per screen
// (workspaces, focused window title, clock, system tray), the notifications
// daemon (toast stack, do-not-disturb, in-memory history), the launcher
// (fuzzy app search over desktop entries, launched through uwsm), the lock
// screen (ext-session-lock + PAM), the idle policy (lock / suspend timers),
// and the session menu (power actions).
//
// The architecture follows Omarchy Quattro: a single long-running Quickshell
// instance hosts the whole desktop; bar, launcher, notifications, lock, etc.
// grow here as milestones. See https://github.com/basecamp/omarchy (MIT).
import Quickshell
import QtQuick

ShellRoot {
  Variants {
    model: Quickshell.screens

    delegate: Component {
      Bar {
        required property var modelData

        screen: modelData
      }
    }
  }

  // One notifications daemon for the session; it opens its own toast
  // window per screen (see Notifications.qml).
  Notifications { }

  // The launcher opens its own overlay on the focused monitor (see
  // Launcher.qml).
  Launcher { }

  // M4: lock + idle. Idle locks through the Lock instance in-process; the
  // session menu locks/suspends through it too.
  Lock { id: lock }
  Idle { lock: lock }
  SessionMenu { lock: lock }
}
