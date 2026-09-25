// M4: the session menu — the power menu half of Omarchy's system menu
// (their omarchy-menu system.* entries): lock, screensaver, suspend,
// logout, reboot, shutdown. SUPER+SHIFT+E (bound in hyprland.lua via `qs
// ipc call session toggle`) opens the same overlay geometry as the
// launcher: a centered card on the focused monitor, keyboard + mouse
// navigation, scrim closes.
//
// Omarchy behaviors kept here, simplified: suspend locks first (their
// lid-close recipe) so resume lands on the lock screen; logout is `uwsm
// stop` (their omarchy-system-logout closes windows first — apps get the
// session end either way); reboot/shutdown call systemctl directly (their
// systemd-run trick exists to survive the calling terminal dying; the
// detached launch below gives the same guarantee). What's deliberately
// NOT here: hibernate (the host has no swap-to-disk setup) and the
// wallpaper/OSD flourishes.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: service

  // Palette shared with Bar.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"

  // Wired to the shell's Lock instance by shell.qml.
  property var lock: null

  // ----- tuning ------------------------------------------------------------

  readonly property int cardWidth: 360
  readonly property int rowHeight: 46

  // Nerd Font glyphs, like Omarchy's omarchy-menu system icons.
  readonly property var actions: [
    { id: "lock", glyph: "󰌾", label: "Lock", detail: "Lock the session" },
    { id: "screensaver", glyph: "󱄄", label: "Screensaver", detail: "Start the wallpaper screensaver" },
    { id: "suspend", glyph: "󰒲", label: "Suspend", detail: "Lock, then suspend to memory" },
    { id: "logout", glyph: "󰍃", label: "Log out", detail: "End the Hyprland session" },
    { id: "reboot", glyph: "󰜉", label: "Reboot", detail: "Restart the system" },
    { id: "shutdown", glyph: "󰐥", label: "Shut down", detail: "Power off the system" }
  ]

  // ----- state -------------------------------------------------------------

  property bool opened: false
  property int selectedIndex: 0

  function open() {
    service.selectedIndex = 0
    service.opened = true
    return "opened"
  }

  function close() {
    service.opened = false
    return "closed"
  }

  function toggle() {
    return service.opened ? close() : open()
  }

  function moveSelection(delta) {
    var next = service.selectedIndex + delta
    service.selectedIndex = Math.max(0, Math.min(service.actions.length - 1, next))
  }

  // Detached so the action outlives the shell and its scopes (Omarchy's
  // systemd-run concern, minus the systemd-run).
  function runDetached(program) {
    Quickshell.execDetached(program)
  }

  function activate(index) {
    if (index < 0 || index >= service.actions.length) return
    var action = service.actions[index].id
    close()

    switch (action) {
      case "lock":
        if (service.lock) service.lock.beginLock()
        else runDetached(["qs", "ipc", "call", "lock", "lock"])
        break
      case "screensaver":
        // Omarchy's System > Screensaver entry, which forces it up even
        // with the idle one off; the shell's service does the same.
        runDetached(["qs", "ipc", "call", "screensaver", "start"])
        break
      case "suspend":
        // Lock first so resume lands on the lock screen; the delay lets the
        // lock surface come up before the machine sleeps.
        if (service.lock) service.lock.beginLock()
        runDetached(["bash", "-c", "sleep 1; systemctl suspend"])
        break
      case "logout":
        runDetached(["uwsm", "stop"])
        break
      case "reboot":
        runDetached(["systemctl", "reboot"])
        break
      case "shutdown":
        runDetached(["systemctl", "poweroff"])
        break
    }
  }

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call session toggle`.

  IpcHandler {
    target: "session"

    function toggle(): string {
      return service.toggle()
    }

    function open(): string {
      return service.open()
    }

    function close(): string {
      return service.close()
    }

    function ping(): string {
      return "ok"
    }
  }

  // ----- the overlay -------------------------------------------------------
  //
  // Same surface recipe as the launcher: full-screen transparent layer on
  // the focused Hyprland monitor, scrim closes, card holds the rows, and
  // the layer takes exclusive keyboard focus while visible.

  PanelWindow {
    id: panel

    visible: service.opened

    screen: {
      var monitor = Hyprland.focusedMonitor
      if (monitor) {
        var screens = Quickshell.screens
        for (var i = 0; i < screens.length; i++) {
          if (screens[i].name === monitor.name) return screens[i]
        }
      }
      return Quickshell.screens[0] || null
    }

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "mike-session"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // The card itself holds keyboard focus (there is no text field to
    // borrow it from, unlike the launcher).
    onVisibleChanged: if (visible) Qt.callLater(card.forceActiveFocus)

    Rectangle {
      anchors.fill: parent
      color: "#66000000"

      MouseArea {
        anchors.fill: parent
        onClicked: service.close()
      }
    }

    Rectangle {
      id: card

      width: service.cardWidth
      height: cardColumn.height + 24
      anchors.centerIn: parent
      radius: 8
      color: "#f0101014"
      border.width: 1
      border.color: "#26ffffff"

      // Swallow clicks inside the card so they don't reach the scrim.
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Keys.onPressed: function(event) {
        switch (event.key) {
          case Qt.Key_Escape:
            service.close()
            event.accepted = true
            break
          case Qt.Key_Return:
          case Qt.Key_Enter:
            service.activate(service.selectedIndex)
            event.accepted = true
            break
          case Qt.Key_Up:
            service.moveSelection(-1)
            event.accepted = true
            break
          case Qt.Key_Down:
            service.moveSelection(1)
            event.accepted = true
            break
          case Qt.Key_Home:
            service.selectedIndex = 0
            event.accepted = true
            break
          case Qt.Key_End:
            service.selectedIndex = service.actions.length - 1
            event.accepted = true
            break
        }
      }

      Column {
        id: cardColumn

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        spacing: 2

        Repeater {
          model: service.actions

          delegate: Rectangle {
            id: row

            required property int index
            required property var modelData

            width: cardColumn.width
            height: service.rowHeight
            radius: 6
            color: row.index === service.selectedIndex ? service.accent : rowHover.hovered ? "#1affffff" : "transparent"

            Row {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 10

              Text {
                width: 24
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: row.modelData.glyph
                color: row.index === service.selectedIndex ? "#101014" : service.foreground
                font.family: service.fontFamily
                font.pixelSize: 18
              }

              Column {
                width: parent.width - 24 - 10 - 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                  width: parent.width
                  text: row.modelData.label
                  color: row.index === service.selectedIndex ? "#101014" : service.foreground
                  font.family: service.fontFamily
                  font.pixelSize: 13
                  font.weight: row.index === service.selectedIndex ? Font.Bold : Font.Normal
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: row.modelData.detail
                  color: row.index === service.selectedIndex ? "#40101014" : service.foreground
                  opacity: 0.55
                  font.family: service.fontFamily
                  font.pixelSize: 11
                  elide: Text.ElideRight
                }
              }
            }

            HoverHandler {
              id: rowHover

              onHoveredChanged: if (hovered) service.selectedIndex = row.index
            }

            TapHandler {
              onTapped: service.activate(row.index)
            }
          }
        }
      }
    }
  }
}
