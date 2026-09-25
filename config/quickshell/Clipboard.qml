// M5: the clipboard history. Two wl-paste watchers (text and image/png)
// feed granite-clipboard-capture's JSON entries into a history under
// ~/.local/state/granite (clipboard-history.json plus content-addressed
// image files), and SUPER+CTRL+V (bound in hyprland.lua via `qs ipc call
// clipboard toggle`) opens the picker: a centered card on the focused
// monitor, like the launcher, with the entry list on the left and the
// selected entry on the right — type to search, return copies back out
// through wl-copy, del removes, shift+del clears (with a confirm step).
//
// Ported from Omarchy Quattro's Clipboard.qml
// (https://github.com/basecamp/omarchy, MIT), kept: sensitive-clipboard
// skipping (password-manager concealment), whitespace-only drops,
// front-most dedup, file:// URI recognition, bounded display text, the
// copy-by-history-index round trip (the picker renders a prefix; wl-copy
// gets the exact stored bytes), and watcher restarts. Deliberately NOT
// here vs Omarchy: their unified copy/paste hotkeys (Super+C/V/X via
// synthetic key sends) — the history picker only puts the entry back on
// the clipboard, pasting stays the apps' own business — and opening
// entries in an editor/browser.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

import "ClipboardHistory.js" as ClipboardHistory

