// File-backed persistence for the notifications service, ported from
// Omarchy's NotificationLogic.js (https://github.com/basecamp/omarchy,
// MIT) and reduced to granite's entry shape (no glyph/execArgv hints, no
// id/originalId split — granite's rows carry originalId only).
//
// Layout under ~/.local/state/granite/notifications/:
//   <timestamp>-<originalId>.json   one per on-screen popup — the file
//                                  exists exactly as long as the toast
//                                  is showing
//   history/<timestamp>-<id>.json   the same file after the toast left
//                                  the screen; this directory IS the
//                                  history `showHistory` replays
//   images/<timestamp>-<id>-<role>  copies of the images persisted
//                                  entries reference — the sender's
//                                  originals don't outlive the
//                                  notification (Chromium-family senders
//                                  delete theirs on close), so each copy
//                                  lives and dies with the JSON file
//                                  whose stem it carries
//
// The file name (timestamp + originalId) is the entry's identity: it
// travels with the row through every model and file round-trip, which is
// what keeps replaces_id updates, restores and archives hitting the same
// file even though ids repeat across server generations.

// Everything the card draws, and therefore everything an in-place update
// has to write through to the row and its file.
var POPUP_ROLES = ["app", "appIcon", "summary", "body", "image", "urgency", "expireTimeout"]

function snapshotOf(notification, timestamp) {
  var n = notification || {}
  var expireTimeout = Number(n.expireTimeout || 0)
  if (!isFinite(expireTimeout) || expireTimeout < 0) expireTimeout = 0
  return {
    originalId: n.id || 0,
    app: n.appName || "",
    appIcon: n.appIcon || "",
    summary: String(n.summary || ""),
    body: n.body || "",
    image: n.image || "",
    urgency: typeof n.urgency === "number" ? n.urgency : 1,
    expireTimeout: expireTimeout,
    timestamp: timestamp === undefined ? Date.now() : timestamp
  }
}

// A client updating a notification through replaces_id keeps the identity
// of the popup it took over: only what the card draws comes from the
// updated object, the id and timestamp stay the replaced row's.
function replacementSnapshot(notification, originalId, timestamp) {
  var updated = snapshotOf(notification, timestamp)
  updated.originalId = originalId
  return updated
}

// Whether a refresh has anything to write. Each property a client updates
// emits its own signal, and the catch-up refresh after a row is inserted
// usually finds the object exactly as it was snapshotted — without this,
// one update would rewrite the file several times over.
function popupRowChanged(row, updated) {
  var current = row || {}
  var next = updated || {}
  for (var i = 0; i < POPUP_ROLES.length; i++) {
    var role = POPUP_ROLES[i]
    if (current[role] !== next[role]) return true
  }
  return false
}

// ---------------------------------------------------- persisted images
//
// A notification's images only exist while it is live: Chromium-family
// senders delete their scoped /tmp files on close, and image-data hints
// surface as in-process image:// URLs that die with the server object.
// Persisted entries therefore reference their own copies, named by the
// entry's file stem so cleanup can find them from the JSON file name
// alone.

var PERSISTED_IMAGE_ROLES = ["appIcon", "image"]

function imageStem(entry) {
  var e = entry || {}
  return String(e.timestamp || 0) + "-" + String(e.originalId || 0)
}

function popupFileName(entry) {
  return imageStem(entry) + ".json"
}

// The filesystem path behind a file-backed image value, or "" for anything
// a copy can't capture: themed icon names, in-process image:// URLs, empty.
function localImageFile(value) {
  var s = String(value || "")
  if (s.indexOf("file://") === 0) {
    s = s.slice(7)
    try { s = decodeURIComponent(s) } catch (e) {}
  }
  return s.charAt(0) === "/" ? s : ""
}

// The entry as it should hit the disk, plus the copies that make it true.
// File-backed images redirect to their copy under imagesDir; dead image://
// URLs drop to "" (the card falls back to the app icon).
// Already-redirected values map onto themselves and produce no copy,
// keeping restores no-ops.
function persistablePopup(entry, imagesDir) {
  var e = entry || {}
  var out = {}
  for (var key in e) out[key] = e[key]
  var copies = []
  for (var i = 0; i < PERSISTED_IMAGE_ROLES.length; i++) {
    var role = PERSISTED_IMAGE_ROLES[i]
    var value = String(out[role] || "")
    if (!value) continue
    var source = localImageFile(value)
    if (source) {
      var copy = String(imagesDir || "") + imageStem(e) + "-" + role
      if (source !== copy) copies.push({ from: source, to: copy })
      out[role] = "file://" + copy
    } else if (value.indexOf("image://") === 0) {
      out[role] = ""
    }
  }
  return { entry: out, copies: copies }
}

