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
// empty query opens onto the most-used apps. Entries that ship desktop
// actions (the .desktop "Actions" group) grow them two ways: matching
// actions appear as their own rows under a query, and arrow-right drills
// into one entry's action list (arrow-left / Backspace comes back).
//
// The same overlay serves Omarchy's dmenu modes for scripts — a pick list
// (`granite-menu-select`, their omarchy-menu select) and a text prompt
// (`granite-menu-input`). The script drops temp-file paths over qs ipc;
// the answer is written back through them, and the polling script wakes
// (their temp-file handshake, kept whole).
//
// What's deliberately NOT here yet: the drilldown command/power menus
// (the system menu grows in M4 alongside lock + idle).
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

  // "apps" is the app launcher. "select" and "input" are the dmenu modes
  // scripts drive (Omarchy's omarchy-menu select / input): a pick list or
  // a text prompt whose answer returns to the calling script.
  property string mode: "apps"
  property string dmenuPrompt: ""
  // Parsed dmenu options: [{ glyph, label, detail }].
  property var dmenuOptions: []
  property string selectionFile: ""
  property string doneFile: ""
  property bool requestActive: false

  // The entry whose desktop actions are listed (arrow-right drilldown).
  property string drilldownId: ""

  // Dmenu rows and the drilldown show row subtext unconditionally: it is
  // the caller's (or the app's own) context, not search noise.
  readonly property bool detailsAlwaysVisible: mode !== "apps" || drilldownId !== ""

  ListModel { id: results }

  // DesktopAction objects parallel to the results model, one slot per row
  // (null for app and dmenu rows). QObject wrappers never go into the
  // ListModel itself — a churned entry leaves a dangling C++ pointer in a
  // model role, and the next read segfaults (Omarchy's lesson, kept from
  // the notifications daemon). A JS slot only ever degrades to a
  // catchable error.
  property var actionObjects: []

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

  // Rows for the dmenu select mode: caller-supplied options filtered by
  // substring on the label or the subtext (Omarchy's filter), keeping the
  // caller's order.
  function dmenuRowsFor(filter) {
    var q = String(filter || "").trim().toLowerCase()
    var rows = []
    for (var i = 0; i < service.dmenuOptions.length; i++) {
      var option = service.dmenuOptions[i]
      if (q && option.label.toLowerCase().indexOf(q) < 0
          && option.detail.toLowerCase().indexOf(q) < 0) continue
      rows.push({
        entryId: "",
        actionId: "",
        label: option.label,
        icon: "",
        glyph: option.glyph,
        detail: option.detail,
        hasActions: false,
        score: i,
        uses: 0
      })
    }
    return rows
  }

  function rebuildResults() {
    // A drilldown whose entry vanished (uninstall, entries churned) falls
    // back to the app list.
    if (service.mode === "apps" && service.drilldownId !== ""
        && !DesktopEntries.byId(service.drilldownId)) {
      service.drilldownId = ""
    }

    var rows
    if (service.mode === "select")
      rows = service.dmenuRowsFor(service.query)
    else if (service.mode === "input")
      rows = []  // the field is the answer; there is nothing to list
    else if (service.drilldownId !== "")
      rows = LauncherSearch.drilldownRows(DesktopEntries.byId(service.drilldownId), service.query, service.usageCounts)
    else
      rows = LauncherSearch.sortedEntries(DesktopEntries.applications.values, service.query, service.usageCounts)

    results.clear()
    var objects = []
    for (var i = 0; i < rows.length; i++) {
      results.append(rows[i])
      objects.push(rows[i].actionId ? service.actionFor(rows[i].entryId, rows[i].actionId) : null)
    }
    service.actionObjects = objects
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
    // A manual open cancels any pending script request — the overlay is a
    // single surface, and the user asked for it.
    if (service.requestActive) service.finishRequest(null)
    service.mode = "apps"
    service.drilldownId = ""
    service.opened = true
    setQuery("")
    return "opened"
  }

  function close() {
    if (service.requestActive) service.finishRequest(null)
    service.mode = "apps"
    service.drilldownId = ""
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
    if (service.mode === "input") {
      service.finishRequest(searchInput.text)
      service.mode = "apps"
      service.opened = false
      return
    }
    if (service.mode === "select") {
      if (index < 0 || index >= results.count) return
      var picked = results.get(index)
      // Omarchy's rule: a plain option returns its label; one with subtext
      // returns "<label><TAB><subtext>" — a stable key for same-named rows.
      service.finishRequest(picked.detail ? picked.label + "\t" + picked.detail : picked.label)
      service.mode = "apps"
      service.opened = false
      return
    }
    if (index < 0 || index >= results.count) return
    var row = results.get(index)
    rememberUse(row.entryId)
    var action = row.actionId ? (service.actionObjects[index] || null) : null
    if (action) launchAction(action)
    else Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", row.entryId + ".desktop"])
    close()
  }

  // A desktop action launches its own command (field codes already
  // stripped by Quickshell's exec parser) through the same uwsm-app scope
  // recipe as the app itself — gtk-launch has no way to reach actions.
  function launchAction(action) {
    var command = []
    try {
      for (var i = 0; i < action.command.length; i++) command.push(String(action.command[i]))
    } catch (e) {
      console.warn("launcher: desktop action unreadable:", e)
      return
    }
    if (command.length === 0) return
    Quickshell.execDetached(["uwsm-app", "--"].concat(command))
  }

  // The DesktopAction object for a row, resolved fresh from the entry —
  // never cached across rebuilds, so entry churn can't leave a stale
  // wrapper in play longer than the list it belongs to.
  function actionFor(entryId, actionId) {
    var entry = DesktopEntries.byId(entryId)
    if (!entry) return null
    var actions = LauncherSearch.entryActions(entry)
    for (var i = 0; i < actions.length; i++) {
      if (String(actions[i].id) === String(actionId)) return actions[i]
    }
    return null
  }

  // ----- the desktop-action drilldown --------------------------------------

  function enterDrilldown(index) {
    if (service.mode !== "apps" || service.drilldownId !== "") return
    if (index < 0 || index >= results.count) return
    var row = results.get(index)
    if (row.actionId || !row.hasActions) return
    service.drilldownId = row.entryId
    service.selectedIndex = 0
    rebuildResults()
  }

  function exitDrilldown() {
    if (service.drilldownId === "") return
    var restoreId = service.drilldownId
    service.drilldownId = ""
    rebuildResults()
    // Land the selection back on the entry whose actions were just left,
    // when it is still in the list.
    for (var i = 0; i < results.count; i++) {
      var row = results.get(i)
      if (row.entryId === restoreId && !row.actionId) {
        service.selectedIndex = i
        break
      }
    }
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

  // ----- dmenu requests ----------------------------------------------------
  //
  // Scripts drive the overlay as a menu: granite-menu-select / -input (see
  // config/hypr/bin) drop two temp-file paths over qs ipc, the user picks,
  // and the answer lands in the selection file followed by the done file —
  // Omarchy's handshake, kept whole so porting their scripts is mechanical.

  function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function startDmenu(kind, prompt, selectionPath, donePath, options) {
    // A new request replaces any pending one — the previous script's poll
    // unblocks with no selection instead of hanging forever.
    if (service.requestActive) service.finishRequest(null)

    service.mode = kind
    service.dmenuPrompt = String(prompt || (kind === "input" ? "Input" : "Select"))
    service.selectionFile = String(selectionPath || "")
    service.doneFile = String(donePath || "")
    service.requestActive = service.doneFile.length > 0
    service.drilldownId = ""

    // An option line is "<label>", "<glyph>\t<label>", or
    // "<glyph>\t<label>\t<subtext>" (Omarchy's format): the glyph shows but
    // never returns; the subtext renders under the label, filters with it,
    // and returns as the stable key for same-named rows.
    var parsed = []
    var lines = String(options || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue
      var parts = lines[i].split("\t")
      var glyph = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (!label) continue
      parsed.push({ glyph: glyph, label: label, detail: detail })
    }
    service.dmenuOptions = parsed

    if (kind === "select" && parsed.length === 0) {
      // Nothing to pick from — fail the request now rather than showing an
      // empty menu the caller can't do anything with.
      service.finishRequest(null)
      service.mode = "apps"
      return "error: no options"
    }

    service.opened = true
    setQuery("")
    return "ok"
  }

  // Hand the answer back to the waiting script: the selection (null =
  // cancelled) lands in the selection file, then the done file appears and
  // the polling script unblocks.
  function finishRequest(selection) {
    if (!service.requestActive || !service.doneFile) {
      service.opened = false
      return
    }

    var selectionPath = service.selectionFile
    var donePath = service.doneFile
    service.requestActive = false
    service.selectionFile = ""
    service.doneFile = ""

    if (selection === null || selection === undefined) {
      resultProc.command = ["bash", "-c", ": > " + shellQuote(donePath)]
    } else {
      resultProc.command = [
        "bash", "-c",
        "printf '%s\\n' " + shellQuote(selection) + " > " + shellQuote(selectionPath)
          + "; : > " + shellQuote(donePath)
      ]
    }
    service.runResultProc()
  }

  // A Process ignores a command change while it is running, and the write
  // itself is a millisecond of bash — if one is still in flight, land the
  // next on the following event-loop turn instead of dropping it (a
  // dropped done file would hang the polling script forever).
  function runResultProc() {
    if (resultProc.running) {
      Qt.callLater(service.runResultProc)
      return
    }
    resultProc.running = true
  }

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call launcher toggle`, and the
  // dmenu pair behind granite-menu-select / granite-menu-input (qs ipc
  // passes each argument through untouched, so the option list rides as
  // one newline-joined string).

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

    function dmenuSelect(prompt: string, selectionFile: string, doneFile: string, options: string): string {
      return service.startDmenu("select", prompt, selectionFile, doneFile, options)
    }

    function dmenuInput(prompt: string, selectionFile: string, doneFile: string): string {
      return service.startDmenu("input", prompt, selectionFile, doneFile, "")
    }

    function ping(): string {
      return "ok"
    }
  }

  // Writes the dmenu answer back to the calling script's temp files.
  Process {
    id: resultProc
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
                  // Omarchy's ladder: the first Escape clears the filter,
                  // the second leaves a drilldown, the third closes. In the
                  // input mode the typed text is the answer, so clearing it
                  // first is also cancelling in two steps.
                  if (service.query.length > 0) service.setQuery("")
                  else if (service.drilldownId !== "") service.exitDrilldown()
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
                  // refine, then Enter launches. Apps mode only — in the
                  // dmenu modes the text is the answer, not a filter to
                  // complete against hidden app rows.
                  if (service.mode === "apps" && service.selectedIndex >= 0)
                    service.setQuery(results.get(service.selectedIndex).label)
                  event.accepted = true
                  break
                case Qt.Key_Right:
                  // Arrow-right opens the selected entry's desktop actions
                  // (the chevron rows); anything else lets the cursor move.
                  service.enterDrilldown(service.selectedIndex)
                  event.accepted = service.drilldownId !== ""
                  break
                case Qt.Key_Left:
                case Qt.Key_Backspace:
                  // Leaving a drilldown only when there is nothing to edit
                  // left in the field — otherwise the keys keep typing.
                  if (service.drilldownId !== "" && service.query.length === 0) {
                    service.exitDrilldown()
                    event.accepted = true
                  }
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
              // The field doubles as the dmenu surface, like Omarchy's menu
              // header: empty, it names what is being asked for.
              text: {
                if (service.mode !== "apps") return service.dmenuPrompt + "…"
                if (service.drilldownId !== "") return "Filter actions…"
                return "Search apps…"
              }
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
          // The input mode is just the field — no rows, no empty-state
          // label pretending to be one.
          height: service.mode === "input" ? 0 : Math.max(service.rowHeight, Math.min(results.count, service.maxVisibleRows) * (service.rowHeight + 2) - (results.count > 0 ? 2 : 0))

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
              required property string actionId
              required property string label
              required property string icon
              required property string glyph
              required property string detail
              required property bool hasActions

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
                    visible: row.glyph.length === 0
                    source: row.glyph.length === 0 ? service.iconSource(row.icon) : ""
                  }

                  // Glyph fallback for entries with no resolvable icon —
                  // the same treatment as the notification bell — and the
                  // slot for a dmenu option's caller-supplied glyph, which
                  // renders as text like Omarchy's rows.
                  Text {
                    anchors.centerIn: parent
                    visible: row.glyph.length > 0 || appIcon.status !== Image.Ready
                    text: row.glyph.length > 0 ? row.glyph : "󰀳"
                    color: service.foreground
                    font.family: service.fontFamily
                    font.pixelSize: 18
                  }
                }

                Column {
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 1

                  Text {
                    width: row.textWidth
                    text: row.label
                    color: row.index === service.selectedIndex ? "#101014" : service.foreground
                    font.family: service.fontFamily
                    font.pixelSize: 13
                    font.weight: row.index === service.selectedIndex ? Font.Bold : Font.Normal
                    elide: Text.ElideRight
                  }

                  // Details surface while a search narrows the list, like
                  // Omarchy's rows — they disambiguate between the five
                  // matches a term typically leaves. Dmenu rows and the
                  // drilldown keep them always on: the subtext is the
                  // caller's (or the app's own) context, not noise.
                  Text {
                    width: row.textWidth
                    visible: (service.query.length > 0 || service.detailsAlwaysVisible) && row.detail.length > 0
                    text: row.detail
                    color: row.index === service.selectedIndex ? "#40101014" : service.foreground
                    opacity: 0.55
                    font.family: service.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                  }
                }

                // Rows with desktop actions grow a chevron: arrow-right
                // drills into them (Omarchy's submenu affordance).
                Text {
                  id: chevron

                  anchors.verticalCenter: parent.verticalCenter
                  visible: row.hasActions && service.mode === "apps" && service.drilldownId === ""
                  text: "›"
                  color: row.index === service.selectedIndex ? "#101014" : service.foreground
                  opacity: 0.5
                  font.family: service.fontFamily
                  font.pixelSize: 15
                }
              }

              HoverHandler {
                id: rowHover

                onHoveredChanged: if (hovered) service.selectedIndex = row.index
              }

              TapHandler {
                onTapped: service.launchAt(row.index)
              }

              // The label/details width: the card minus its chrome and the
              // icon slot, giving the chevron its room when one shows.
              readonly property real textWidth: card.width - 24 - 12 - 8 - 8 - iconSlot.width - 10 - (chevron.visible ? 18 : 0)
            }
          }

          Text {
            anchors.centerIn: parent
            visible: results.count === 0 && service.mode !== "input"
            text: service.query.length > 0 ? "No matches" : service.mode === "select" ? "No options" : "No applications found"
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
