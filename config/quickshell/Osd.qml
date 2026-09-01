// M7: the on-screen display. The media keys stop being silent: volume,
// brightness, and media popups surface over the focused monitor's bottom
// edge for a beat, like Omarchy Quattro's OSD.
//
// The keys are bound in hyprland.lua to `qs ipc call osd …` (and the
// media keys to `qs ipc call media …`) and the shell does the work
// behind them: volume moves through Quickshell's pipewire service (the
// PwObjectTracker keeps the default sink/source bound, and the watch on
// their audio properties means a headset's volume wheel pops the same
// popup the keyboard does), brightness goes through brightnessctl —
// Quickshell has no backlight service, and only class "backlight"
// devices count, so the wifi LED brightnessctl would otherwise pick on
// desktop hosts is left alone — and media acts through the MPRIS service
// (Media.qml) that M8 grew out of this file: the media keys call its IPC,
// it runs the player ladder and calls back here for the popup. The audio
// panel holds the volume popup while it is open — its own sliders are
// the display then.
//
// Omarchy behaviors kept here, simplified: the popup geometry (bottom
// center card — icon, progress bar, readout — or icon + message), the
// progress bar's settle animation, and a generic `show` IPC for scripts
// (their omarchy-osd CLI's payload). Deliberately NOT here vs Omarchy:
// that CLI wrapper (qs ipc is granite's equivalent), keyboard-backlight
// and DDC display brightness, and the mic-mute LED. The player picking
// and next/previous track waiting live in Media.qml since M8.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import QtQuick

