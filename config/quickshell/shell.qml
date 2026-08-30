// Quickshell desktop shell, M1: one bar per screen (workspaces, focused
// window, clock, system tray).
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
}
