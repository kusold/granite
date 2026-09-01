// M6: the screensaver. Omarchy's runs ASCII branding through ttfx in a
// fullscreen terminal per monitor (any input exits); granite keeps the
// shape — one surface per screen, idle-triggered ahead of the lock,
// dismissed by any activity — but draws it in-process: a slow crossfade
// slideshow over the background library with a large clock.
//
// Idle wiring: its own IdleMonitor (ext-idle-notify, so wayland idle
// inhibitors are respected) fires at 150s — Omarchy Quattro's default,
// ahead of Idle.qml's 300s lock and 1800s suspend. Any activity ends
// idle, which both dismisses the screensaver and resets the lock timer,
// so dismissing it can never leave a lock looming (Omarchy needs
// explicit cancellation logic for their terminal windows; the shared
// idle clock gives granite that for free). Locking hides it — the
// ext-session-lock surface takes the outputs anyway.
//
// On demand: SUPER+Escape and the session menu's Screensaver row (both via
// `qs ipc call screensaver start`).
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Item {
  id: service

  // Wired to the shell's Background and Lock instances by shell.qml.
  property var background: null
  property var lock: null

  // Palette shared with Bar.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"

  // ----- tuning ------------------------------------------------------------

  readonly property int screensaverTimeoutSeconds: 150
  readonly property int slideSeconds: 15
  readonly property int crossfadeMs: 900

  // ----- state -------------------------------------------------------------

  property bool opened: false
  property int slideIndex: 0
  property string displayedSlide: ""
  property string outgoingSlide: ""
  property string incomingSlide: ""

  // Any pointer motion inside this window after show() dismisses; the
  // grace keeps the map-under-cursor enter event from doing it instantly.
  property double shownAt: 0

  readonly property var slides: background !== null ? background.backgrounds : []

  // ----- idle ---------------------------------------------------------------

  IdleMonitor {
    timeout: service.screensaverTimeoutSeconds
    respectInhibitors: true
    // While locked the lock surface owns the outputs; there is nothing
    // to save them from.
    enabled: service.lock === null || !service.lock.locked

    onIsIdleChanged: {
      if (isIdle && enabled) service.show()
      else service.hide()
    }
  }

  Connections {
    target: service.lock

    function onLockedChanged() {
      if (service.lock && service.lock.locked) service.hide()
    }
  }

  // ----- slideshow ----------------------------------------------------------

  function slideAt(index) {
    if (slides.length === 0) return ""
    var wrapped = ((index % slides.length) + slides.length) % slides.length
    return slides[wrapped]
  }

  function show() {
    if (opened) return "already"
    shownAt = Date.now()
    // A random start, so two idle spells don't open on the same slide;
    // the first frame is instant, crossfades own everything after it.
    // (A fade mid-flight from a previous showing fizzles once the state
    // empties — fadeSlide lives in the per-screen delegate below.)
    slideIndex = Math.floor(Math.random() * Math.max(1, slides.length))
    outgoingSlide = ""
    incomingSlide = ""
    displayedSlide = slideAt(slideIndex)
    opened = true
    return "started"
  }

  function hide() {
    if (!opened) return "already"
    opened = false
    outgoingSlide = ""
    incomingSlide = ""
    return "stopped"
  }

  function nextSlide() {
    if (slides.length === 0) return
    slideIndex += 1
    var path = slideAt(slideIndex)
    if (path.length === 0 || path === displayedSlide) return
    outgoingSlide = displayedSlide
    incomingSlide = path
  }

  function cancelSlideTransition() {
    incomingSlide = ""
    outgoingSlide = ""
  }

  Timer {
    interval: service.slideSeconds * 1000
    repeat: true
    running: service.opened
    onTriggered: service.nextSlide()
  }

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call screensaver start`.

  IpcHandler {
    target: "screensaver"

    function start(): string {
      return service.show()
    }

    function stop(): string {
      return service.hide()
    }

    function status(): string {
      return JSON.stringify({
        opened: service.opened,
        slides: service.slides.length,
        slide: service.slideAt(service.slideIndex),
        timeoutSeconds: service.screensaverTimeoutSeconds,
        slideSeconds: service.slideSeconds
      })
    }

    function ping(): string {
      return "ok"
    }
  }

  // ----- the surfaces --------------------------------------------------------
  //
  // One overlay per screen at Overlay layer — above the bar, below the
  // ext-session-lock surface — with the same three-frame crossfade as
  // Background.qml. Input dismisses immediately; the compositor's idle
  // clock resetting (which is what any real input does) dismisses the
  // rest of the way and re-arms the lock timer.

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: saverPanel

      required property var modelData

      screen: modelData
      visible: service.opened

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      color: "#101014"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "mike-screensaver"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      onVisibleChanged: if (visible) Qt.callLater(saverRoot.forceActiveFocus)

      Item {
        id: saverRoot

        anchors.fill: parent

        // Any key resumes. (The idle clock resets on the same press, so
        // this is as much feedback as it is dismissal.)
        Keys.onPressed: function(event) {
          service.hide()
          event.accepted = true
        }

        Image {
          id: settledSlide

          anchors.fill: parent
          source: service.displayedSlide.length > 0 ? "file://" + service.displayedSlide : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: true
          onStatusChanged: {
            if (status !== Image.Ready) return
            if (service.incomingSlide !== "" && !fadeSlide.running) {
              service.incomingSlide = ""
              service.outgoingSlide = ""
            } else if (service.incomingSlide === "" && service.outgoingSlide !== "") {
              service.outgoingSlide = ""
            }
          }
        }

        Image {
          id: outgoingSlideFrame

          anchors.fill: parent
          visible: service.outgoingSlide.length > 0
          source: service.outgoingSlide.length > 0 ? "file://" + service.outgoingSlide : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
        }

        Image {
          id: incomingSlideFrame

          anchors.fill: parent
          opacity: 0
          source: service.incomingSlide.length > 0 ? "file://" + service.incomingSlide : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          smooth: true
          onStatusChanged: {
            if (status === Image.Ready && service.incomingSlide !== "")
              fadeSlide.restart()
            else if (status === Image.Error)
              service.cancelSlideTransition()
          }
        }

        NumberAnimation {
          id: fadeSlide

          target: incomingSlideFrame
          property: "opacity"
          from: 0
          to: 1
          duration: service.crossfadeMs
          easing.type: Easing.InOutQuad
          // Only a natural finish settles; the faded-in frame stays up as
          // a cover until the settled frame reports the new image Ready,
          // like Background.qml's handshake.
          onFinished: {
            if (service.incomingSlide !== "" && incomingSlideFrame.status === Image.Ready)
              service.displayedSlide = service.incomingSlide
          }
        }

        // Dim the slideshow enough for the clock to carry, without
        // hiding the images.
        Rectangle {
          anchors.fill: parent
          color: "#8c000000"
        }

        SystemClock {
          id: saverClock

          precision: SystemClock.Minutes
        }

        Column {
          anchors.centerIn: parent
          spacing: 10

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(saverClock.date, "HH:mm")
            color: service.foreground
            font.family: service.fontFamily
            font.pixelSize: 88
            font.weight: Font.Light
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(saverClock.date, "dddd, MMMM d")
            color: service.foreground
            opacity: 0.7
            font.family: service.fontFamily
            font.pixelSize: 20
          }
        }

        Text {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 24
          anchors.horizontalCenter: parent.horizontalCenter
          text: "move or press any key to resume"
          color: service.foreground
          opacity: 0.35
          font.family: service.fontFamily
          font.pixelSize: 11
        }

        // Pointer dismissal, with the show()-time grace so the surface
        // mapping under a resting cursor doesn't dismiss itself.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.AllButtons
          onPressed: service.hide()
          onPositionChanged: if (Date.now() - service.shownAt > 400) service.hide()
        }
      }
    }
  }
}
