// M8: the audio + media panel. SUPER+CTRL+A (bound in hyprland.lua via
// `qs ipc call audio toggle`, Omarchy Quattro's audio binding) opens the
// launcher's centered card on the focused monitor with both halves of
// the desktop's sound: the media half — MPRIS now-playing (art, title,
// artist, transport, a seekable position bar, and a player picker when
// more than one player exists) through the shared Media.qml service —
// and the sink half, ported from Omarchy's audio panel: output/input
// volume sliders with mute, the device lists that pick the default
// sink/source, and an input peak meter.
//
// Omarchy behaviors kept, simplified: device rows that set the default
// through Pipewire.preferredDefaultAudioSink/Source, node label
// friendlification and glyph picking (headphones, bluetooth, hdmi,
// webcam) from the node's own name blob, panel-local snapshots of the
// pipewire node lists fed through a short settle timer (rebuilding
// repeaters straight from a removal signal has crashed Quickshell's
// pipewire service), and a cached last-good list so a scan flickering
// empty doesn't blank the panel. Deliberately NOT here vs Omarchy:
// per-app stream mixers, their DSP/tuning sink resolution (granite runs
// no filter chains; the default sink is where loudness lives),
// sink-availability polling for reconnecting bluetooth headsets, their
// sectioned keyboard cursor (granite gets the same reach from a flat row
// ladder — return activates, arrows adjust), and the playful volume
// mood-names.
//
// The panel holds the OSD's volume popup while open (its own sliders are
// on screen); transport actions run through Media.qml with feedback off
// for the same reason.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import QtQuick