// ---------------------------------------------------- files

// Normalize a value from disk (or the sender) into a persistable popup
// entry. The absolute expiry deadline is set only when a restore resets a
// surviving popup's display lifetime, and is kept out of the entry
// entirely when unset so restored rows match the roles of freshly
// received ones.
function popupEntry(value) {
  var e = value || {}
  var expire = Number(e.expireTimeout || 0)
  if (!isFinite(expire) || expire < 0) expire = 0
  var entry = {
    originalId: e.originalId || e.id || 0,
    app: e.app || "",
    appIcon: e.appIcon || "",
    summary: e.summary || "",
    body: e.body || "",
    image: e.image || "",
    urgency: typeof e.urgency === "number" ? e.urgency : 1,
    expireTimeout: expire,
    timestamp: e.timestamp || 0
  }
  var deadline = Number(e.deadline || 0)
  if (isFinite(deadline) && deadline > 0) entry.deadline = deadline
  return entry
}

function serializePopup(entry) {
  // Compact (single-line) on purpose: restore cats every file together and
  // parses line by line, which only works when each file is one line.
  return JSON.stringify(popupEntry(entry))
}

// Parse the concatenation of every persisted popup file into entries,
// newest-first. Deliberately NO dedupe by originalId: ids restart from 1
// with every server process, so two files sharing an id are usually
// different generations — dropping the older one would silently discard a
// restored critical alert the moment a fresh notification reuses its id.
// The one case that leaves a genuine duplicate (a crash between a
// replacement's write and the replaced file's delete) merely re-shows a
// superseded toast, which expires or is dismissed and cleans itself up.
function parsePopupFiles(raw) {
  var lines = String(raw || "").split("\n")
  var entries = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var value = JSON.parse(line)
      if (value && typeof value === "object") entries.push(popupEntry(value))
    } catch (e) {
      // A torn write from a crash mid-save — skip the line, keep the rest.
    }
  }
  entries.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return entries
}

// A persisted popup whose lifetime already ran out would have expired on
// screen had the shell kept running, so it is not restored. duration 0
// means the popup never expires (critical urgency) and always survives
// restarts. A restore-reset deadline outranks the original timestamp:
// without it, a second restart would judge a re-shown toast by a clock
// that no longer governs its display and drop it while it is still on
// screen.
function popupExpired(entry, duration, now) {
  var deadline = Number((entry || {}).deadline || 0)
  if (isFinite(deadline) && deadline > 0) return Number(now) >= deadline
  var lifetime = Number(duration || 0)
  if (!isFinite(lifetime) || lifetime <= 0) return false
  return (Number(now) - Number((entry || {}).timestamp || 0)) >= lifetime
}

// ---------------------------------------------------- history
//
// The archived files are the history. They are read back exactly like the
// live popup files, then normalized into replay rows: replaying a toast
// must not inherit the original's expire timeout or restore deadline, so
// it gets the standard on-screen lifetime for its urgency instead.
function historyEntry(value) {
  var e = popupEntry(value)
  delete e.deadline
  e.expireTimeout = 0
  return e
}

// liveRows are the toasts still on screen when the replay was asked for.
// They belong in it — they're the newest notifications there are — but the
// directory read races their archival, so they're carried across by hand
// and keyed by file name (timestamp + id) to drop the copy the read
// already saw.
function historyRows(raw, liveRows, limit) {
  var max = limit === undefined || limit === null ? 10 : Number(limit)
  if (isNaN(max)) max = 10
  max = Math.max(0, max)

  var out = []
  var seen = {}
  function collect(rows) {
    for (var i = 0; i < rows.length; i++) {
      var entry = rows[i]
      if (!entry) continue
      var key = popupFileName(entry)
      if (seen[key]) continue
      seen[key] = true
      out.push(historyEntry(entry))
    }
  }

  collect(Array.isArray(liveRows) ? liveRows : [])
  collect(parsePopupFiles(raw))
  out.sort(function(a, b) { return (b.timestamp || 0) - (a.timestamp || 0) })
  return out.slice(0, max)
}