Item {
  id: service

  // Wired to the shell's Media instance by shell.qml: media feedback is
  // this OSD's popup, media state is the Media service's business.
  property var media: null

  // Palette shared with Bar.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"

  // ----- tuning ------------------------------------------------------------

  readonly property int hideDelayMs: 1200
  readonly property int volumeStepPercent: 5
  readonly property int brightnessStepPercent: 5
  readonly property int barWidth: 140
  readonly property int cardHeight: 52
  readonly property int cardPad: 16
  readonly property int cardSpacing: 16
  readonly property int cardBottomMargin: 64
  readonly property int messageMaxWidth: 320

  // ----- OSD state ----------------------------------------------------------
  //
  // One popup at a time: a new show replaces whatever is up and restarts
  // the hide timer, so key repeats refresh the same popup instead of
  // stacking them.

  property bool opened: false
  property string iconKey: ""
  property string message: ""
  property int value: 0
  property bool hasProgress: false

  readonly property string icon: iconGlyph(iconKey, value)

  Timer {
    id: hideTimer

    interval: service.hideDelayMs
    onTriggered: service.opened = false
  }

  function present(key, messageText, percent, progress, duration) {
    iconKey = key
    message = messageText
    value = percent
    hasProgress = progress
    opened = true
    hideTimer.interval = duration > 0 ? duration : service.hideDelayMs
    hideTimer.restart()
  }

  function showProgress(key, percent) {
    present(key, "", Math.max(0, Math.min(100, Math.round(percent))), true, 0)
  }

  function showMessage(key, messageText, duration) {
    present(key, messageText, 0, false, duration || 0)
  }

  // Nerd Font glyphs, shared with SessionMenu.qml's icon set. "volume"
  // picks its glyph from the level; the generic show() IPC passes unknown
  // keys through as literal text.
  readonly property var glyphs: ({
    "volume-muted": "",
    "volume-low": "",
    "volume-medium": "",
    "volume-high": "",
    "mic": "󰍬",
    "mic-muted": "󰍭",
    "brightness": "󰍹",
    "media": "󰝚",
    "media-play": "󰐊",
    "media-pause": "󰏤",
    "media-next": "󰒭",
    "media-previous": "󰒮"
  })

  function iconGlyph(key, percent) {
    if (key === "volume") {
      if (percent <= 0) return glyphs["volume-muted"]
      if (percent <= 33) return glyphs["volume-low"]
      if (percent <= 66) return glyphs["volume-medium"]
      return glyphs["volume-high"]
    }
    if (glyphs[key] !== undefined) return glyphs[key]
    return key
  }

  // ----- volume -------------------------------------------------------------
  //
  // Writes go through pipewire directly, so the popup state and the real
  // sink state can't disagree. Volume above 100% (boost set elsewhere)
  // reads as-is, but the keys cap at 100 like pamixer did.

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource

  // The default nodes' audio interfaces only exist while something holds
  // a reference — track both so volume/mute reads, writes, and the
  // property watches below work.
  PwObjectTracker {
    objects: {
      var tracked = []
      if (service.sink !== null) tracked.push(service.sink)
      if (service.source !== null) tracked.push(service.source)
      return tracked
    }
  }

  // External volume changes (headset wheels, pavucontrol) pop the same
  // popup the keys do. Armed a beat after startup so the initial pipewire
  // bind doesn't pop one at login; a sink switch mid-session still gets
  // its immediate first-change popup, which is useful feedback. M8's
  // audio panel holds the popup while it is open — its own sliders are
  // the display then.
  property bool volumeWatchArmed: false
  property bool volumePopupHeld: false

  Timer {
    interval: 3000
    running: true
    onTriggered: service.volumeWatchArmed = true
  }

  Connections {
    target: service.sink !== null ? service.sink.audio : null

    function onVolumesChanged() {
      if (service.volumeWatchArmed && !service.volumePopupHeld) service.showVolume()
    }

    function onMutedChanged() {
      if (service.volumeWatchArmed && !service.volumePopupHeld) service.showVolume()
    }
  }

  function sinkPercent() {
    if (service.sink === null || service.sink.audio === null) return -1
    if (service.sink.audio.volumes.length === 0) return -1
    return Math.round(service.sink.audio.volume * 100)
  }

  function stepVolume(step) {
    var current = sinkPercent()
    if (current < 0) return "unavailable"
    // Adjusting unmutes, like Omarchy's wrapper — a volume key that only
    // changes the number while muted reads dead.
    service.sink.audio.muted = false
    service.sink.audio.volume = Math.max(0, Math.min(100, current + step)) / 100
    return "ok"
  }

  function volumeUp() {
    return stepVolume(volumeStepPercent)
  }

  function volumeDown() {
    return stepVolume(-volumeStepPercent)
  }

  function volumeMute() {
    if (service.sink === null || service.sink.audio === null) return "unavailable"
    service.sink.audio.muted = !service.sink.audio.muted
    return "ok"
  }

  function showVolume() {
    var percent = sinkPercent()
    if (percent < 0) return
    showProgress(service.sink.audio.muted ? "volume-muted" : "volume", percent)
  }

  function micMute() {
    if (service.source === null || service.source.audio === null) return "unavailable"
    var muted = !service.source.audio.muted
    service.source.audio.muted = muted
    showMessage(muted ? "mic-muted" : "mic", muted ? "Microphone muted" : "Microphone on")
    return "ok"
  }

  // ----- brightness ---------------------------------------------------------
  //
  // One brightnessctl round trip per step: pick the first class
  // "backlight" device, step to an absolute target (1% steps near the
  // bottom, like Omarchy — raw 5% steps round to nothing on dim panels),
  // then report the resulting percent. Repeats that arrive while a trip
  // is in flight land on the next turn with the latest step (the
  // clipboard's process-retry pattern); the wifi-LED-only hosts print
  // nothing and no popup appears.

  readonly property string brightnessScript:
    "line=$(brightnessctl -l -m 2>/dev/null | awk -F, '$2 == \"backlight\" { print; exit }')\n" +
    "[[ -n $line ]] || exit 0\n" +
    "dev=${line%%,*}\n" +
    "cur=$(printf '%s\\n' \"$line\" | cut -d, -f3)\n" +
    "max=$(printf '%s\\n' \"$line\" | cut -d, -f5)\n" +
    "(( max > 0 )) || exit 0\n" +
    "step=$2\n" +
    "percent=$(( cur * 100 / max ))\n" +
    "if (( percent <= step )); then delta=1; else delta=step; fi\n" +
    "case $1 in\n" +
    "  +*) target=$(( percent + delta )) ;;\n" +
    "  *) target=$(( percent - delta )) ;;\n" +
    "esac\n" +
    "(( target > 100 )) && target=100\n" +
    "(( target < 1 )) && target=1\n" +
    "brightnessctl -d \"$dev\" set \"${target}%\" >/dev/null 2>&1\n" +
    "brightnessctl -d \"$dev\" -m 2>/dev/null | cut -d, -f3 | awk -v m=\"$max\" '{ printf \"%.0f\\n\", $1 * 100 / m }'"

  property int pendingBrightnessStep: 0

  function brightnessUp() {
    return stepBrightness(brightnessStepPercent)
  }

  function brightnessDown() {
    return stepBrightness(-brightnessStepPercent)
  }

  function stepBrightness(step) {
    pendingBrightnessStep = step
    if (!brightnessProc.running) runBrightnessStep()
    return "ok"
  }

  function runBrightnessStep() {
    if (brightnessProc.running || pendingBrightnessStep === 0) return
    var step = pendingBrightnessStep
    pendingBrightnessStep = 0
    brightnessProc.command = ["bash", "-c", brightnessScript, "--",
      (step > 0 ? "+" : "") + String(step), String(brightnessStepPercent)]
    brightnessProc.running = true
  }

  Process {
    id: brightnessProc

    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var percent = parseInt(String(text || "").trim(), 10)
        if (!isNaN(percent)) service.showProgress("brightness", percent)
        // Chained here rather than in onExited so the collector has fully
        // drained before the next trip reuses the process.
        service.runBrightnessStep()
      }
    }
  }

  // ----- generic show -------------------------------------------------------
  //
  // For scripts: `qs ipc call osd show '{"icon":"mic","message":"…"}'` or
  // with a value for a progress popup. Omarchy's omarchy-osd payload,
  // minus their max/progressText variants (percent is 0-100 here).

  function showPayload(payloadJson) {
    var payload
    try {
      payload = JSON.parse(payloadJson || "{}")
    } catch (e) {
      return "parse-error"
    }
    var raw = payload.value === undefined ? "" : String(payload.value)
    var parsed = parseInt(raw, 10)
    var progress = raw !== "" && !isNaN(parsed) && String(payload.message || "") === ""
    var duration = parseInt(payload.duration, 10)
    present(String(payload.icon || ""), String(payload.message || ""),
      progress ? Math.max(0, Math.min(100, parsed)) : 0, progress,
      isNaN(duration) ? 0 : duration)
    return "ok"
  }

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call osd volumeUp` etc.

  IpcHandler {
    target: "osd"

    function volumeUp(): string {
      return service.volumeUp()
    }

    function volumeDown(): string {
      return service.volumeDown()
    }

    function volumeMute(): string {
      return service.volumeMute()
    }

    function micMute(): string {
      return service.micMute()
    }

    function brightnessUp(): string {
      return service.brightnessUp()
    }

    function brightnessDown(): string {
      return service.brightnessDown()
    }

    function show(payloadJson: string): string {
      return service.showPayload(payloadJson)
    }

    function close(): string {
      service.opened = false
      return "ok"
    }

    function status(): string {
      var percent = service.sinkPercent()
      return JSON.stringify({
        opened: service.opened,
        iconKey: service.iconKey,
        message: service.message,
        value: service.value,
        hasProgress: service.hasProgress,
        sinkPercent: percent,
        sinkMuted: percent >= 0 ? service.sink.audio.muted : false,
        players: service.media !== null ? service.media.players.length : 0,
        activePlayer: service.media !== null ? service.media.mediaMessage(service.media.activePlayer, "") : ""
      })
    }

    function ping(): string {
      return "ok"
    }
  }

  // ----- the popup ----------------------------------------------------------
  //
  // A transparent full-screen layer on the focused monitor (the launcher
  // recipe) holding a bottom-center card. Empty input region, no keyboard
  // focus, Overlay layer above the bar: the OSD never takes input and
  // never outstays its timer.

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
    WlrLayershell.namespace: "mike-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region {}

    Rectangle {
      id: card

      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: service.cardBottomMargin

      height: service.cardHeight
      width: content.implicitWidth + 2 * service.cardPad
      radius: 8
      color: "#f0101014"
      border.width: 1
      border.color: "#26ffffff"

      Row {
        id: content

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: service.cardPad
        spacing: service.cardSpacing

        // Fixed icon column: the monospace cells keep the bar and readout
        // anchored as the glyph changes with the level.
        Text {
          height: parent.height
          width: 26
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: service.icon
          color: service.foreground
          font.family: service.fontFamily
          font.pixelSize: 22
        }

        Rectangle {
          visible: service.hasProgress
          width: service.barWidth
          height: 6
          radius: 3
          y: (parent.height - height) / 2
          color: "#33ffffff"

          Rectangle {
            height: parent.height
            radius: 3
            width: parent.width * Math.min(1, service.value / 100)
            color: service.accent

            // Repeated presses glide to the new level (Omarchy's settle).
            Behavior on width {
              NumberAnimation {
                duration: 140
                easing.type: Easing.OutCubic
              }
            }
          }
        }

        // Fixed-width, right-aligned: the digits don't jitter between 9%
        // and 100%.
        Text {
          visible: service.hasProgress
          height: parent.height
          width: 44
          horizontalAlignment: Text.AlignRight
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: service.value + "%"
          color: service.foreground
          font.family: service.fontFamily
          font.pixelSize: 13
        }

        Text {
          visible: !service.hasProgress
          height: parent.height
          verticalAlignment: Text.AlignVCenter
          textFormat: Text.PlainText
          text: service.message
          color: service.foreground
          font.family: service.fontFamily
          font.pixelSize: 13
          elide: Text.ElideRight
          width: Math.min(implicitWidth, service.messageMaxWidth)
        }
      }
    }
  }
}