Item {
  id: service

  // Palette shared with Bar.qml and Launcher.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"
  readonly property color critical: "#ff5555"

  // ----- tuning ------------------------------------------------------------

  readonly property int cardWidth: 640
  readonly property int cardHeight: 460
  readonly property int rowHeight: 40
  readonly property int historyLimit: 500
  readonly property int displayLimit: 50

  // Same state layout as the other milestones: a wiped $HOME simply
  // starts the history over.
  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/granite/clipboard-history.json"
  readonly property string imagesDir: Quickshell.env("HOME") + "/.local/state/granite/clipboard-images/"

  // ----- state -------------------------------------------------------------

  property bool opened: false
  property string query: ""
  property int selectedIndex: 0
  property var history: []

  // While true, every key but return/escape is swallowed — shift+del
  // asks before wiping the whole history.
  property bool clearConfirmOpen: false

  ListModel { id: displayModel }

  // ----- persistence -------------------------------------------------------
  //
  // Same pattern as the launcher's usage counts and the notifications
  // DND flag: a JSON file under ~/.local/state/granite, written with a
  // debounced save, loaded once (FileView can fire onLoaded more than
  // once during startup; the first read is authoritative).

  FileView {
    id: historyFile

    path: service.historyPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadHistory(text())
    // First run: the file doesn't exist yet — an empty history, and the
    // first capture writes it. This also completes the startup gate the
    // capture pipeline waits on.
    onLoadFailed: service.loadHistory("[]")
  }

  property bool historyLoaded: false

  Timer {
    id: saveTimer

    interval: 200
    onTriggered: historyFile.setText(JSON.stringify(service.history.slice(0, service.historyLimit)) + "\n")
  }

  function loadHistory(raw) {
    if (service.historyLoaded) return
    service.historyLoaded = true
    service.history = ClipboardHistory.parseHistory(raw)
    // Writes are guarded so a load-time hydration can never clobber the
    // file with the default before it was read.
    service.startCapture()
  }

  function saveHistory() {
    if (service.historyLoaded) saveTimer.restart()
  }

  // ----- capture -----------------------------------------------------------
  //
  // wl-paste --watch fires the capture script on every clipboard change
  // (ours included — a selection from the picker re-copies through
  // wl-copy, and the watcher is what moves it back to the front). A
  // shell restart misses nothing it cares about: the watchers left
  // behind by a dead instance die on their next write (SIGPIPE), the
  // pkill is belt and braces, and the snapshot re-records whatever is on
  // the clipboard right now.

  function captureJson(line) {
    var entry = ClipboardHistory.parseEntryJson(line)
    if (!entry) return
    service.history = ClipboardHistory.addEntry(service.history, entry, service.historyLimit)
    saveHistory()
    if (service.opened) rebuildDisplay()
  }

  function startCapture() {
    // Reap watchers left behind by a previous shell instance, then start
    // our own plus a snapshot of the current clipboard.
    reapProc.running = true
  }

  Process {
    id: reapProc

    running: false
    // The exit-0 keeps the fallback harmless where pkill is missing;
    // either way onExited starts the real watchers. The [g] keeps the
    // pattern from matching this wrapper's own command line.
    command: ["bash", "-c", "pkill -f 'wl-paste .*--watch .*[g]ranite-clipboard-capture' 2>/dev/null; exit 0"]
    onExited: {
      textWatchProc.running = true
      imageWatchProc.running = true
      snapshotProc.running = true
      // Copies a killed queue left behind can't be named by anything
      // else — sweep now that the history is loaded.
      Qt.callLater(service.sweepImages)
    }
  }

  Process {
    id: snapshotProc

    running: false
    command: ["granite-clipboard-capture"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) service.captureJson(lines[i])
      }
    }
  }

  Process {
    id: textWatchProc

    running: false
    command: ["wl-paste", "--type", "text", "--watch", "granite-clipboard-capture", "text"]
    stdout: SplitParser {
      onRead: function(data) { service.captureJson(data) }
    }
    onExited: watchRestartTimer.restart()
  }

  Process {
    id: imageWatchProc

    running: false
    command: ["wl-paste", "--type", "image/png", "--watch", "granite-clipboard-capture", "image/png"]
    stdout: SplitParser {
      onRead: function(data) { service.captureJson(data) }
    }
    onExited: watchRestartTimer.restart()
  }

  // A watcher that dies takes clipboard history with it, silently:
  // copying still works, the picker still opens, and the old entries are
  // all still there, so nothing recorded until the next shell reload.
  // Bring it back instead.
  Timer {
    id: watchRestartTimer

    interval: 1000
    onTriggered: {
      if (!textWatchProc.running) textWatchProc.running = true
      if (!imageWatchProc.running) imageWatchProc.running = true
    }
  }

  // ----- image hygiene -----------------------------------------------------
  //
  // Image files are content-addressed and only history entries reference
  // them, so entries falling off the tail (or removals/clears) orphan
  // files. Swept after startup and after any removal, through one
  // process with the launcher's retry-on-running pattern.

  Timer {
    id: sweepTimer

    interval: 500
    onTriggered: {
      if (sweepProc.running) {
        sweepTimer.restart()
        return
      }
      sweepProc.running = true
    }
  }

  function sweepImages() {
    sweepTimer.restart()
  }

  Process {
    id: sweepProc

    running: false
    command: ["bash", "-c",
      "tmp=$(mktemp) || exit 0\n" +
      "jq -r '.[].path // empty' \"$1\" >\"$tmp\" 2>/dev/null || { rm -f -- \"$tmp\"; exit 0; }\n" +
      "shopt -s nullglob\n" +
      // \"${2%/}\" drops the trailing slash QML's imagesDir carries, so the
      // globbed paths match the stored ones byte for byte.
      "for img in \"${2%/}\"/*; do\n" +
      "  case $img in *.tmp) rm -f -- \"$img\"; continue ;; esac\n" +
      "  grep -qxF -- \"$img\" \"$tmp\" || rm -f -- \"$img\"\n" +
      "done\n" +
      "rm -f -- \"$tmp\"", "--",
      service.historyPath,
      service.imagesDir]
  }

  // ----- open / close ------------------------------------------------------

  function open() {
    service.clearConfirmOpen = false
    service.opened = true
    // setQuery owns the filter, the selection and the rebuild — and syncs
    // the field, which keeps whatever was typed last time it was open.
    setQuery("")
    return "opened"
  }

  function close() {
    service.clearConfirmOpen = false
    service.opened = false
    return "closed"
  }

  function toggle() {
    return service.opened ? close() : open()
  }

  function setQuery(value) {
    // The TextInput is the source of truth while open; setting .text runs
    // its onTextChanged, which updates the query and rebuilds — so a fresh
    // rebuild here would be redundant double work.
    if (searchInput.text !== value) searchInput.text = value
    else {
      service.query = value
      service.selectedIndex = 0
      rebuildDisplay()
    }
  }

  // ----- the picker's rows --------------------------------------------------

  function rebuildDisplay() {
    var rows = ClipboardHistory.displayRows(service.history, service.query, service.displayLimit)

    displayModel.clear()
    for (var i = 0; i < rows.length; i++) displayModel.append(rows[i])

    if (displayModel.count === 0) service.selectedIndex = 0
    else if (service.selectedIndex >= displayModel.count) service.selectedIndex = displayModel.count - 1
    else if (service.selectedIndex < 0) service.selectedIndex = 0
  }

  function moveSelection(delta) {
    if (displayModel.count === 0) return
    var next = service.selectedIndex + delta
    service.selectedIndex = Math.max(0, Math.min(displayModel.count - 1, next))
  }

  onSelectedIndexChanged: Qt.callLater(function() {
    if (service.selectedIndex >= 0 && service.selectedIndex < displayModel.count)
      resultList.positionViewAtIndex(service.selectedIndex, ListView.Contain)
  })

  // ----- acting on entries --------------------------------------------------

  // Copy the full entry back onto the clipboard. Text round-trips
  // through the history file by index (jq | wl-copy) so the exact stored
  // bytes move, never the capped copy the picker renders; images stream
  // from their content-addressed file. systemd-run scopes the wl-copy
  // daemon out of the shell's cgroup, so the clipboard survives a shell
  // restart instead of dying with the service.
  function copyAt(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)
    close()
    if (row.entryType === "image") {
      copyProc.command = ["systemd-run", "--user", "--scope", "--collect",
        "bash", "-c", "exec wl-copy --type \"$1\" < \"$2\"", "--",
        row.mime, row.previewImage]
    } else {
      copyProc.command = ["systemd-run", "--user", "--scope", "--collect",
        "bash", "-c",
        "jq -j --argjson index \"$1\" '.[$index] | if .type == \"text\" and (.text | type == \"string\") then .text else empty end' \"$2\" | wl-copy",
        "--",
        String(row.historyIndex),
        service.historyPath]
    }
    runCopyProc()
  }

  // A Process ignores a command change while it is running — if one is
  // still in flight, land the next on the following event-loop turn
  // instead of dropping it.
  function runCopyProc() {
    if (copyProc.running) {
      Qt.callLater(service.runCopyProc)
      return
    }
    copyProc.running = true
  }

  Process {
    id: copyProc
  }

  function removeAt(index) {
    if (index < 0 || index >= displayModel.count) return
    var row = displayModel.get(index)

    service.history = ClipboardHistory.removeEntryAt(service.history, row.historyIndex)
    saveHistory()

    if (displayModel.count <= 1) service.selectedIndex = 0
    else if (service.selectedIndex >= displayModel.count - 1) service.selectedIndex = displayModel.count - 2
    rebuildDisplay()
    sweepImages()
  }

  function requestClear() {
    if (service.history.length === 0) return
    service.clearConfirmOpen = true
  }

  function cancelClear() {
    service.clearConfirmOpen = false
  }

  function confirmClear() {
    service.clearConfirmOpen = false
    service.history = ClipboardHistory.clearHistory()
    saveHistory()
    service.selectedIndex = 0
    rebuildDisplay()
    sweepImages()
  }

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call clipboard toggle`.

  IpcHandler {
    target: "clipboard"

    function toggle(): string {
      return service.toggle()
    }

    function open(): string {
      return service.open()
    }

    function close(): string {
      return service.close()
    }

    function clearHistory(): string {
      service.confirmClear()
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }

  // Make sure the state directory exists before the first save. FileView
  // does not create parent directories.
  Process {
    id: ensureStateDir

    command: ["mkdir", "-p", service.imagesDir]
  }

  Component.onCompleted: ensureStateDir.running = true

  // ----- the overlay -------------------------------------------------------
  //
  // Same surface recipe as the launcher: full-screen transparent layer on
  // the focused Hyprland monitor, scrim closes, card holds the field, the
  // rows and the preview, and the layer takes exclusive keyboard focus
  // while visible.

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
    WlrLayershell.namespace: "mike-clipboard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // The layer is created hidden; focus the field each time it surfaces.
    onVisibleChanged: if (visible) searchInput.forceActiveFocus()

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

        // ----- search field ------------------------------------------------

        Rectangle {
          width: parent.width
          height: 40
          radius: 6
          color: "#22000000"
          border.width: 1
          border.color: searchInput.activeFocus ? service.accent : "#26ffffff"

          TextInput {
            id: searchInput

            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            color: service.foreground
            selectionColor: service.accent
            selectedTextColor: "#101014"
            font.family: service.fontFamily
            font.pixelSize: 14

            onTextChanged: {
              service.query = text
              service.selectedIndex = 0
              service.rebuildDisplay()
            }

            // Navigation keys are consumed before the TextInput's own
            // handling — cursor movement inside a one-line filter field
            // matters less than moving through the entries.
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              // The clear confirm owns the keyboard while open: return
              // commits, escape backs out, everything else waits.
              if (service.clearConfirmOpen) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                  service.confirmClear()
                else if (event.key === Qt.Key_Escape)
                  service.cancelClear()
                event.accepted = true
                return
              }

              switch (event.key) {
                case Qt.Key_Escape:
                  // The launcher's ladder: the first Escape clears the
                  // filter, the second closes.
                  if (service.query.length > 0) service.setQuery("")
                  else service.close()
                  event.accepted = true
                  break
                case Qt.Key_Return:
                case Qt.Key_Enter:
                  service.copyAt(service.selectedIndex)
                  event.accepted = true
                  break
                case Qt.Key_Delete:
                  if (event.modifiers & Qt.ShiftModifier) service.requestClear()
                  else service.removeAt(service.selectedIndex)
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
                case Qt.Key_PageUp:
                  service.moveSelection(-8)
                  event.accepted = true
                  break
                case Qt.Key_PageDown:
                  service.moveSelection(8)
                  event.accepted = true
                  break
                case Qt.Key_Home:
                  service.selectedIndex = displayModel.count > 0 ? 0 : -1
                  event.accepted = true
                  break
                case Qt.Key_End:
                  service.selectedIndex = displayModel.count - 1
                  event.accepted = true
                  break
              }
            }

            Text {
              anchors.fill: parent
              anchors.leftMargin: 1
              verticalAlignment: Text.AlignVCenter
              visible: searchInput.text.length === 0
              text: "Search clipboard…"
              color: service.foreground
              opacity: 0.5
              font.family: service.fontFamily
              font.pixelSize: 14
            }
          }
        }

        // ----- entries + preview --------------------------------------------

        Item {
          width: parent.width
          height: parent.height - 40 - 10 - 24 - 10

          Row {
            anchors.fill: parent
            spacing: 0

            // The list: one line per entry, thumbnails for image-ish
            // payloads, elided previews for text.
            Item {
              width: parent.width * 0.55
              height: parent.height
              clip: true

              ListView {
                id: resultList

                anchors.fill: parent
                model: displayModel
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: service.selectedIndex

                delegate: Rectangle {
                  id: row

                  required property int index
                  required property string entryType
                  required property string previewText
                  required property string previewImage
                  required property int historyIndex

                  width: resultList.width
                  height: service.rowHeight
                  radius: 6
                  color: row.index === service.selectedIndex ? service.accent : rowHover.hovered ? "#1affffff" : "transparent"

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10

                    Image {
                      visible: row.previewImage.length > 0
                      width: visible ? 28 : 0
                      height: 28
                      anchors.verticalCenter: parent.verticalCenter
                      source: row.previewImage.length > 0 ? "file://" + row.previewImage : ""
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width - (row.previewImage.length > 0 ? 38 : 0)
                      height: parent.height
                      text: row.previewText
                      color: row.index === service.selectedIndex ? "#101014" : service.foreground
                      opacity: row.entryType === "image" || row.entryType === "file" ? 0.72 : 1.0
                      font.family: service.fontFamily
                      font.pixelSize: 13
                      elide: Text.ElideRight
                      wrapMode: Text.NoWrap
                      verticalAlignment: Text.AlignVCenter
                    }
                  }

                  HoverHandler {
                    id: rowHover

                    onHoveredChanged: if (hovered) service.selectedIndex = row.index
                  }

                  TapHandler {
                    onTapped: service.copyAt(row.index)
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: displayModel.count === 0
                text: service.history.length === 0
                  ? "Clipboard is empty"
                  : "No matches for “" + service.query + "”"
                color: service.foreground
                opacity: 0.5
                font.family: service.fontFamily
                font.pixelSize: 13
              }
            }

            Rectangle {
              width: 1
              height: parent.height
              color: "#26ffffff"
            }

            // The preview pane: the selected entry in full (text wrapped,
            // image fitted), exactly what return would put back on the
            // clipboard — modulo the display cap the JS helper applies.
            Item {
              width: parent.width * 0.45 - 1
              height: parent.height
              clip: true

              property var activeRow: displayModel.count > 0 && service.selectedIndex >= 0 && service.selectedIndex < displayModel.count
                ? displayModel.get(service.selectedIndex)
                : null

              Text {
                textFormat: Text.PlainText
                visible: !parent.activeRow || parent.activeRow.previewImage.length === 0
                anchors.fill: parent
                anchors.leftMargin: 12
                text: parent.activeRow ? parent.activeRow.fullText : ""
                color: service.foreground
                font.family: service.fontFamily
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
              }

              Image {
                visible: parent.activeRow && parent.activeRow.previewImage.length > 0
                anchors.fill: parent
                anchors.leftMargin: 12
                source: parent.activeRow && parent.activeRow.previewImage.length > 0 ? "file://" + parent.activeRow.previewImage : ""
                fillMode: Image.PreserveAspectFit
                verticalAlignment: Image.AlignTop
                asynchronous: true
                smooth: true
              }
            }
          }
        }

        // ----- footer -------------------------------------------------------

        Item {
          width: parent.width
          height: 24

          Text {
            visible: !service.clearConfirmOpen
            anchors.verticalCenter: parent.verticalCenter
            text: "return copy · del remove · shift+del clear all"
            color: service.foreground
            opacity: 0.55
            font.family: service.fontFamily
            font.pixelSize: 11
          }

          Text {
            visible: service.clearConfirmOpen
            anchors.verticalCenter: parent.verticalCenter
            text: "Delete entire clipboard history? return to confirm · esc to cancel"
            color: service.critical
            font.family: service.fontFamily
            font.pixelSize: 11
          }
        }
      }
    }
  }
}
