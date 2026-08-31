// Quickshell desktop shell, M1 + M2: one bar per screen (workspaces,
// focused window title, clock, system tray) and the notifications daemon
// (toast stack, do-not-disturb, in-memory history).
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
}
