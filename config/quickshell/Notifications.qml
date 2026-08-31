// M2: the notifications daemon. The NotificationServer claims
// org.freedesktop.Notifications on the session bus — notify-send, libnotify
// apps and Chromium all talk to it — and toasts stack in the top-right
// corner below the bar (one stack per screen).
//
// Omarchy Quattro behaviors kept here, simplified: urgency-based lifetimes
// (critical never expires), hover pauses the countdown, click runs the
// sender's "default" action or focuses its window, do-not-disturb silences
// everything but bare-CLI critical alerts, and the last few notifications
// are kept in memory for a replay (`qs ipc call notifications showHistory`).
// What's deliberately NOT here yet: on-disk persistence of live toasts and
// history (Omarchy mirrors them under ~/.local/state so they survive shell
// restarts — revisit alongside M5's clipboard history).
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import QtQuick

Item {
  id: service

  // Palette shared with Bar.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"
  readonly property color critical: "#ff5555"
  readonly property int barSize: 30

  // ----- tuning ------------------------------------------------------------
  readonly property int maxPopups: 5
  readonly property int historyLimit: 10
  readonly property int lowDuration: 5000
  readonly property int normalDuration: 8000
  readonly property int maxDuration: 30000

  // ----- do-not-disturb ----------------------------------------------------

  // PersistentProperties carries DND across live config reloads; the
  // notifications.json file below carries it across shell restarts.
  PersistentProperties {
    id: persisted

    reloadableId: "granite-notifications"
    property bool doNotDisturb: false
  }

  readonly property alias doNotDisturb: persisted.doNotDisturb

  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/granite/notifications.json"

  FileView {
    id: settingsFile

    path: service.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadSettings(text())
    // First run: the file doesn't exist yet — treat as defaults and let the
    // first toggle write it.
    onLoadFailed: service.loadSettings("")
  }

  Timer {
    id: settingsSaveTimer

    interval: 200
    onTriggered: settingsFile.setText(JSON.stringify({ dnd: persisted.doNotDisturb }) + "\n")
  }

  property bool settingsLoaded: false

  function loadSettings(raw) {
    // FileView can fire onLoaded more than once during startup; the first
    // read is authoritative.
    if (service.settingsLoaded) return
    service.settingsLoaded = true

    var text = String(raw || "").trim()
    if (!text) return
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed.dnd === "boolean")
        persisted.doNotDisturb = parsed.dnd
    } catch (e) {
      console.warn("notifications: settings parse failed:", e)
    }
  }

  function toggleDoNotDisturb() {
    setDoNotDisturb(!persisted.doNotDisturb)
  }

  function setDoNotDisturb(value) {
    persisted.doNotDisturb = !!value
    // The write-through is guarded so a load-time hydration can never
    // clobber the file with the default before it was read.
    if (service.settingsLoaded) settingsSaveTimer.restart()
    // Feedback for the toggle — injected directly, so it shows even though
    // DND was just turned on (the user just acted; hiding the confirmation
    // would look like a dead keybind).
    pushToast({
      originalId: -1,
      app: "granite-shell",
      appIcon: "",
      summary: value ? "Do not disturb on" : "Do not disturb off",
      body: "",
      image: "",
      urgency: NotificationUrgency.Low,
      expireTimeout: 0,
      timestamp: Date.now()
    }, false)
  }

  // ----- the toast stack ---------------------------------------------------

  ListModel { id: popupModel }

  // Live server Notification objects by id, kept OUT of the ListModel: a
  // QObject stored in a model role becomes a dangling C++ pointer when the
  // server destroys the notification (sender close, dismissal), and the
  // next read of that role segfaults (Omarchy's lesson). A JS map only
  // holds a wrapper, which degrades to a catchable error instead.
  property var liveRefs: ({})

  // The notifications that left the screen, oldest first, newest last.
  // In-memory only — see the header note on persistence.
  property var history: []

  // Duration in ms for a toast: critical never expires; senders asking for
  // longer than the per-urgency base get it, capped at maxDuration.
  function durationFor(urgency, expireTimeout) {
    if (urgency === NotificationUrgency.Critical) return 0
    var base = urgency === NotificationUrgency.Low ? lowDuration : normalDuration
    var requested = Number(expireTimeout || 0)
    if (isFinite(requested) && requested > base) base = requested
    return Math.min(maxDuration, base)
  }

  // DND bypass: only bare-CLI critical alerts (system scripts notifying via
  // notify-send) punch through. Chat apps set urgency=critical to force
  // visibility, so critical alone must not be enough.
  function bypassesDnd(notification) {
    return notification.urgency === NotificationUrgency.Critical &&
      String(notification.appName || "") === "notify-send"
  }

  // The card renders a copy, never the server object (see liveRefs).
  function snapshotOf(notification) {
    return {
      originalId: notification.id,
      app: notification.appName || "",
      appIcon: notification.appIcon || "",
      summary: notification.summary || "",
      body: notification.body || "",
      image: notification.image || "",
      urgency: notification.urgency,
      expireTimeout: notification.expireTimeout || 0,
      timestamp: Date.now()
    }
  }

  function handleNotification(notification) {
    // Without tracked = true the server destroys the object as soon as this
    // handler returns, dangling every reference the card holds.
    notification.tracked = true
    var snapshot = snapshotOf(notification)
    liveRefs[snapshot.originalId] = notification
    notification.closed.connect(function() {
      if (service.liveRefs[snapshot.originalId] === notification)
        delete service.liveRefs[snapshot.originalId]
    })

    if (doNotDisturb && !bypassesDnd(notification)) {
      // No toast; "what did I miss while silenced" is what history is for.
      // The transient hint marks popup-only notifications the sender says
      // aren't worth recording.
      if (!notification.transient) remember(snapshot)
      releaseRef(notification, snapshot.originalId)
      return
    }

    remember(snapshot)
    watchForUpdates(notification, snapshot)
    pushToast(snapshot)
  }

  // Drop the reference to a server object. Untracking tells the sender the
  // notification is closed (Chromium then deletes its image files); the
  // closed signal's own map cleanup becomes a guarded no-op.
  function releaseRef(notification, originalId) {
    if (liveRefs[originalId] === notification) delete liveRefs[originalId]
    try {
      notification.tracked = false
    } catch (e) {
      // Object already destroyed by the server — nothing to release.
    }
  }

  // A client updating its notification through replaces_id does not produce
  // a second onNotification — the server writes the new content onto the
  // object we already hold. Copy it back onto the row so the card shows it.
  readonly property var updateSignals: [
    "summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged",
    "imageChanged", "urgencyChanged", "expireTimeoutChanged"
  ]

  function watchForUpdates(notification, snapshot) {
    for (var i = 0; i < updateSignals.length; i++) {
      var signal = notification[updateSignals[i]]
      if (signal && typeof signal.connect === "function")
        signal.connect(function() {
          service.refreshPopup(notification, snapshot.originalId, snapshot.timestamp)
        })
    }
  }

  function refreshPopup(notification, originalId, timestamp) {
    // The id may have been reused by a newer notification, or the popup
    // already left the screen — in both cases there is nothing to refresh.
    if (liveRefs[originalId] !== notification) return

    var updated
    try {
      updated = snapshotOf(notification)
    } catch (e) {
      return  // object destroyed while the signal was in flight
    }
    updated.timestamp = timestamp

    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId || row.timestamp !== timestamp) continue
      for (var key in updated) popupModel.setProperty(i, key, updated[key])
      updateHistory(originalId, timestamp, updated)
      return
    }
  }

  // The history entry should show what the sender last sent, not the first
  // version a later replaces_id superseded.
  function updateHistory(originalId, timestamp, updated) {
    for (var i = 0; i < history.length; i++) {
      var entry = history[i]
      if (entry.originalId !== originalId || entry.timestamp !== timestamp) continue
      history[i] = {
        originalId: originalId,
        app: updated.app,
        appIcon: updated.appIcon,
        summary: updated.summary,
        body: updated.body,
        image: updated.image,
        urgency: updated.urgency,
        timestamp: timestamp
      }
      history = history.slice()  // reassign so future bindings see the change
      return
    }
  }

  // Raw row removal without touching the server: the id now belongs to the
  // notification taking its place, so closing it server-side would close
  // the wrong one. Only called for live ids — synthetic rows share -1.
  function removeRowById(originalId) {
    for (var i = popupModel.count - 1; i >= 0; i--) {
      if (popupModel.get(i).originalId === originalId) popupModel.remove(i)
    }
  }

  function pushToast(entry, enforceLimit) {
    // Qt.callLater avoids QV4 crashes when the toast Repeater is still
    // incubating while the model mutates.
    Qt.callLater(function() {
      if (entry.originalId >= 0) removeRowById(entry.originalId)
      popupModel.insert(0, entry)
      if (enforceLimit !== false)
        while (popupModel.count > maxPopups)
          removePopup(popupModel.count - 1, "expire")
    })
  }

  function dismissPopup(index) {
    removePopup(index, "dismiss")
  }

  function expirePopup(index) {
    removePopup(index, "expire")
  }

  function removePopup(index, reason) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    popupModel.remove(index)

    // Synthetic and replayed rows (originalId < 0) have no server object,
    // and resolving one by id could hit an unrelated live notification.
    if (entry.originalId < 0) return

    var ref = liveRefs[entry.originalId]
    if (!ref) return
    try {
      if (reason === "expire") ref.expire()
      else ref.dismiss()
    } catch (e) {
      // Object already torn down by the server — nothing to close.
    }
    releaseRef(ref, entry.originalId)
  }

  function clearPopups() {
    while (popupModel.count > 0) dismissPopup(0)
  }

  // ----- clicking a toast --------------------------------------------------

  // Left click: run the sender's "default" action if it registered one;
  // otherwise focus its window (chat apps expect click-to-jump and rarely
  // register a default action).
  function invokeDefault(index) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)

    var invoked = false
    var ref = entry.originalId >= 0 ? liveRefs[entry.originalId] : null
    if (ref) {
      try {
        var actions = ref.actions
        for (var i = 0; i < actions.length; i++) {
          if (actions[i].identifier === "default") {
            actions[i].invoke()
            invoked = true
            break
          }
        }
      } catch (e) {
        console.warn("notifications: invoking action failed:", e)
      }
    }
    if (!invoked) focusApp(entry.app)
    dismissPopup(index)
  }

  // Focus a window whose Hyprland class matches the sender, matching either
  // direction case-insensitively: apps notify as "Slack" but their window
  // class is "slack", and terminals notify as the terminal while the class
  // is the shell.
  function focusApp(appName) {
    var needle = String(appName || "").toLowerCase()
    if (!needle) return

    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++) {
      var toplevel = values[i]
      var klass = String(((toplevel.lastIpcObject || {})["class"]) || "").toLowerCase()
      if (!klass) continue
      if (klass === needle || klass.indexOf(needle) !== -1 || needle.indexOf(klass) !== -1) {
        Hyprland.dispatch("focuswindow address:" + toplevel.address)
        return
      }
    }
  }

  // ----- history -----------------------------------------------------------

  function remember(entry) {
    // originalId + timestamp identify the entry for replaces_id updates;
    // the replay deliberately drops both (its rows are synthetic).
    history = history.concat([{
      originalId: entry.originalId,
      app: entry.app,
      appIcon: entry.appIcon,
      summary: entry.summary,
      body: entry.body,
      image: entry.image,
      urgency: entry.urgency,
      timestamp: entry.timestamp
    }]).slice(-historyLimit)
  }

  // Re-show the remembered notifications as toasts, newest on top. Replay
  // rows carry originalId -1 so dismissal and clicks never resolve to a
  // live server object: their notification died with the sender long ago,
  // and the id may since belong to an unrelated one. The replay's lifetime
  // comes from the urgency alone — a critical original must not stick on
  // screen forever just because history was opened.
  function showHistory() {
    if (history.length === 0) {
      pushToast({
        originalId: -1,
        app: "granite-shell",
        appIcon: "",
        summary: "No recent notifications",
        body: "",
        image: "",
        urgency: NotificationUrgency.Low,
        expireTimeout: 0,
        timestamp: Date.now()
      }, false)
      return "ok"
    }

    clearPopups()
    // Oldest first: each insert lands at the top, so the newest ends up on
    // top of the stack like a fresh arrival.
    for (var i = 0; i < history.length; i++) {
      var entry = history[i]
      pushToast({
        originalId: -1,
        app: entry.app,
        appIcon: entry.appIcon,
        summary: entry.summary,
        body: entry.body,
        image: entry.image,
        urgency: entry.urgency,
        expireTimeout: 0,
        timestamp: entry.timestamp
      }, false)
    }
    return "ok"
  }

  function clearHistory() {
    history = []
    return "ok"
  }

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call notifications toggleDnd`.

  IpcHandler {
    target: "notifications"

    function dndState(): string {
      return service.doNotDisturb ? "on" : "off"
    }

    function toggleDnd(): string {
      service.toggleDoNotDisturb()
      return dndState()
    }

    function showHistory(): string {
      return service.showHistory()
    }

    function clearHistory(): string {
      return service.clearHistory()
    }

    function dismissAll(): string {
      service.clearPopups()
      return "ok"
    }

    // Dismiss the most recent toast.
    function dismissLast(): string {
      if (popupModel.count === 0) return "none"
      service.dismissPopup(0)
      return "ok"
    }

    function ping(): string {
      return "ok"
    }
  }

  // ----- the server --------------------------------------------------------

  NotificationServer {
    id: server

    // Keep the bus name and tracked notifications across live config
    // reloads (there is no on-disk restore to repopulate from, unlike
    // Omarchy's).
    keepOnReload: true
    actionsSupported: true
    imageSupported: true
    // Bodies render as plain text: markup is not advertised, so
    // well-behaved senders strip theirs, and hostile <img> markup in body
    // text can never reach a StyledText renderer.
    bodyMarkupSupported: false

    onNotification: function(notification) {
      service.handleNotification(notification)
    }
  }

  // Make sure the state directory exists before the first settings save.
  // FileView does not create parent directories.
  Process {
    id: ensureStateDir

    command: ["mkdir", "-p", service.statePath.substring(0, service.statePath.lastIndexOf("/"))]
  }

  Component.onCompleted: ensureStateDir.running = true

  // ----- toast UI ----------------------------------------------------------
  //
  // One full-screen passive overlay per screen, like Omarchy's: the fixed
  // surface size means adding or removing a toast never resizes the Wayland
  // buffer (which briefly stretches stale cards), and the mask keeps
  // everything but the toast column click-through. Overlay layer, no
  // keyboard focus — popups never steal input from the focused app.

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: toastWindow

      required property var modelData

      screen: modelData
      visible: popupModel.count > 0

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.namespace: "mike-notifications"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      mask: Region { item: toastColumn }

      Column {
        id: toastColumn

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: service.barSize + 8
        anchors.rightMargin: 8
        spacing: 8

        Repeater {
          model: popupModel

          // The delegate is a slot Item that owns the countdown state; the
          // visuals live in NotificationCard, which must not redeclare the
          // model's required properties.
          delegate: Item {
            id: slot

            required property int index
            required property int originalId
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property int urgency
            required property real expireTimeout
            required property real timestamp

            width: card.width
            height: card.height

            readonly property real lifetime: service.durationFor(slot.urgency, slot.expireTimeout)
            property real remaining: 1.0

            // A sender replacing the content deserves a fresh look, so the
            // countdown starts over instead of running out the clock the
            // superseded text was most of the way through.
            onSummaryChanged: slot.remaining = 1.0
            onBodyChanged: slot.remaining = 1.0

            // Hover pauses the countdown.
            Timer {
              interval: 50
              repeat: true
              running: slot.lifetime > 0 && !card.hovered
              onTriggered: {
                if (slot.lifetime <= 0) return
                slot.remaining -= 50.0 / slot.lifetime
                if (slot.remaining <= 0) {
                  slot.remaining = 0
                  service.expirePopup(slot.index)
                }
              }
            }

            NotificationCard {
              id: card

              fontFamily: service.fontFamily
              foreground: service.foreground
              accent: service.accent
              critical: service.critical
              app: slot.app
              appIcon: slot.appIcon
              summary: slot.summary
              body: slot.body
              image: slot.image
              urgency: slot.urgency
              remainingLifetime: slot.remaining

              onCloseRequested: service.dismissPopup(slot.index)
              onCardClicked: service.invokeDefault(slot.index)
            }
          }
        }
      }
    }
  }
}
