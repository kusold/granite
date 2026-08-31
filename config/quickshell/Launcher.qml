// M3: the launcher / menu. One overlay per session: SUPER+SPACE (bound in
// hyprland.lua via `qs ipc call launcher toggle`) summons a centered card
// on the focused monitor with a fuzzy search over desktop entries; Enter
// launches through `uwsm-app -- gtk-launch`, like Omarchy Quattro's
// launcher (https://github.com/basecamp/omarchy, MIT).
//
// Omarchy behaviors kept here, simplified: multi-term + acronym fuzzy
// matching, Escape clears the filter before closing, Tab completes the
// query to the selection, and launch frequency ranks the list (persisted
// under ~/.local/state/granite, like the notifications settings) so the
// empty query opens onto the most-used apps. What's deliberately NOT here
// yet: per-entry desktop actions, a dmenu mode for scripts, and the
// drilldown command/power menus (the system menu grows in M4 alongside
// lock + idle).
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import "LauncherSearch.js" as LauncherSearch

Item {
  id: service

  // Palette shared with Bar.qml and Notifications.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"

  // ----- tuning ------------------------------------------------------------

  readonly property int cardWidth: 480
  readonly property int rowHeight: 44
  readonly property int maxVisibleRows: 8

  // ----- state -------------------------------------------------------------

  property bool opened: false
  property string query: ""
  property int selectedIndex: 0

  ListModel { id: results }

  // ----- launch frequency --------------------------------------------------
  //
  // Same persistence pattern as Notifications.qml's DND flag: a JSON file
  // under ~/.local/state/granite (which a wiped $HOME simply loses — the
  // launcher degrades to alphabetical order until apps are used again).

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/granite/launcher.json"

  property var usageCounts: ({})
  property bool stateLoaded: false

  FileView {
    id: usageFile

    path: service.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadUsage(text())
    // First run: the file doesn't exist yet — defaults, and the first
    // launch writes it.
    onLoadFailed: service.loadUsage("")
  }

  Timer {
    id: usageSaveTimer

    interval: 500
    onTriggered: usageFile.setText(JSON.stringify({ counts: service.usageCounts }) + "\n")
  }

  function loadUsage(raw) {
    // FileView can fire onLoaded more than once during startup; the first
    // read is authoritative.
    if (service.stateLoaded) return
    service.stateLoaded = true

    var counts = ({})
    var text = String(raw || "").trim()
    if (text) {
      try {
        var parsed = JSON.parse(text)
        if (parsed && parsed.counts && typeof parsed.counts === "object") counts = parsed.counts
      } catch (e) {
        console.warn("launcher: usage file parse failed:", e)
      }
    }
    service.usageCounts = counts
    if (service.opened) rebuildResults()
  }

  function rememberUse(entryId) {
    var counts = ({})
    for (var key in service.usageCounts) counts[key] = service.usageCounts[key]
    counts[entryId] = (Number(counts[entryId]) || 0) + 1
    service.usageCounts = counts
    // Guarded so a load-time hydration can never clobber the file with
    // the default before it was read.
    if (service.stateLoaded) usageSaveTimer.restart()
  }

  // ----- results -----------------------------------------------------------

  function rebuildResults() {
    var rows = LauncherSearch.sortedEntries(DesktopEntries.applications.values, service.query, service.usageCounts)
    results.clear()
    for (var i = 0; i < rows.length; i++) results.append(rows[i])
    service.selectedIndex = results.count > 0 ? 0 : -1
  }

  // Newly installed apps appear without a restart; only churn the model
  // while the launcher is actually on screen.
  Connections {
    target: DesktopEntries.applications

    function onValuesChanged() {
      if (service.opened) service.rebuildResults()
    }
  }

  // ----- open / close ------------------------------------------------------

  function open() {
    service.opened = true
    setQuery("")
    return "opened"
  }

  function close() {
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
      rebuildResults()
    }
  }

  // ----- launching ---------------------------------------------------------

  // iconPath(name, true) yields "" for unknown icon names, so the row
  // glyph fallback shows instead of Qt's broken-image placeholder.
  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0 || value.indexOf("/") === 0)
      return value
    return Quickshell.iconPath(value, true)
  }

  // Launch through uwsm-app -- gtk-launch, Omarchy's recipe: the app lands
  // in its own systemd scope, and gtk-launch resolves the desktop entry
  // properly (ids with spaces, Terminal=true entries) where a naive
  // exec-string parse would fail. The .desktop suffix is required or ids
  // like org.gnome.Nautilus don't resolve.
  function launchAt(index) {
    if (index < 0 || index >= results.count) return
    var row = results.get(index)
    rememberUse(row.entryId)
    Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", row.entryId + ".desktop"])
    close()
  }

  function moveSelection(delta) {
    if (results.count === 0) return
    var next = service.selectedIndex + delta
    service.selectedIndex = Math.max(0, Math.min(results.count - 1, next))
  }

  // Keep the selection visible when the keyboard outruns the viewport.
  onSelectedIndexChanged: Qt.callLater(function() {
    if (service.selectedIndex >= 0 && service.selectedIndex < results.count)
      resultList.positionViewAtIndex(service.selectedIndex, ListView.Contain)
  })

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call launcher toggle`.

  IpcHandler {
    target: "launcher"

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

  // Make sure the state directory exists before the first usage save.
  // FileView does not create parent directories.
  Process {
    id: ensureStateDir

    command: ["mkdir", "-p", service.statePath.substring(0, service.statePath.lastIndexOf("/"))]
  }

  Component.onCompleted: {
    ensureStateDir.running = true
    // Prime the model so the first open is instant even if the entries
    // list never changed.
    rebuildResults()
  }

  // ----- the overlay -------------------------------------------------------
  //
  // A full-screen transparent layer-shell surface on the focused Hyprland
  // monitor: the scrim dims and swallows outside clicks (close on click),
  // the card holds the search field and results, and the layer takes
  // exclusive keyboard focus while visible. ExclusionMode.Ignore keeps it
  // off the reserved space bookkeeping, like the notifications overlay.

  PanelWindow {
    id: panel

    visible: service.opened

    // The launcher belongs to the screen being looked at — Hyprland's
    // focused monitor — falling back to the first screen if the lookup
    // misses (Quickshell 0.3 has no primaryScreen).
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
    WlrLayershell.namespace: "mike-launcher"
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
      height: cardColumn.height + 24
      anchors.centerIn: parent
      radius: 8
      color: "#f0101014"
      border.width: 1
      border.color: "#26ffffff"

      // Swallow clicks inside the card so they don't reach the scrim and
      // close the launcher.
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Column {
        id: cardColumn

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
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
              // rebuildResults owns selection state too (first row, or -1
              // when nothing matches).
              service.query = text
              service.rebuildResults()
            }

            // Navigation keys are consumed before the TextInput's own
            // handling — cursor movement inside a one-line filter field
            // matters less than moving through the results.
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              switch (event.key) {
                case Qt.Key_Escape:
                  // Omarchy's rule: the first Escape clears the filter,
                  // the second closes.
                  if (service.query.length > 0) service.setQuery("")
                  else service.close()
                  event.accepted = true
                  break
                case Qt.Key_Return:
                case Qt.Key_Enter:
                  service.launchAt(service.selectedIndex)
                  event.accepted = true
                  break
                case Qt.Key_Tab:
                  // Complete the query to the selection, fuzzel-style:
                  // refine, then Enter launches.
                  if (service.selectedIndex >= 0)
                    service.setQuery(results.get(service.selectedIndex).label)
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
                  service.moveSelection(-service.maxVisibleRows)
                  event.accepted = true
                  break
                case Qt.Key_PageDown:
                  service.moveSelection(service.maxVisibleRows)
                  event.accepted = true
                  break
                case Qt.Key_Home:
                  service.selectedIndex = results.count > 0 ? 0 : -1
                  event.accepted = true
                  break
                case Qt.Key_End:
                  service.selectedIndex = results.count - 1
                  event.accepted = true
                  break
              }
            }

            Text {
              anchors.fill: parent
              anchors.leftMargin: 1
              verticalAlignment: Text.AlignVCenter
              visible: searchInput.text.length === 0
              text: "Search apps…"
              color: service.foreground
              opacity: 0.5
              font.family: service.fontFamily
              font.pixelSize: 14
            }
          }
        }

        // ----- results -------------------------------------------------------

        Item {
          width: parent.width
          height: Math.max(service.rowHeight, Math.min(results.count, service.maxVisibleRows) * (service.rowHeight + 2) - (results.count > 0 ? 2 : 0))

          ListView {
            id: resultList

            anchors.fill: parent
            model: results
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: service.selectedIndex

            delegate: Rectangle {
              id: row

              required property int index
              required property string entryId
              required property string label
              required property string icon
              required property string detail

              width: resultList.width
              height: service.rowHeight
              radius: 6
              color: row.index === service.selectedIndex ? service.accent : rowHover.hovered ? "#1affffff" : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10

                Item {
                  id: iconSlot

                  width: 24
                  height: 24
                  anchors.verticalCenter: parent.verticalCenter

                  IconImage {
                    id: appIcon

                    anchors.fill: parent
                    implicitSize: 24
                    source: service.iconSource(row.icon)
                  }

                  // Glyph fallback for entries with no resolvable icon —
                  // the same treatment as the notification bell.
                  Text {
                    anchors.centerIn: parent
                    visible: appIcon.status !== Image.Ready
                    text: "󰀳"
                    color: service.foreground
                    font.family: service.fontFamily
                    font.pixelSize: 18
                  }
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    width: card.width - 24 - 12 - 8 - 8 - iconSlot.width - 10
                    text: row.label
                    color: row.index === service.selectedIndex ? "#101014" : service.foreground
                    font.family: service.fontFamily
                    font.pixelSize: 13
                    font.weight: row.index === service.selectedIndex ? Font.Bold : Font.Normal
                    elide: Text.ElideRight
                  }

                  // Details surface while a search narrows the list, like
                  // Omarchy's rows — they disambiguate between the five
                  // matches a term typically leaves.
                  Text {
                    width: card.width - 24 - 12 - 8 - 8 - iconSlot.width - 10
                    visible: service.query.length > 0 && row.detail.length > 0
                    text: row.detail
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
                onTapped: service.launchAt(row.index)
              }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: results.count === 0
            text: service.query.length > 0 ? "No matches" : "No applications found"
            color: service.foreground
            opacity: 0.5
            font.family: service.fontFamily
            font.pixelSize: 13
          }
        }
      }
    }
  }
}