Item {
  id: service

  // Wired to the shell's Media and Osd instances by shell.qml.
  property var media: null
  property var osd: null

  // Palette shared with Bar.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"

  // ----- tuning ------------------------------------------------------------

  readonly property int cardWidth: 460
  readonly property int rowHeight: 40
  readonly property int headerHeight: 28
  readonly property int mediaRowHeight: 112
  readonly property real volumeStep: 0.05
  readonly property int seekStepSeconds: 5
  readonly property int transportButtonSize: 34
  readonly property int transportSpacing: 6
  readonly property int timeReadoutWidth: 96

  // ----- state -------------------------------------------------------------

  property bool opened: false
  property int selectedIndex: 0

  // The flat cursor ladder: headers and hints render but never take the
  // cursor; everything else is return-activatable and hover-selectable.
  property var cursorRows: []

  // ----- pipewire: the default channels -------------------------------------

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource

  readonly property double outputVolume: sink !== null && sink.audio !== null && sink.audio.volumes.length > 0 ? sink.audio.volume : 0
  readonly property bool outputMuted: sink !== null && sink.audio !== null && sink.audio.volumes.length > 0 ? sink.audio.muted : false
  readonly property double inputVolume: source !== null && source.audio !== null && source.audio.volumes.length > 0 ? source.audio.volume : 0
  readonly property bool inputMuted: source !== null && source.audio !== null && source.audio.volumes.length > 0 ? source.audio.muted : false

  function setOutputVolume(v) {
    if (sink === null || sink.audio === null) return
    sink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function setInputVolume(v) {
    if (source === null || source.audio === null) return
    source.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() {
    if (sink !== null && sink.audio !== null) sink.audio.muted = !sink.audio.muted
  }

  function toggleInputMute() {
    if (source !== null && source.audio !== null) source.audio.muted = !source.audio.muted
  }

  // ----- pipewire: the device lists -----------------------------------------
  //
  // Sinks are every non-stream sink node; sources are non-sink non-stream
  // nodes that look like audio capture (the quickshell node itself is
  // skipped). The defaults are merged in even when a scan misses them.

  function isAudioSource(node) {
    if (!node) return false
    if (node.audio) return true
    var mediaClass = String(node.type || "")
    return mediaClass.indexOf("Audio/Source") !== -1
      || mediaClass.indexOf("AudioSource") !== -1
      || mediaClass.indexOf("Source") !== -1
  }

  readonly property var candidateSinks: {
    var list = []
    var values = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < values.length; i++) {
      var n = values[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }

  readonly property var candidateSources: {
    var list = []
    var values = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < values.length; i++) {
      var n = values[i]
      if (n && !n.isSink && !n.isStream && isAudioSource(n)) {
        if (String(n.name || "") === "quickshell") continue
        list.push(n)
      }
    }
    return list
  }

  // Default first, then by label — a stable ladder for the keyboard.
  readonly property var sinks: {
    var list = candidateSinks.slice()
    if (sink !== null && list.indexOf(sink) < 0) list.unshift(sink)
    list.sort(function(a, b) {
      var aDefault = sink !== null && a.id === sink.id ? 1 : 0
      var bDefault = sink !== null && b.id === sink.id ? 1 : 0
      if (aDefault !== bDefault) return bDefault - aDefault
      return nodeLabel(a).localeCompare(nodeLabel(b))
    })
    return list
  }

  readonly property var sources: {
    var list = candidateSources.slice()
    if (source !== null && list.indexOf(source) < 0) list.unshift(source)
    list.sort(function(a, b) {
      var aDefault = source !== null && a.id === source.id ? 1 : 0
      var bDefault = source !== null && b.id === source.id ? 1 : 0
      if (aDefault !== bDefault) return bDefault - aDefault
      return nodeLabel(a).localeCompare(nodeLabel(b))
    })
    return list
  }

  // The lists' audio interfaces only exist while something holds a
  // reference — track everything the panel can show.
  PwObjectTracker {
    objects: {
      var tracked = service.sinks.slice()
      return tracked.concat(service.sources)
    }
  }

  function setDefaultSink(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSink = node
  }

  function setDefaultSource(node) {
    if (!node) return
    Pipewire.preferredDefaultAudioSource = node
  }

  // ----- device labels + glyphs ----------------------------------------------
  //
  // Ported from Omarchy's audio panel model: the nickname blob names the
  // device class for the glyph, and marketing noise falls off the label.

  function nodeProps(node) {
    return node && node.ready && node.properties ? node.properties : {}
  }

  function friendlyDeviceLabel(text) {
    var label = String(text || "").trim()
    label = label.replace(/^sof-soundwire\s+/i, "")
    label = label.replace(/^built-?in audio\s+/i, "")
    label = label.replace(/\s+Output$/i, "")
    label = label.replace(/\s+Input$/i, "")
    label = label.replace(/\bMicrophones\b/g, "Microphone")
    return label
  }

  function nodeLabel(node) {
    if (!node) return "Unknown"
    var p = nodeProps(node)
    var nickname = friendlyDeviceLabel(node.nickname || node.description || p["node.description"] || p["device.profile.description"] || "")
    if (nickname) return nickname
    return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "Unknown")
  }

  function nodeBlob(node) {
    if (!node) return ""
    var p = nodeProps(node)
    return String([
      node.name, node.description, node.nickname,
      p["device.icon-name"] || "",
      p["device.product.name"] || "",
      p["node.description"] || "",
      p["node.nick"] || ""
    ].join(" ")).toLowerCase()
  }

  function isHeadphones(node) {
    var blob = nodeBlob(node)
    return blob.indexOf("headphone") !== -1
      || blob.indexOf("headset") !== -1
      || blob.indexOf("earbud") !== -1
      || blob.indexOf("earphone") !== -1
      || blob.indexOf("airpod") !== -1
  }

  function sinkGlyph(node) {
    if (!node) return "󰓃"
    if (isHeadphones(node)) return "󰋋"
    var blob = nodeBlob(node)
    if (blob.indexOf("bluetooth") !== -1) return "󰂯"
    if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1) return "󰍹"
    return "󰓃"
  }

  function sourceGlyph(node) {
    if (!node) return "󰍬"
    var blob = nodeBlob(node)
    if (blob.indexOf("headset") !== -1) return "󰋋"
    if (blob.indexOf("bluetooth") !== -1) return "󰂯"
    if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1) return "󰄀"
    return "󰍬"
  }

  // The default output's glyph follows the level, like the OSD's.
  function outputGlyph() {
    if (sink === null || sink.audio === null) return ""
    if (isHeadphones(sink)) return "󰋋"
    if (outputMuted) return ""
    if (outputVolume >= 0.67) return ""
    if (outputVolume >= 0.34) return ""
    if (outputVolume > 0) return ""
    return ""
  }

  function inputGlyph() {
    if (source === null || source.audio === null) return "󰍭"
    return inputMuted ? "󰍭" : "󰍬"
  }

  // ----- display snapshots ---------------------------------------------------
  //
  // The live pipewire model can remove nodes while Quickshell is
  // dispatching the removal signal; rebuilding rows straight from that
  // signal path has crashed Quickshell's pipewire service. Snapshots let
  // the mutation settle first (Omarchy's recipe), and a closed panel
  // keeps its repeaters detached entirely. The last non-empty list is
  // kept so a scan flickering empty mid-transition doesn't blank rows.

  property var displaySinks: []
  property var displaySources: []
  property var displayPlayers: []

  Timer {
    id: refreshTimer

    interval: 75
    onTriggered: service.refreshModels()
  }

  function scheduleRefresh() {
    if (!opened) return
    refreshTimer.restart()
  }

  function refreshModels() {
    if (!opened) return
    if (sinks.length > 0 || displaySinks.length === 0) displaySinks = sinks.slice()
    if (sources.length > 0 || displaySources.length === 0) displaySources = sources.slice()
    displayPlayers = media !== null ? media.orderedPlayers.slice() : []
    rebuildRows()
  }

  onSinksChanged: scheduleRefresh()
  onSourcesChanged: scheduleRefresh()

  Connections {
    target: service.media

    function onOrderedPlayersChanged() {
      service.scheduleRefresh()
    }
  }

  // ----- the row ladder -------------------------------------------------------

  function rebuildRows() {
    var rows = []

    rows.push({ kind: "header", label: "MEDIA" })
    if (media !== null && displayPlayers.length > 0) {
      rows.push({ kind: "media" })
      for (var i = 0; i < displayPlayers.length; i++)
        rows.push({ kind: "player", player: displayPlayers[i] })
    } else {
      rows.push({ kind: "hint", label: "No media player" })
    }

    rows.push({ kind: "header", label: "OUTPUT" })
    if (sink !== null && sink.audio !== null) {
      rows.push({ kind: "volume", channel: "output" })
    } else {
      rows.push({ kind: "hint", label: "No output device" })
    }
    for (var s = 0; s < displaySinks.length; s++)
      rows.push({ kind: "device", node: displaySinks[s], channel: "output" })

    if (source !== null && source.audio !== null) {
      rows.push({ kind: "header", label: "INPUT" })
      rows.push({ kind: "volume", channel: "input" })
      for (var r = 0; r < displaySources.length; r++)
        rows.push({ kind: "device", node: displaySources[r], channel: "input" })
    }

    cursorRows = rows
    clampSelection()
  }

  function rowSelectable(row) {
    return row !== undefined && row.kind !== "header" && row.kind !== "hint"
  }

  function firstSelectable() {
    for (var i = 0; i < cursorRows.length; i++)
      if (rowSelectable(cursorRows[i])) return i
    return -1
  }

  function lastSelectable() {
    for (var i = cursorRows.length - 1; i >= 0; i--)
      if (rowSelectable(cursorRows[i])) return i
    return -1
  }

  function clampSelection() {
    if (selectedIndex >= 0 && selectedIndex < cursorRows.length && rowSelectable(cursorRows[selectedIndex]))
      return
    selectedIndex = selectedIndex > lastSelectable() ? lastSelectable() : firstSelectable()
  }

  function moveSelection(delta) {
    var next = selectedIndex
    for (var steps = Math.abs(delta); steps > 0; steps--) {
      do {
        next += delta > 0 ? 1 : -1
      } while (next >= 0 && next < cursorRows.length && !rowSelectable(cursorRows[next]))
      if (next < 0 || next >= cursorRows.length) return
    }
    selectedIndex = next
  }

  // ----- acting on rows -------------------------------------------------------

  function activePlayerKey() {
    return media !== null && media.activePlayer !== null ? media.playerKey(media.activePlayer) : ""
  }

  function activateRow(index) {
    if (index < 0 || index >= cursorRows.length) return
    var entry = cursorRows[index]

    if (entry.kind === "media") {
      if (media !== null) media.runAction("playPause", false, activePlayerKey())
    } else if (entry.kind === "player") {
      if (media !== null) media.selectPlayer(media.playerKey(entry.player))
    } else if (entry.kind === "volume") {
      if (entry.channel === "input") toggleInputMute()
      else toggleOutputMute()
    } else if (entry.kind === "device") {
      if (entry.channel === "input") setDefaultSource(entry.node)
      else setDefaultSink(entry.node)
    }
  }

  // Left/Right on a row: sliders step their channel, the media row seeks.
  function stepRow(direction) {
    if (selectedIndex < 0 || selectedIndex >= cursorRows.length) return
    var entry = cursorRows[selectedIndex]

    if (entry.kind === "volume") {
      if (entry.channel === "input") setInputVolume(inputVolume + direction * volumeStep)
      else setOutputVolume(outputVolume + direction * volumeStep)
    } else if (entry.kind === "media") {
      seekBy(direction * seekStepSeconds)
    }
  }

  // ----- position --------------------------------------------------------------

  property double displayPosition: 0

  Timer {
    id: positionTimer

    interval: 1000
    repeat: true
    running: service.opened && service.media !== null && service.media.activePlayer !== null
      && service.media.activePlayer.isPlaying && service.media.activePlayer.positionSupported
    onTriggered: service.syncPosition()
  }

  Connections {
    target: service.media !== null ? service.media.activePlayer : null

    // Players push position irregularly (many only on Seeked); the timer
    // above tops it up to once a second while playing.
    function onPositionChanged() {
      service.syncPosition()
    }

    function onTrackTitleChanged() {
      service.syncPosition()
    }
  }

  Connections {
    target: service.media

    function onActivePlayerChanged() {
      service.syncPosition()
    }
  }

  function syncPosition() {
    var player = media !== null ? media.activePlayer : null
    displayPosition = player !== null && player.positionSupported ? player.position : 0
  }

  function playerLength() {
    var player = media !== null ? media.activePlayer : null
    return player !== null && player.lengthSupported ? player.length : 0
  }

  function seekBy(seconds) {
    seekTo(displayPosition + seconds)
  }

  function seekTo(seconds) {
    var player = media !== null ? media.activePlayer : null
    if (player === null || !player.canSeek || !player.positionSupported) return
    var length = playerLength()
    var target = Math.max(0, length > 0 ? Math.min(length - 1, seconds) : seconds)
    player.position = target
    displayPosition = target
  }

  function formatTime(seconds) {
    var total = Math.max(0, Math.floor(seconds))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    var rest = total % 60
    var minuteText = (hours > 0 && minutes < 10 ? "0" : "") + minutes
    var secondText = (rest < 10 ? "0" : "") + rest
    return hours > 0 ? hours + ":" + minuteText + ":" + secondText : minuteText + ":" + secondText
  }

  // ----- input peak -------------------------------------------------------------

  PwNodePeakMonitor {
    id: inputPeak

    node: service.source
    enabled: service.opened && service.source !== null
  }

  // ----- open / close -------------------------------------------------------------

  function open() {
    service.opened = true
    // The panel's sliders are on screen; the OSD's external-change popup
    // would only talk over them.
    if (service.osd !== null) service.osd.volumePopupHeld = true
    refreshModels()
    syncPosition()
    return "opened"
  }

  function close() {
    service.opened = false
    if (service.osd !== null) service.osd.volumePopupHeld = false
    displaySinks = []
    displaySources = []
    displayPlayers = []
    cursorRows = []
    return "closed"
  }

  function toggle() {
    return service.opened ? close() : open()
  }

  // ----- IPC -----------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call audio toggle`.

  IpcHandler {
    target: "audio"

    function toggle(): string {
      return service.toggle()
    }

    function open(): string {
      return service.open()
    }

    function close(): string {
      return service.close()
    }

    function status(): string {
      return JSON.stringify({
        opened: service.opened,
        sinks: service.sinks.length,
        sources: service.sources.length,
        players: service.media !== null ? service.media.players.length : 0,
        activePlayer: service.media !== null ? service.media.mediaMessage(service.media.activePlayer, "") : "",
        outputPercent: Math.round(service.outputVolume * 100),
        outputMuted: service.outputMuted,
        inputPercent: Math.round(service.inputVolume * 100),
        inputMuted: service.inputMuted
      })
    }

    function ping(): string {
      return "ok"
    }
  }

  // ----- the overlay -----------------------------------------------------------
  //
  // Same surface recipe as the launcher and session menu: full-screen
  // transparent layer on the focused Hyprland monitor, scrim closes, card
  // holds the rows, and the layer takes exclusive keyboard focus while
  // visible — the card itself (there is no text field to borrow it from).

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
    WlrLayershell.namespace: "mike-audio"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

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

      // Swallow clicks inside the card so they don't reach the scrim and
      // close the panel.
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
            service.activateRow(service.selectedIndex)
            event.accepted = true
            break
          case Qt.Key_Left:
            service.stepRow(-1)
            event.accepted = true
            break
          case Qt.Key_Right:
            service.stepRow(1)
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
            service.moveSelection(-6)
            event.accepted = true
            break
          case Qt.Key_PageDown:
            service.moveSelection(6)
            event.accepted = true
            break
          case Qt.Key_Home:
            service.selectedIndex = service.firstSelectable()
            event.accepted = true
            break
          case Qt.Key_End:
            service.selectedIndex = service.lastSelectable()
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
          model: service.cursorRows

          delegate: Rectangle {
            id: row

            required property int index
            required property var modelData

            readonly property string kind: modelData.kind || ""
            readonly property bool isInputRow: modelData.channel === "input"
            readonly property bool selectable: service.rowSelectable(modelData)
            readonly property bool current: row.selectable && row.index === service.selectedIndex

            width: cardColumn.width
            height: kind === "header" || kind === "hint" ? service.headerHeight
              : kind === "media" ? service.mediaRowHeight
              : service.rowHeight
            radius: 6
            // The media hero is a composite, not a button: selection
            // outlines it instead of filling it.
            color: row.current && row.kind !== "media" ? service.accent : rowHover.hovered ? "#1affffff" : "transparent"
            border.width: row.current && row.kind === "media" ? 1 : 0
            border.color: service.accent

            HoverHandler {
              id: rowHover

              enabled: row.selectable
              onHoveredChanged: if (hovered) service.selectedIndex = row.index
            }

            // ----- headers + hints --------------------------------------

            Text {
              visible: row.kind === "header"
              anchors.left: parent.left
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.label
              color: service.foreground
              opacity: 0.45
              font.family: service.fontFamily
              font.pixelSize: 10
              font.bold: true
              font.letterSpacing: 1.2
            }

            Text {
              visible: row.kind === "hint"
              anchors.left: parent.left
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.label
              color: service.foreground
              opacity: 0.4
              font.family: service.fontFamily
              font.pixelSize: 12
            }

            // ----- the media hero + transport ---------------------------

            Column {
              id: mediaColumn

              visible: row.kind === "media"
              anchors.fill: parent
              anchors.margins: 8
              spacing: 6

              readonly property var player: service.media !== null ? service.media.activePlayer : null
              readonly property bool hasPosition: !!(player && player.positionSupported && player.lengthSupported && service.playerLength() > 0)

              Row {
                spacing: 12

                // Art, or a glyph tile when the player ships none.
                Item {
                  width: 56
                  height: 56

                  Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: "#22000000"
                    border.width: 1
                    border.color: "#26ffffff"
                    visible: art.status !== Image.Ready
                  }

                  Text {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: "󰝚"
                    color: service.foreground
                    opacity: 0.6
                    font.family: service.fontFamily
                    font.pixelSize: 24
                  }

                  Image {
                    id: art

                    anchors.fill: parent
                    source: mediaColumn.player && mediaColumn.player.trackArtUrl ? mediaColumn.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                  }
                }

                Column {
                  width: mediaColumn.width - 56 - 12
                  spacing: 2
                  anchors.verticalCenter: parent.verticalCenter

                  Text {
                    width: parent.width
                    text: mediaColumn.player
                      ? (mediaColumn.player.trackTitle || service.media.playerLabel(mediaColumn.player))
                      : ""
                    color: service.foreground
                    font.family: service.fontFamily
                    font.pixelSize: 14
                    font.weight: Font.Bold
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    visible: !!(mediaColumn.player && (mediaColumn.player.trackArtist || mediaColumn.player.trackAlbum))
                    text: {
                      if (!mediaColumn.player) return ""
                      var parts = []
                      if (mediaColumn.player.trackArtist) parts.push(mediaColumn.player.trackArtist)
                      if (mediaColumn.player.trackAlbum) parts.push(mediaColumn.player.trackAlbum)
                      return parts.join(" — ")
                    }
                    color: service.foreground
                    opacity: 0.7
                    font.family: service.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    visible: !!(mediaColumn.player && mediaColumn.player.identity)
                    text: mediaColumn.player ? mediaColumn.player.identity : ""
                    color: service.foreground
                    opacity: 0.45
                    font.family: service.fontFamily
                    font.pixelSize: 11
                    elide: Text.ElideRight
                  }
                }
              }

              // Transport + time readout.
              Row {
                id: transportRow

                spacing: service.transportSpacing

                TransportButton {
                  glyph: "󰒮"
                  enabled: !!(mediaColumn.player && mediaColumn.player.canGoPrevious)
                  onTriggered: if (service.media !== null) service.media.runAction("previous", false, service.activePlayerKey())
                }

                TransportButton {
                  glyph: mediaColumn.player && mediaColumn.player.isPlaying ? "󰏤" : "󰐊"
                  enabled: !!(mediaColumn.player && (mediaColumn.player.canTogglePlaying || mediaColumn.player.canPlay || mediaColumn.player.canPause))
                  onTriggered: if (service.media !== null) service.media.runAction("playPause", false, service.activePlayerKey())
                }

                TransportButton {
                  glyph: "󰒭"
                  enabled: !!(mediaColumn.player && mediaColumn.player.canGoNext)
                  onTriggered: if (service.media !== null) service.media.runAction("next", false, service.activePlayerKey())
                }

                PositionBar {
                  visible: mediaColumn.hasPosition
                  width: mediaColumn.width - 3 * service.transportButtonSize - 4 * service.transportSpacing - service.timeReadoutWidth
                  anchors.verticalCenter: parent.verticalCenter

                  onSought: function(fraction) {
                    service.seekTo(fraction * service.playerLength())
                  }
                }

                Text {
                  visible: mediaColumn.hasPosition
                  width: service.timeReadoutWidth
                  anchors.verticalCenter: parent.verticalCenter
                  horizontalAlignment: Text.AlignRight
                  text: service.formatTime(service.displayPosition) + " / " + service.formatTime(service.playerLength())
                  color: service.foreground
                  opacity: 0.55
                  font.family: service.fontFamily
                  font.pixelSize: 11
                }
              }
            }

            // ----- player rows --------------------------------------------

            Row {
              visible: row.kind === "player"
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 10

              Text {
                width: 22
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.player && row.modelData.player.isPlaying ? "󰐊" : "󰏚"
                color: row.current ? "#101014" : service.foreground
                font.family: service.fontFamily
                font.pixelSize: 14
              }

              Text {
                width: parent.width * 0.45 - 22
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData.player ? service.media.playerLabel(row.modelData.player) : ""
                color: row.current ? "#101014" : service.foreground
                font.family: service.fontFamily
                font.pixelSize: 12
                font.weight: row.current ? Font.Bold : Font.Normal
                elide: Text.ElideRight
              }

              Text {
                width: parent.width - 22 - 10 - parent.width * 0.45 - 10 - playerMark.width - 10
                anchors.verticalCenter: parent.verticalCenter
                visible: !!(row.modelData.player && row.modelData.player.trackTitle)
                text: row.modelData.player ? row.modelData.player.trackTitle : ""
                color: row.current ? "#40101014" : service.foreground
                opacity: 0.55
                font.family: service.fontFamily
                font.pixelSize: 11
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
              }

              Text {
                id: playerMark

                anchors.verticalCenter: parent.verticalCenter
                visible: !!(row.modelData.player && service.activePlayerKey() !== "" && service.media.playerKey(row.modelData.player) === service.activePlayerKey())
                text: "●"
                color: row.current ? "#101014" : service.accent
                font.family: service.fontFamily
                font.pixelSize: 12
              }
            }

            // ----- volume rows ----------------------------------------------

            Row {
              visible: row.kind === "volume"
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 10

              Rectangle {
                width: 26
                height: 26
                radius: 6
                anchors.verticalCenter: parent.verticalCenter
                color: muteGlyphMouse.containsMouse ? "#1affffff" : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: row.isInputRow ? service.inputGlyph() : service.outputGlyph()
                  color: row.current ? "#101014" : service.foreground
                  font.family: service.fontFamily
                  font.pixelSize: 15
                }

                MouseArea {
                  id: muteGlyphMouse

                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (row.isInputRow) service.toggleInputMute()
                    else service.toggleOutputMute()
                  }
                }
              }

              VolumeBar {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 26 - 10 - 48 - 10
                value: row.isInputRow ? service.inputVolume : service.outputVolume
                dimmed: row.isInputRow ? service.inputMuted : service.outputMuted
                onMoved: function(v) {
                  if (row.isInputRow) service.setInputVolume(v)
                  else service.setOutputVolume(v)
                }
              }

              Text {
                width: 48
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: Math.round((row.isInputRow ? service.inputVolume : service.outputVolume) * 100) + "%"
                color: row.current ? "#101014" : service.foreground
                opacity: (row.isInputRow ? service.inputMuted : service.outputMuted) ? 0.45 : 1
                font.family: service.fontFamily
                font.pixelSize: 12
              }
            }

            // ----- the input peak meter, under the input volume row ----------

            Rectangle {
              visible: row.kind === "volume" && row.isInputRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: 44
              anchors.rightMargin: 8
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 2
              height: 3
              radius: 1.5
              color: "#22ffffff"

              Rectangle {
                height: parent.height
                radius: 1.5
                width: parent.width * Math.max(0, Math.min(1, inputPeak.peak))
                color: service.accent

                Behavior on width {
                  NumberAnimation {
                    duration: 70
                  }
                }
              }
            }

            // ----- device rows -----------------------------------------------

            Row {
              visible: row.kind === "device"
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 10

              readonly property bool isDefault: !!row.modelData.node
                && ((row.modelData.channel === "output" && service.sink !== null && row.modelData.node.id === service.sink.id)
                  || (row.modelData.channel === "input" && service.source !== null && row.modelData.node.id === service.source.id))

              Text {
                width: 22
                horizontalAlignment: Text.AlignHCenter
                anchors.verticalCenter: parent.verticalCenter
                text: row.isInputRow ? service.sourceGlyph(row.modelData.node) : service.sinkGlyph(row.modelData.node)
                color: row.current ? "#101014" : service.foreground
                font.family: service.fontFamily
                font.pixelSize: 15
              }

              Text {
                width: parent.width - 22 - 10 - deviceMark.width - 10
                anchors.verticalCenter: parent.verticalCenter
                text: service.nodeLabel(row.modelData.node)
                color: row.current ? "#101014" : service.foreground
                font.family: service.fontFamily
                font.pixelSize: 12
                font.weight: parent.isDefault ? Font.Bold : Font.Normal
                elide: Text.ElideRight
              }

              Text {
                id: deviceMark

                anchors.verticalCenter: parent.verticalCenter
                visible: parent.isDefault
                text: "●"
                color: row.current ? "#101014" : service.accent
                font.family: service.fontFamily
                font.pixelSize: 12
              }
            }

            TapHandler {
              enabled: row.selectable && (row.kind === "player" || row.kind === "device")
              onTapped: service.activateRow(row.index)
            }
          }
        }

        // ----- footer ---------------------------------------------------------

        Item {
          width: parent.width
          height: 24

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "return select · ←→ adjust / seek · esc close"
            color: service.foreground
            opacity: 0.55
            font.family: service.fontFamily
            font.pixelSize: 11
          }
        }
      }
    }
  }

  // ----- shared row pieces ---------------------------------------------------

  // A transport button: glyph, hover fill, disabled dim. Media actions
  // route through the Media service with feedback off — the hero is the
  // feedback.
  component TransportButton: Rectangle {
    id: button

    property string glyph: ""
    property bool enabled: true
    signal triggered()

    width: service.transportButtonSize
    height: 30
    radius: 6
    color: buttonMouse.containsMouse ? "#1affffff" : "transparent"
    opacity: button.enabled ? 1 : 0.35

    Text {
      anchors.centerIn: parent
      text: button.glyph
      color: service.foreground
      font.family: service.fontFamily
      font.pixelSize: 16
    }

    MouseArea {
      id: buttonMouse

      anchors.fill: parent
      hoverEnabled: true
      cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (button.enabled) button.triggered()
    }
  }

  // The slider both volume rows wear: click or drag sets the level, mute
  // dims it. The fill tracks the pointer directly — the settle animation
  // belongs to the OSD's key steps, not a drag.
  component VolumeBar: Rectangle {
    id: bar

    property real value: 0
    property bool dimmed: false
    signal moved(real volume)

    width: 140
    height: 6
    radius: 3
    color: "#33ffffff"
    opacity: dimmed ? 0.45 : 1

    Rectangle {
      height: parent.height
      radius: 3
      width: parent.width * Math.max(0, Math.min(1, bar.value))
      color: service.accent
    }

    MouseArea {
      id: volumeMouse

      // Taller than the track — a 6px target is too thin to hit.
      anchors.fill: parent
      anchors.topMargin: -12
      anchors.bottomMargin: -12
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      onPressed: function(mouse) {
        bar.moved(Math.max(0, Math.min(1, mouse.x / bar.width)))
      }

      onPositionChanged: function(mouse) {
        if (pressed) bar.moved(Math.max(0, Math.min(1, mouse.x / bar.width)))
      }
    }
  }

  // The media row's position bar: drag scrubs (the readout follows the
  // drag, the player seeks on release), click jumps.
  component PositionBar: Rectangle {
    id: bar

    property double dragFraction: -1
    signal sought(double fraction)

    width: 140
    height: 5
    radius: 2.5
    color: "#33ffffff"

    readonly property double fraction: dragFraction >= 0
      ? dragFraction
      : (service.playerLength() > 0 ? Math.max(0, Math.min(1, service.displayPosition / service.playerLength())) : 0)

    Rectangle {
      height: parent.height
      radius: 2.5
      width: parent.width * bar.fraction
      color: service.accent
    }

    MouseArea {
      id: positionMouse

      anchors.fill: parent
      anchors.topMargin: -12
      anchors.bottomMargin: -12
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor

      function apply(x) {
        bar.dragFraction = Math.max(0, Math.min(1, x / bar.width))
      }

      onPressed: function(mouse) {
        apply(mouse.x)
      }

      onPositionChanged: function(mouse) {
        if (pressed) apply(mouse.x)
      }

      onReleased: {
        if (bar.dragFraction >= 0) bar.sought(bar.dragFraction)
        bar.dragFraction = -1
      }
    }
  }
}
