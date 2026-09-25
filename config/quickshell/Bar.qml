// The bar: dark top bar with workspaces and the focused window title on
// the left, a centered clock (left click: calendar panel; right click:
// cycle the label format), and on the right the network status glyph
// (click: network panel) beside the system tray.
// Styling and layout follow Omarchy Quattro's bar.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import QtQuick
import "CalendarModel.js" as Model

PanelWindow {
  id: root

  // Wired to the shell's Calendar instance by shell.qml.
  property var calendar: null

  // Wired to the shell's NetworkPanel instance by shell.qml; the glyph
  // reads its NetworkManager state directly.
  property var networkPanel: null

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

    // A seconds label needs the clock to tick sixty times as often, and a
    // repaint a second is a price only the formats that print seconds pay.
    precision: Model.clockNeedsSeconds(root.clockFormat) ? SystemClock.Seconds : SystemClock.Minutes
  }

  // Omarchy's default clock format; right-click walks their format ring.
  // Session-only — there is no shell.json settings store here to persist a
  // cycled format into.
  property string clockFormat: "dddd HH:mm"

  function clockText() {
    // Qt has no ISO week specifier of its own; stand the number in before
    // formatting the 'W'ww preset.
    var format = root.clockFormat.replace(/ww/g, function() {
      return Model.isoWeekLiteral(clock.date.getFullYear(), clock.date.getMonth(), clock.date.getDate())
    })
    return Qt.formatDateTime(clock.date, format)
  }

  Rectangle {
    id: clockButton

    anchors.centerIn: parent
    width: clockLabel.implicitWidth + 18
    height: 22
    radius: 4
    color: clockMouse.containsMouse ? "#33ffffff" : "transparent"

    Text {
      id: clockLabel

      anchors.centerIn: parent
      text: root.clockText()
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: 13
    }

    MouseArea {
      id: clockMouse

      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton

      // Left click asks "what is the date?" and gets the calendar; right
      // click walks the label formats.
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton)
          root.clockFormat = Model.nextClockFormat(root.clockFormat)
        else if (root.calendar)
          root.calendar.toggle()
      }
    }
  }

  // ----- Right: network status + system tray ------------------------------

  Row {
    id: traySection

    anchors.right: parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 2

    // Omarchy's network bar widget, at granite's scale: the connection
    // glyph (wifi signal / ethernet / disconnected) straight off the
    // panel's Networking service state, opening the panel on click.
    Rectangle {
      width: 24
      height: 24
      radius: 4
      color: networkMouse.containsMouse ? "#33ffffff" : "transparent"
      opacity: root.networkPanel && root.networkPanel.networkManagerAvailable ? 1 : 0.5

      Text {
        anchors.centerIn: parent
        text: root.networkPanel ? root.networkPanel.icon : "󰤮"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: 14
      }

      MouseArea {
        id: networkMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.networkPanel) root.networkPanel.toggle()
      }
    }

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
