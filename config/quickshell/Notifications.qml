// M2: the notifications daemon. The NotificationServer claims
// org.freedesktop.Notifications on the session bus — notify-send, libnotify
// apps and Chromium all talk to it — and toasts stack in the top-right
// corner below the bar (one stack per screen).
//
// Omarchy Quattro behaviors kept here, simplified: urgency-based lifetimes
// (critical never expires), hover pauses the countdown, click runs the
// sender's "default" action or focuses its window, do-not-disturb silences
// everything but bare-CLI critical alerts, and both live toasts and their
// history persist under ~/.local/state/granite/notifications/ so they
// survive shell restarts — `qs ipc call notifications showHistory` replays
// the history directory (NotificationFiles.js owns that file format).
// Still deliberately NOT here vs Omarchy: their glyph/exec-argv hints
// (omarchy-notification-send specifics) and body-markup sanitization.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import QtQuick

import "NotificationFiles.js" as NotificationFiles

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

  // One file per on-screen popup, so live toasts survive shell restarts.
  // A file exists exactly as long as its popup is showing: written when the
  // toast appears, moved into historyDir when it expires, is dismissed, or
  // is acted upon. This directory is also the restore source on startup.
  readonly property string popupStateDir: Quickshell.env("HOME") + "/.local/state/granite/notifications/"
  // The notifications that already left the screen, one file each, trimmed
  // to the newest historyLimit. This directory IS the history: `showHistory`
  // replays exactly what has been moved in here.
  readonly property string historyDir: popupStateDir + "history/"
  // Copies of the images persisted entries reference — the sender's
  // originals don't outlive the notification (see NotificationFiles.js).
  // Each copy lives and dies with the JSON file whose stem it carries.
  readonly property string imagesDir: popupStateDir + "images/"

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
    return NotificationFiles.snapshotOf(notification, Date.now())
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
      // aren't worth recording. writeSilenced holds the notification
      // tracked until the history file (and its image copies) is on disk.
      if (!notification.transient) writeSilenced(notification, snapshot)
      else releaseRef(notification, snapshot.originalId)
      return
    }

    persistPopupFile(snapshot)
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
      updated = NotificationFiles.replacementSnapshot(notification, originalId, timestamp)
    } catch (e) {
      return  // object destroyed while the signal was in flight
    }

    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId || row.timestamp !== timestamp) continue
      if (!NotificationFiles.popupRowChanged(row, updated)) return
      for (var key in updated) popupModel.setProperty(i, key, updated[key])
      // The file name is the timestamp and id this popup was persisted
      // under, so the rewrite lands on the same file: a restart restores
      // the version last shown, and so does the copy that ends up in
      // history (the sender's last words, not the superseded first draft).
      persistPopupFile(updated)
      return
    }
  }

  // Raw row removal without touching the server: the id now belongs to the
  // notification taking its place, so closing it server-side would close
  // the wrong one. Only called for live ids — synthetic rows share -1.
  //
  // The superseded row's file is deleted rather than archived: the row
  // taking its place archives itself when it goes, and history would
  // otherwise hold two entries for what the sender means as one
  // notification. keepFileName is the replacement's own file: a
  // same-millisecond replacement shares the replaced row's filename, and
  // the new write is already queued — deleting that path here would erase
  // the replacement's only file. Restored rows are skipped — their
  // old-generation id matching here is a coincidence, and removing one
  // would silently kill a restored critical alert on an unrelated ping.
  function removeRowById(originalId, keepFileName) {
    for (var i = popupModel.count - 1; i >= 0; i--) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId) continue
      if (isRestoredRow(row)) continue
      if (NotificationFiles.popupFileName(row) !== keepFileName) deletePopupFileFor(row)
      popupModel.remove(i)
    }
  }

  function pushToast(entry, enforceLimit) {
    // Qt.callLater avoids QV4 crashes when the toast Repeater is still
    // incubating while the model mutates.
    Qt.callLater(function() {
      if (entry.originalId >= 0) removeRowById(entry.originalId, NotificationFiles.popupFileName(entry))
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
    var restored = isRestoredRow(entry)

    // The popup is leaving the screen — for any reason — so its file must
    // not survive to the next shell restart. It becomes the newest history
    // entry instead. Rows that never had a file (a history replay, the
    // empty-history placeholder, the DND feedback toast) archive to
    // nothing, which the move tolerates.
    if (entry.originalId >= 0) {
      archivePopupFileFor(entry)
      if (restored) delete restoredPopups[NotificationFiles.popupFileName(entry)]
    }
    popupModel.remove(index)

    // Synthetic, replayed and restored rows have no live server object —
    // a restored row's old-generation id may meanwhile belong to a fresh
    // notification, and resolving it by id would close the wrong one.
    if (restored || entry.originalId < 0) return

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
    // Restored rows have no live actions, and looking up liveRefs by their
    // old-generation id could fire an unrelated fresh notification's action.
    var ref = entry.originalId >= 0 && !isRestoredRow(entry) ? liveRefs[entry.originalId] : null
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
        // Hyprland >= 0.55 with a Lua config wants a dispatcher OBJECT
        // (hl.dsp.*) on the request socket, not a "focuswindow addr" string.
        Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + toplevel.address + "\" })")
        return
      }
    }
  }

  // ----- file persistence -------------------------------------------------
  //
  // Mirror every on-screen popup to its own file under popupStateDir so
  // toasts survive shell restarts. Writes, moves and deletes go through
  // one serialized queue: a burst of replaces_id updates must not race a
  // single reused Process, and ordering guarantees a delete issued after
  // a write wins.

  // Popups restored from a previous shell process, keyed by their file
  // name (timestamp-originalId) since ids alone repeat across server
  // generations. The replaces_id handling and liveRefs lookups must not
  // match these rows against fresh notifications.
  property var restoredPopups: ({})

  // A restored row carries an id from the previous server generation, and
  // the new server hands out ids from 1 again — so a fresh notification
  // with the same originalId is a coincidence, not the same notification.
  // The timestamp (via the file name) disambiguates: it travels with the
  // row through every model and file round-trip.
  function isRestoredRow(row) {
    return !!row && !!restoredPopups[NotificationFiles.popupFileName(row)]
  }

  // Entries are either { command, done } for a file job or { read: true }
  // for a replay's directory read. Queueing the read rather than running it
  // beside the queue is what makes it a barrier: it takes its place in line,
  // so the history it sees is the one that existed when the replay was
  // asked for. Everything queued after it — a clear, an archive, a silenced
  // write — waits for it, and no amount of later traffic can push it back.
  property var popupFileQueue: []

  // Done callback of the job popupFileProc is currently running.
  property var runningPopupFileJobDone: null

  function enqueuePopupFileJob(command, done) {
    popupFileQueue = popupFileQueue.concat([{ command: command, done: done || null }])
    runNextPopupFileJob()
  }

  function enqueueHistoryRead() {
    popupFileQueue = popupFileQueue.concat([{ read: true }])
    runNextPopupFileJob()
  }

  function runNextPopupFileJob() {
    if (readHistoryProc.running || popupFileProc.running) return
    if (popupFileQueue.length === 0) return

    var job = popupFileQueue[0]
    popupFileQueue = popupFileQueue.slice(1)

    if (job.read) {
      startHistoryRead()
      return
    }

    popupFileProc.command = job.command
    service.runningPopupFileJobDone = job.done || null
    popupFileProc.running = true
  }

  Process {
    id: popupFileProc

    running: false
    onExited: {
      var done = service.runningPopupFileJobDone
      service.runningPopupFileJobDone = null
      if (done) {
        try {
          done()
        } catch (e) {
          console.warn("notifications: file job callback failed:", e)
        }
      }
      service.runNextPopupFileJob()
    }
  }

  // Consumes the remaining args as from/to pairs. Bounded read into a temp
  // file, validated, then renamed into place: the source path is
  // sender-controlled and may grow, block, or become a FIFO mid-copy, and
  // must neither hang the serialized queue nor fill the state dir.
  readonly property string copyImagesScript:
    "while (( $# >= 2 )); do\n" +
    "  if [[ -f $1 ]] && timeout 5 head -c 5242881 -- \"$1\" > \"$2.tmp\" 2>/dev/null &&\n" +
    "     (( $(stat -c%s -- \"$2.tmp\") <= 5242880 )); then mv -f -- \"$2.tmp\" \"$2\"; else rm -f -- \"$2.tmp\"; fi\n" +
    "  shift 2\n" +
    "done\n"

  function persistPopupFile(snapshot) {
    // The JSON travels as an argument, not through shell interpolation, so
    // summaries/bodies with quotes or backticks can't break the command. The
    // mkdir guards notifications that arrive before ensureStateDir has run.
    // Copies run before the JSON referencing them, while the source exists.
    var persistable = NotificationFiles.persistablePopup(snapshot, imagesDir)
    var command = ["bash", "-c",
      "mkdir -p \"$1\" \"$2\" || exit 0\n" +
      "dir=\"$1\" json=\"$3\" name=\"$4\"\n" +
      "shift 4\n" +
      copyImagesScript +
      "printf '%s\\n' \"$json\" > \"$dir/$name\"", "--",
      popupStateDir,
      imagesDir,
      NotificationFiles.serializePopup(persistable.entry),
      NotificationFiles.popupFileName(snapshot)]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueuePopupFileJob(command)
  }

  function deletePopupFileFor(row) {
    if (!row) return
    // History replays and the "no recent notifications" placeholder never
    // had a file — rm -f on the computed paths is a harmless no-op there.
    enqueuePopupFileJob(["bash", "-c",
      "rm -f \"$1/$2.json\" \"$3/$2\"-*", "--",
      popupStateDir,
      NotificationFiles.imageStem(row),
      imagesDir])
  }

  // A popup that leaves the screen keeps its file — it just moves one level
  // down, into historyDir. Trimming happens right there in the same shell
  // job: the names sort numerically by their leading millisecond timestamp,
  // so everything but the newest historyLimit files is the tail to drop,
  // image copies included. Callers set $hist, $limit and $imgs first.
  readonly property string trimHistoryScript:
    "ls -1 \"$hist\" 2>/dev/null | sort -n | head -n \"-$limit\" | while IFS= read -r stale; do rm -f \"$hist/$stale\" \"$imgs/${stale%.json}\"-*; done"

  function archivePopupFileFor(row) {
    if (!row) return
    // A history replay or the empty-history placeholder has no file to move;
    // the failed mv leaves the history untouched, trimming included. Image
    // copies stay put — live and archived entries share imagesDir.
    enqueuePopupFileJob(["bash", "-c",
      "mkdir -p \"$1\" || exit 0\n" +
      "hist=\"$1\" limit=\"$2\" imgs=\"$5\"\n" +
      "mv -f \"$4/$3\" \"$1/$3\" 2>/dev/null || exit 0\n" +
      trimHistoryScript, "--",
      historyDir,
      String(historyLimit),
      NotificationFiles.popupFileName(row),
      popupStateDir,
      imagesDir])
  }

  // Record a notification that never made it to the screen (DND silenced
  // it), straight into history. Same file format as an archived popup, so
  // the replay can't tell the two apart.
  function writeHistoryFile(entry, done) {
    if (!entry) {
      if (done) done()
      return
    }
    var persistable = NotificationFiles.persistablePopup(entry, imagesDir)
    var command = ["bash", "-c",
      "mkdir -p \"$1\" \"$5\" || exit 0\n" +
      "hist=\"$1\" limit=\"$2\" name=\"$3\" json=\"$4\" imgs=\"$5\"\n" +
      "shift 5\n" +
      copyImagesScript +
      "printf '%s\\n' \"$json\" > \"$hist/$name\" || exit 0\n" +
      trimHistoryScript, "--",
      historyDir,
      String(historyLimit),
      NotificationFiles.popupFileName(entry),
      NotificationFiles.serializePopup(persistable.entry),
      imagesDir]
    for (var i = 0; i < persistable.copies.length; i++)
      command.push(persistable.copies[i].from, persistable.copies[i].to)
    enqueuePopupFileJob(command, done)
  }

  // Persist a silenced notification, held tracked until its content is
  // stable: untracking tells the sender its notification closed (Chromium
  // then deletes its image files), and a replaces_id update lands on this
  // object without a second onNotification — releasing on a stale snapshot
  // would drop it. Each catch-up write reuses the original file identity.
  function writeSilenced(notification, written) {
    writeHistoryFile(written, function() {
      var updated = null
      try {
        updated = NotificationFiles.replacementSnapshot(notification, written.originalId, written.timestamp)
      } catch (e) {
        // Torn down by the server while the write was queued.
      }
      if (updated && NotificationFiles.popupRowChanged(written, updated)) {
        service.writeSilenced(notification, updated)
        return
      }
      service.releaseRef(notification, written.originalId)
    })
  }

  // A restart can kill a queued job between its cp and its JSON write,
  // leaving copies no JSON-derived cleanup can name. Swept at startup,
  // through the queue so in-flight copies aren't mistaken for orphans.
  function sweepOrphanImages() {
    enqueuePopupFileJob(["bash", "-c",
      "for img in \"$3\"/*; do\n" +
      "  [[ -e $img ]] || continue\n" +
      "  [[ $img == *.tmp ]] && { rm -f -- \"$img\"; continue; }\n" +
      "  stem=\"${img##*/}\"\n" +
      "  stem=\"${stem%-*}\"\n" +
      "  [[ -e $1/$stem.json || -e $2/$stem.json ]] || rm -f \"$img\"\n" +
      "done", "--", popupStateDir, historyDir, imagesDir])
  }

  Process {
    id: readHistoryProc

    running: false
    // Let the file queue go again, whatever the read did — a failed or empty
    // read must not leave archives and clears parked behind it forever.
    onExited: service.runNextPopupFileJob()
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.replayHistory(text)
    }
  }

  // ----- restore ----------------------------------------------------------
  //
  // Re-show popups that were on screen when the previous shell died. The
  // glob-through-bash tolerates a missing/empty dir (first run); awk 1
  // (not cat) so a torn file missing its trailing newline can't glue
  // itself onto the next file and take a valid popup down with it.

  Process {
    id: restorePopupsProc

    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.restorePopups(text)
    }
  }

  function restorePopups(raw) {
    var entries = NotificationFiles.parsePopupFiles(raw)
    var now = Date.now()
    var live = []
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var duration = durationFor(entry.urgency, entry.expireTimeout)
      if (NotificationFiles.popupExpired(entry, duration, now)) {
        // It would have expired on screen had the shell kept running, so it
        // gets archived exactly like an expiry that happened while it did.
        archivePopupFileFor(entry)
        continue
      }
      // Survivors restart with a full lifetime on purpose: shell restarts
      // are rare, and a full look after the restart flicker beats resuming
      // a toast with a second left on its clock. The reset is persisted as
      // an absolute deadline so a second restart while the toast is still
      // on screen judges it by the reset clock, not the original timestamp.
      if (duration > 0) {
        entry.deadline = now + duration
        persistPopupFile(entry)
        // deadline is persistence metadata, not a model role — fresh rows
        // never carry it, and ListModel roles must stay consistent.
        delete entry.deadline
      }
      live.push(entry)
    }
    if (live.length === 0) return

    Qt.callLater(function() {
      for (var j = 0; j < live.length; j++) {
        var restored = live[j]
        // A notification received while the restore was reading the dir can
        // already occupy this originalId with the same timestamp — then it
        // IS this entry, live with its own file, and must be left alone. A
        // different timestamp is indistinguishable between a genuine
        // cross-restart replaces_id and a new-generation id coincidence, so
        // show both: a briefly duplicated toast beats silently dropping a
        // restored critical alert.
        var duplicate = false
        for (var k = 0; k < popupModel.count; k++) {
          var row = popupModel.get(k)
          if (row && row.originalId === restored.originalId && row.timestamp === restored.timestamp) {
            duplicate = true
            break
          }
        }
        if (duplicate) continue
        // Append (entries are newest-first) so restored toasts stack in
        // their original order below anything that just arrived. Restored
        // popups have no liveRefs entry — the server object died with the
        // old shell — so dismissal and action fallbacks degrade gracefully.
        service.restoredPopups[NotificationFiles.popupFileName(restored)] = true
        popupModel.append(restored)
      }
    })
  }

  // ----- history -----------------------------------------------------------
  //
  // History is the archived files in historyDir — there is no in-memory
  // copy. `showHistory` re-shows them as toasts, newest on top.

  // Toasts that were on screen when the replay was asked for. The clear in
  // replayHistory archives them, but the directory read is already in
  // flight by then, so they're handed over in memory instead of being
  // waited for.
  property var replayCarryOver: []

  // Set from the moment a read is queued until it starts, so a second
  // showHistory while one is still waiting its turn doesn't queue another.
  property bool historyReadQueued: false

  function showHistory() {
    if (readHistoryProc.running || historyReadQueued) return "ok"
    replayCarryOver = liveRowsForReplay()
    historyReadQueued = true
    enqueueHistoryRead()
    return "ok"
  }

  function startHistoryRead() {
    historyReadQueued = false
    readHistoryProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", historyDir]
    readHistoryProc.running = true
  }

  // Copy the on-screen rows out of the model. The placeholder from an
  // earlier empty replay carries originalId -1 and is not a notification,
  // so it is left behind rather than replayed as one. The replay dismisses
  // these notifications, and senders delete their images on close — so the
  // carried rows point at the persisted copies, like the archived files
  // they join.
  function liveRowsForReplay() {
    var rows = []
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (!row || row.originalId < 0) continue
      rows.push(NotificationFiles.persistablePopup({
        originalId: row.originalId,
        app: row.app,
        appIcon: row.appIcon,
        summary: row.summary,
        body: row.body,
        image: row.image,
        urgency: row.urgency,
        timestamp: row.timestamp
      }, imagesDir).entry)
    }
    return rows
  }

  function replayHistory(raw) {
    // Newest-first, de-duplicated against what the directory read already
    // saw (the carry-over rows race their own archival), capped at
    // historyLimit.
    var rows = NotificationFiles.historyRows(raw, replayCarryOver, historyLimit)
    replayCarryOver = []

    // Replaying nothing at all looks like a dead keybinding, so say so.
    if (rows.length === 0) {
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
      return
    }

    clearPopups()
    // Oldest first (rows arrive newest-first): each insert lands at the
    // top, so the newest ends up on top of the stack like a fresh arrival.
    // Replay rows carry originalId -1 so dismissal and clicks never
    // resolve to a live server object: their notification died with the
    // sender long ago, and the id may since belong to an unrelated one. The
    // replay's lifetime comes from the urgency alone — a critical original
    // must not stick on screen forever just because history was opened.
    for (var i = rows.length - 1; i >= 0; i--) {
      var entry = rows[i]
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
  }

  function clearHistory() {
    // Forget the recorded history; the toasts on screen stay put.
    enqueuePopupFileJob(["bash", "-c",
      "for f in \"$1\"/*.json; do\n" +
      "  [[ -e $f ]] || continue\n" +
      "  stale=\"${f##*/}\"\n" +
      "  rm -f \"$f\" \"$2/${stale%.json}\"-*\n" +
      "done", "--", historyDir, imagesDir])
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

    // Drop the server on live config reloads, like Omarchy's: a reloaded
    // instance's tracked notifications have no owners left (their signal
    // handlers and popups died with the old tree), and the on-disk restore
    // below repopulates the toasts instead.
    keepOnReload: false
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

  // Make sure the state directories exist before the first settings save
  // and popup persist. FileView does not create parent directories.
  Process {
    id: ensureStateDir

    command: [
      "mkdir", "-p",
      service.statePath.substring(0, service.statePath.lastIndexOf("/")),
      service.popupStateDir,
      service.historyDir,
      service.imagesDir
    ]
  }

  Component.onCompleted: {
    ensureStateDir.running = true
    // Once mkdir has had a tick: re-show popups that were on screen when
    // the previous shell died, and sweep image copies a killed queue left
    // behind. Safe beside the restore read: the sweep only deletes images
    // whose JSON is gone from both directories — exactly the ones the read
    // can't restore.
    Qt.callLater(function() {
      restorePopupsProc.command = ["bash", "-c", "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", service.popupStateDir]
      restorePopupsProc.running = true
      sweepOrphanImages()
    })
  }

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
