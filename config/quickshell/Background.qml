// M6: the desktop background. One Background-layer surface per screen
// renders the wallpaper in-process — no hyprpaper or swww, Omarchy
// Quattro's background plugin recipe — crossfading between changes.
//
// The current choice persists as a symlink at
// ~/.local/state/granite/background (Omarchy's readlink handshake: the
// lock screen's blur and any script can resolve it, and a wiped $HOME
// just re-seeds from the library). Backgrounds are discovered from
// ~/.local/share/granite/backgrounds — populated by home-manager from
// nixos-artwork, so a wiped $HOME grows its wallpaper back on the next
// switch — plus ~/.local/share/backgrounds for images of the user's own.
//
// The picker: SUPER+CTRL+SPACE (bound in hyprland.lua via `qs ipc call
// background toggle`, Omarchy Quattro's binding) or a double-click on
// the desktop opens a thumbnail grid on the focused monitor; return (or
// a click) switches, escape closes, and the image the desktop is wearing
// is marked. What's deliberately NOT here vs Omarchy: per-theme
// background sets and their slanted reveal wipe (granite has one
// palette; a plain crossfade), and their thumbnail disk cache (the
// library is small and the images load async as-is).
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: service

  // Palette shared with Bar.qml and the other overlays.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"

  // ----- tuning ------------------------------------------------------------

  readonly property int crossfadeMs: 400
  readonly property int cardWidth: 640
  readonly property int cardHeight: 460
  readonly property int cellWidth: 154
  readonly property int cellHeight: 118

  // The symlink other components resolve for the live wallpaper
  // (Omarchy's current/background handshake).
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/granite"
  readonly property string linkPath: stateDir + "/background"
  // home-manager's starter set plus the user's own images, both scanned
  // flat (case-insensitively) and merged.
  readonly property string libraryDir: Quickshell.env("HOME") + "/.local/share/granite/backgrounds"
  readonly property string userDir: Quickshell.env("HOME") + "/.local/share/backgrounds"

  // ----- state -------------------------------------------------------------

  property var backgrounds: [] // sorted absolute paths
  property string currentBackground: "" // what the symlink says
  property string displayedBackground: "" // what is on screen
  property string outgoingBackground: "" // fading under an incoming one
  property string incomingBackground: "" // fading in

  // Startup gate: the scan and the symlink read must both land before
  // the initial choice is made.
  property bool scanDone: false
  property bool linkChecked: false
  property string initialCandidate: ""

  property bool opened: false

  ListModel { id: pickerModel }

  // ----- library scan ------------------------------------------------------
  //
  // A flat glob per directory (nullglob so an empty or wiped $HOME scans
  // clean); the accumulation lands in one sorted array. Re-scanned on
  // every picker open, so dropping an image into a directory and
  // re-opening is enough.

  property var scanAccumulator: []

  function scan() {
    if (scanProc.running) {
      scanRetryTimer.restart()
      return
    }
    scanProc.running = true
  }

  Timer {
    id: scanRetryTimer

    interval: 200
    onTriggered: service.scan()
  }

  Process {
    id: scanProc

    running: false
    command: ["bash", "-c",
      "shopt -s nullglob nocaseglob\n" +
      "for dir in \"$1\" \"$2\"; do\n" +
      "  for img in \"$dir\"/*.jpg \"$dir\"/*.jpeg \"$dir\"/*.png \"$dir\"/*.gif \"$dir\"/*.bmp \"$dir\"/*.webp; do\n" +
      "    printf '%s\\n' \"$img\"\n" +
      "  done\n" +
      "done\n" +
      "exit 0", "--",
      service.libraryDir,
      service.userDir]
    stdout: SplitParser {
      onRead: function(data) { service.scanAccumulator.push(String(data)) }
    }
    onExited: {
      service.backgrounds = service.scanAccumulator.slice().sort()
      service.scanAccumulator = []
      service.scanDone = true
      service.maybeApplyInitial()
      if (service.opened) service.rebuildPicker()
    }
  }

  // ----- startup -----------------------------------------------------------
  //
  // Make the directories exist (FileView is not involved here, but the
  // symlink's parent needs creating before the first ln), then resolve
  // the current choice and fall back to the first library image when the
  // symlink is gone — the wiped-$HOME story every milestone shares.

  Process {
    id: ensureDirs

    running: false
    command: ["mkdir", "-p", service.stateDir, service.libraryDir, service.userDir]
  }

  Process {
    id: linkProc

    running: false
    // -e resolves only existing files, so a stale symlink reads as empty
    // instead of a path the Image would fail on.
    command: ["bash", "-c", "readlink -e -- \"$1\" || exit 0", "--", service.linkPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        service.linkChecked = true
        service.initialCandidate = String(text || "").trim()
        service.maybeApplyInitial()
      }
    }
  }

  Component.onCompleted: {
    ensureDirs.running = true
    scan()
    linkProc.running = true
  }

  function maybeApplyInitial() {
    if (!scanDone || !linkChecked) return

    var start = initialCandidate
    if (start.length === 0 && backgrounds.length > 0) start = backgrounds[0]
    // Restoring an intact symlink needs no write; seeding the fallback
    // persists it so the choice survives shell restarts too.
    if (start.length > 0) setBackground(start, true, start === initialCandidate)
  }

  // ----- setting -----------------------------------------------------------

  function setBackground(path, instant, skipPersist) {
    path = String(path || '').trim()
    if (path.length === 0 || path === currentBackground) return
    currentBackground = path
    if (!skipPersist) persistLink(path)

    if (instant || displayedBackground.length === 0) {
      // A fade mid-flight fizzles on its own here: the incoming frame's
      // source empties with the state, and its onFinished guard refuses
      // to settle. (fadeIn itself lives in the per-screen delegate below
      // — out of this scope, like every id inside Variants.)
      outgoingBackground = ""
      incomingBackground = ""
      displayedBackground = path
      return
    }

    // The old image stays on screen (displayed) while the new one fades
    // in over it; see the frames below for the settle handshake.
    outgoingBackground = displayedBackground
    incomingBackground = path
  }

  // Omarchy's omarchy-theme-bg-set: repoint the symlink and let anything
  // resolving it follow. readlink -e validates the target first, so a bad
  // `qs ipc call background set` path never poisons the state.
  function persistLink(path) {
    if (persistProc.running) {
      Qt.callLater(function() { service.persistLink(path) })
      return
    }
    persistProc.command = ["bash", "-c",
      "p=$(readlink -e -- \"$1\") || exit 0\n" +
      "[ -n \"$p\" ] || exit 0\n" +
      "mkdir -p -- \"$(dirname -- \"$2\")\"\n" +
      "ln -nsf -- \"$p\" \"$2\"", "--",
      path, linkPath]
    persistProc.running = true
  }

  Process {
    id: persistProc

    running: false
  }

  function cancelTransition() {
    incomingBackground = ""
    outgoingBackground = ""
  }

  function nextBackground() {
    if (backgrounds.length === 0) return "none"
    var index = backgrounds.indexOf(currentBackground)
    var next = backgrounds[(index + 1) % backgrounds.length]
    setBackground(next, false, false)
    return next
  }

  function imageUrl(path) {
    return path.length > 0 ? "file://" + path : ""
  }

  // Omarchy's pretty names (their omarchy-theme-bg-current): strip the
  // extension, a leading sort index, and the nix wallpaper prefixes, then
  // title-case what's left.
  function prettyName(path) {
    var name = String(path).split("/").pop() || String(path)
    name = name.replace(/\.[^.]+$/, "")
    name = name.replace(/^(nix-?os-)?wallpaper-/, "")
    name = name.replace(/^\d+-/, "")
    name = name.replace(/[-_]+/g, " ")
    return name.replace(/\b\w/g, function(c) { return c.toUpperCase() })
  }

  // ----- open / close ------------------------------------------------------

  function openPicker() {
    service.opened = true
    scan()
    rebuildPicker()
    return "opened"
  }

  function closePicker() {
    service.opened = false
    return "closed"
  }

  function togglePicker() {
    return service.opened ? closePicker() : openPicker()
  }

  function rebuildPicker() {
    pickerModel.clear()
    for (var i = 0; i < backgrounds.length; i++)
      pickerModel.append({ path: backgrounds[i], name: prettyName(backgrounds[i]) })

    var current = backgrounds.indexOf(currentBackground)
    grid.currentIndex = current >= 0 ? current : (pickerModel.count > 0 ? 0 : -1)
  }

  function pick(path) {
    closePicker()
    setBackground(path, false, false)
  }

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call background toggle` /
  // `qs ipc call background set <path>` (Omarchy's omarchy-theme-bg-set).

  IpcHandler {
    target: "background"

    function toggle(): string {
      return service.togglePicker()
    }

    function open(): string {
      return service.openPicker()
    }

    function close(): string {
      return service.closePicker()
    }

    function set(path: string): string {
      var trimmed = String(path || "").trim()
      if (trimmed.length === 0) return "ignored"
      service.setBackground(trimmed, false, false)
      return "ok"
    }

    function next(): string {
      return service.nextBackground()
    }

    function current(): string {
      return service.currentBackground
    }

    function ping(): string {
      return "ok"
    }
  }

  // ----- the wallpaper surfaces --------------------------------------------
  //
  // One Background-layer surface per screen, all showing the same image
  // (the symlink is one choice, like Omarchy's). Three frames keep the
  // crossfade seamless: the settled frame holds the displayed image, the
  // outgoing frame covers its async reload after a settle, and the
  // incoming frame fades in on top once its pixels are ready.

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: backgroundPanel

      required property var modelData

      screen: modelData
      visible: true

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      // granite's base — also the whole show when the library is empty.
      color: "#101014"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "mike-background"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      Image {
        id: settledFrame

        anchors.fill: parent
        source: service.imageUrl(service.displayedBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        onStatusChanged: {
          if (status !== Image.Ready) return
          if (service.incomingBackground !== "" && !fadeIn.running) {
            // The fade settled the state; both cover layers drop now that
            // the settled frame really holds the new image.
            service.incomingBackground = ""
            service.outgoingBackground = ""
          } else if (service.incomingBackground === "" && service.outgoingBackground !== "") {
            service.outgoingBackground = ""
          }
        }
      }

      Image {
        id: outgoingFrame

        anchors.fill: parent
        visible: service.outgoingBackground.length > 0
        source: service.imageUrl(service.outgoingBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
      }

      Image {
        id: incomingFrame

        anchors.fill: parent
        opacity: 0
        source: service.imageUrl(service.incomingBackground)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        smooth: true
        onStatusChanged: {
          // Wait for the pixels before fading; a broken path cancels the
          // switch and leaves the old image standing.
          if (status === Image.Ready && service.incomingBackground !== "")
            fadeIn.restart()
          else if (status === Image.Error)
            service.cancelTransition()
        }
      }

      NumberAnimation {
        id: fadeIn

        target: incomingFrame
        property: "opacity"
        from: 0
        to: 1
        duration: service.crossfadeMs
        easing.type: Easing.InOutQuad
        // Only a natural finish settles; the faded-in frame stays up as a
        // cover until the settled frame reports the new image Ready (its
        // onStatusChanged clears the layers), so the async reload never
        // lets the old image peek back through.
        onFinished: {
          if (service.incomingBackground !== "" && incomingFrame.status === Image.Ready)
            service.displayedBackground = service.incomingBackground
        }
      }

      // Omarchy's desktop double-click: the background opens its picker.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onDoubleClicked: service.openPicker()
      }
    }
  }

  // ----- the picker overlay ------------------------------------------------
  //
  // Same surface recipe as the clipboard picker: full-screen transparent
  // layer on the focused Hyprland monitor, scrim closes, card holds a
  // thumbnail grid, and the layer takes exclusive keyboard focus while
  // visible. The grid's own key navigation moves the selection; return
  // commits and escape closes.

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
    WlrLayershell.namespace: "mike-background-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    onVisibleChanged: if (visible) grid.forceActiveFocus()

    Rectangle {
      anchors.fill: parent
      color: "#66000000"

      MouseArea {
        anchors.fill: parent
        onClicked: service.closePicker()
      }
    }

    Rectangle {
      id: card

      width: service.cardWidth
      height: service.cardHeight
      anchors.centerIn: parent
      radius: 8
      color: "#f0101014"
      border.width: 1
      border.color: "#26ffffff"

      // Swallow clicks inside the card so they don't reach the scrim and
      // close the picker.
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Column {
        id: cardColumn

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        spacing: 10

        // ----- header ------------------------------------------------------

        Item {
          width: parent.width
          height: 24

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Backgrounds"
            color: service.foreground
            font.family: service.fontFamily
            font.pixelSize: 14
            font.weight: Font.Bold
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: service.backgrounds.length + " image" + (service.backgrounds.length === 1 ? "" : "s")
            color: service.foreground
            opacity: 0.55
            font.family: service.fontFamily
            font.pixelSize: 11
          }
        }

        // ----- the grid ----------------------------------------------------

        Item {
          width: parent.width
          height: parent.height - 24 - 10 - 20 - 10
          clip: true

          GridView {
            id: grid

            anchors.fill: parent
            model: pickerModel
            clip: true
            cellWidth: service.cellWidth
            cellHeight: service.cellHeight
            boundsBehavior: Flickable.StopAtBounds

            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain)

            Keys.onPressed: function(event) {
              switch (event.key) {
                case Qt.Key_Escape:
                  service.closePicker()
                  event.accepted = true
                  break
                case Qt.Key_Return:
                case Qt.Key_Enter:
                  if (grid.currentIndex >= 0 && grid.currentIndex < pickerModel.count)
                    service.pick(pickerModel.get(grid.currentIndex).path)
                  event.accepted = true
                  break
                case Qt.Key_Home:
                  if (pickerModel.count > 0) grid.currentIndex = 0
                  event.accepted = true
                  break
                case Qt.Key_End:
                  if (pickerModel.count > 0) grid.currentIndex = pickerModel.count - 1
                  event.accepted = true
                  break
              }
            }

            delegate: Item {
              id: cell

              required property int index
              required property string path
              required property string name

              width: grid.cellWidth
              height: grid.cellHeight

              Rectangle {
                id: thumb

                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: grid.cellWidth - 12
                height: 82
                radius: 6
                clip: true
                color: "#22000000"
                border.width: cell.index === grid.currentIndex ? 2 : 1
                border.color: cell.index === grid.currentIndex ? service.accent : "#26ffffff"

                Image {
                  anchors.fill: parent
                  anchors.margins: 1
                  source: "file://" + cell.path
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  smooth: true
                }

                // Marks the image the desktop is actually wearing.
                Rectangle {
                  visible: cell.path === service.currentBackground
                  width: 10
                  height: 10
                  radius: 5
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.margins: 6
                  color: service.accent
                }
              }

              Text {
                anchors.top: thumb.bottom
                anchors.topMargin: 4
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: cell.name
                color: cell.index === grid.currentIndex ? service.accent : service.foreground
                opacity: cell.index === grid.currentIndex ? 1 : 0.8
                font.family: service.fontFamily
                font.pixelSize: 11
                elide: Text.ElideMiddle
              }

              HoverHandler {
                id: cellHover

                onHoveredChanged: if (hovered) grid.currentIndex = cell.index
              }

              TapHandler {
                onTapped: service.pick(cell.path)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: pickerModel.count === 0
            text: "No backgrounds found — drop images into " + service.userDir
            color: service.foreground
            opacity: 0.5
            font.family: service.fontFamily
            font.pixelSize: 13
          }
        }

        // ----- footer ------------------------------------------------------

        Item {
          width: parent.width
          height: 20

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "return switch · esc close · double-click the desktop to reopen"
            color: service.foreground
            opacity: 0.55
            font.family: service.fontFamily
            font.pixelSize: 11
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: service.currentBackground.length > 0
            text: "current: " + prettyName(service.currentBackground)
            color: service.foreground
            opacity: 0.55
            font.family: service.fontFamily
            font.pixelSize: 11
          }
        }
      }
    }
  }
}
