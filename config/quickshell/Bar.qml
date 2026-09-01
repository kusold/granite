// The bar: dark top bar with workspaces and the focused window title on the
// left, a centered clock, and the system tray on the right.
// Styling and layout follow Omarchy Quattro's bar.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick

PanelWindow {
  id: root

  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"
  readonly property int barSize: 30

  anchors {
    top: true
    left: true
    right: true
  }

  implicitHeight: root.barSize
  exclusionMode: ExclusionMode.Auto
  color: "#e8101014"
  surfaceFormat.opaque: false
  WlrLayershell.namespace: "mike-bar"
  WlrLayershell.layer: WlrLayer.Top

  // ----- Left: workspaces + focused window --------------------------------

  Row {
    id: leftSection

    anchors.left: parent.left
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 4

    Repeater {
      // Omarchy's Workspaces widget: always offer 1-5, plus any occupied
      // workspace up to 10.
      model: {
        var ids = [1, 2, 3, 4, 5];
        var values = Hyprland.workspaces.values;
        for (var i = 0; i < values.length; i++) {
          var id = values[i].id;
          if (id > 0 && id <= 10 && ids.indexOf(id) === -1)
            ids.push(id);
        }
        ids.sort(function(left, right) { return left - right; });
        return ids;
      }

      delegate: Rectangle {
        required property int modelData

        readonly property var workspace: {
          var values = Hyprland.workspaces.values;
          for (var i = 0; i < values.length; i++) {
            if (values[i].id === modelData)
              return values[i];
          }
          return null;
        }
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        width: occupied || focused ? 26 : 18
        height: 22
        radius: 4
        color: focused ? root.accent : "transparent"
        opacity: occupied || focused ? 1 : 0.5

        Text {
          anchors.centerIn: parent
          text: modelData === 10 ? "0" : String(modelData)
          color: focused ? "#101014" : root.foreground
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: focused ? Font.Bold : Font.Normal
        }

        MouseArea {
          anchors.fill: parent
          // Bar.qml's root is `root`, not `service` like the service
          // components (Launcher, Lock, …) — the undefined reference made
          // every click throw before dispatching.
          onClicked: root.dispatchWorkspace(modelData)
        }
      }
    }

    Text {
      id: focusedWindow

      property var focused: Hyprland.focusedWorkspace !== null ? Hyprland.focusedWorkspace.focusedWindow : null

      visible: !!focused && !!focused.title
      text: focused && focused.title ? focused.title : ""
      color: root.foreground
      opacity: 0.9
      font.family: root.fontFamily
      font.pixelSize: 12

      anchors.verticalCenter: parent.verticalCenter
      leftPadding: 8
      // Elide long titles without pushing the other sections around.
      width: Math.min(implicitWidth, root.width * 0.3)
      elide: Text.ElideRight
    }
  }

  // Hyprland >= 0.55 with a Lua config evaluates request-socket payloads as
  // Lua: hl.dispatch takes a dispatcher OBJECT (hl.dsp.*), so the classic
  // "workspace 3" string form fails with a Lua syntax error — the clicks
  // were dead since the Lua migration.
  function dispatchWorkspace(id) {
    Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })")
  }

  // ----- Center: clock -----------------------------------------------------

  SystemClock {
    id: clock

    precision: SystemClock.Minutes
  }

  Text {
    anchors.centerIn: parent
    // Omarchy's default clock format.
    text: Qt.formatDateTime(clock.date, "dddd HH:mm")
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: 13
  }

  // ----- Right: system tray ------------------------------------------------

  Row {
    id: traySection

    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    Repeater {
      model: SystemTray.items

      delegate: Rectangle {
        required property var modelData

        width: 24
        height: 24
        radius: 4
        color: mouse.containsMouse ? "#33ffffff" : "transparent"

        IconImage {
          anchors.centerIn: parent
          implicitSize: 16
          source: modelData.icon
        }

        MouseArea {
          id: mouse

          anchors.fill: parent
          hoverEnabled: true
          onClicked: modelData.activate()
        }
      }
    }
  }
}
