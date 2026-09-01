// M8: the media service. The MPRIS player picking that M7's OSD grew
// inline becomes the shell's shared service, grown to Omarchy Quattro's
// full ladder (https://github.com/basecamp/omarchy, MIT): the media keys
// (via `qs ipc call media …`, bound in hyprland.lua), the OSD's media
// popups, and the audio panel (AudioPanel.qml) all act on one
// `activePlayer`.
//
// The ladder, most to least preferred: the user's last-picked player
// while it plays; the player that has been playing longest, preferring
// ones with a live pipewire playback stream (a player actually moving
// samples beats one merely claiming to play); the last-picked player;
// then the first stream-backed, track-metadata-having, controllable, or
// identified player. Proxy players (playerctld) rank behind real ones at
// every step — a front for other players only wins when nothing it
// fronts exists.
//
// Omarchy behaviors kept: the reactive playing-order bookkeeping
// (recomputed from the players' own isPlaying signals, never polled),
// waiting for next/previous to actually change tracks before showing the
// OSD (so it names the new track, not the old one), play/pause aiming at
// the oldest playing player first, and per-player actions for the panel
// (targetKey). Deliberately NOT here vs Omarchy: their media source
// cycling (switchSource and its transferPlayback dance — granite has no
// source keybinds; the panel's player rows do the picking instead) and
// their MPRIS volume passthrough (sink controls are the pipewire half of
// M8's panel).
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import QtQuick

import "MediaModel.js" as MediaModel

Item {
  id: service

  // Wired to the shell's Osd instance by shell.qml; media feedback is an
  // OSD popup (or nothing, when the panel drives the action itself).
  property var osd: null

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && MediaModel.isPlaybackStream(n)) list.push(n)
    }
    return list
  }

  // The default nodes' audio interfaces only exist while something holds
  // a reference — track the streams so their labels resolve for ranking.
  PwObjectTracker { objects: service.playbackStreams }

  // ----- active player ------------------------------------------------------

  property string preferredPlayerKey: ""
  property var playingOrder: ({})
  property int playSerial: 0

  readonly property var activePlayer: selectActivePlayer()
  readonly property bool hasMedia: MediaModel.hasTrackMetadata(activePlayer)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer ? (activePlayer.trackAlbum || "") : ""
  readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""
  readonly property string identity: activePlayer
    ? (activePlayer.identity || activePlayer.desktopEntry || MediaModel.playerAppLabel(activePlayer))
    : ""

  function playerKey(player) {
    return MediaModel.playerKey(player)
  }

  function playerByKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++)
      if (playerKey(players[i]) === key) return players[i]
    return null
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playingOrder[key] : undefined
    return value === undefined ? fallback : value
  }

  // Reactive start-of-playback ordering (Omarchy's syncPlayingOrder
  // shape): recomputed from the players' own isPlaying signals, never
  // polled. The whole object is replaced (not mutated) so the
  // activePlayer binding re-evaluates.
  function syncPlayingOrder() {
    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playingOrder[key] === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = playingOrder[key]
      }
    }

    // A preferred player that died stops preferring.
    if (preferredPlayerKey && !alive[preferredPlayerKey]) preferredPlayerKey = ""

    playSerial = serial
    playingOrder = next
  }

  onPlayersChanged: syncPlayingOrder()
  Component.onCompleted: syncPlayingOrder()

  Instantiator {
    model: service.players

    delegate: Connections {
      required property var modelData

      target: modelData

      function onIsPlayingChanged() {
        service.syncPlayingOrder()
      }
    }
  }

  function oldestPlayingPlayer(requirePlaybackStream) {
    var oldest = null
    var oldestOrder = 0
    var playingProxy = null
    var proxyOrder = 0

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p || !p.isPlaying) continue

      if (requirePlaybackStream && !MediaModel.playerHasPlaybackStream(p, playbackStreams)) continue

      var proxy = MediaModel.isProxyPlayer(p)
      var order = playerOrder(p, i + 1000)
      if (!proxy && (oldest === null || order < oldestOrder)) {
        oldest = p
        oldestOrder = order
      } else if (proxy && (playingProxy === null || order < proxyOrder)) {
        playingProxy = p
        proxyOrder = order
      }
    }

    return oldest !== null ? oldest : playingProxy
  }

  function selectActivePlayer() {
    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var streamPlayer = null
    var streamProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxy = MediaModel.isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && MediaModel.hasMetadata(p))
        preferred = p

      if (MediaModel.playerHasPlaybackStream(p, playbackStreams)) {
        if (!proxy && streamPlayer === null) streamPlayer = p
        else if (proxy && streamProxy === null) streamProxy = p
      } else if (MediaModel.hasTrackMetadata(p)) {
        if (!proxy && trackPlayer === null) trackPlayer = p
        else if (proxy && trackProxy === null) trackProxy = p
      } else if (MediaModel.playerCanControl(p)) {
        if (!proxy && controllablePlayer === null) controllablePlayer = p
        else if (proxy && controllableProxy === null) controllableProxy = p
      } else if (MediaModel.hasMetadata(p)) {
        if (!proxy && identityPlayer === null) identityPlayer = p
        else if (proxy && identityProxy === null) identityProxy = p
      }
    }

    if (preferred !== null && preferred.isPlaying) return preferred
    var streamPreferred = preferred !== null && MediaModel.playerHasPlaybackStream(preferred, playbackStreams)
      ? preferred
      : null
    return oldestPlayingPlayer(true)
      || oldestPlayingPlayer(false)
      || streamPreferred
      || streamPlayer
      || streamProxy
      || preferred
      || trackPlayer
      || trackProxy
      || controllablePlayer
      || controllableProxy
      || identityPlayer
      || identityProxy
      || null
  }

  // The panel's picker rows: playing first, then by start order, then by
  // name; proxy players sink within each tier.
  readonly property var orderedPlayers: {
    var list = players.slice()
    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (MediaModel.isProxyPlayer(a) !== MediaModel.isProxyPlayer(b))
        return MediaModel.isProxyPlayer(a) ? 1 : -1
      if (a.isPlaying && b.isPlaying) {
        var orderDelta = playerOrder(a, 1000) - playerOrder(b, 1000)
        if (orderDelta !== 0) return orderDelta
      }
      return playerLabel(a).localeCompare(playerLabel(b))
    })
    return list
  }

  function playerLabel(player) {
    if (!player) return "Unknown"
    return String(player.identity || player.desktopEntry || MediaModel.playerAppLabel(player) || "Unknown")
  }

  function selectPlayer(key) {
    var player = playerByKey(key)
    if (player === null || !MediaModel.hasMetadata(player)) return false
    preferredPlayerKey = playerKey(player)
    return true
  }

  // ----- actions -------------------------------------------------------------

  function canHandle(player, action) {
    return MediaModel.canHandleAction(player, action)
  }

  // Pause stops the oldest playing player (with a stream, else without):
  // pausing "whatever is actually audible" beats pausing the picker's
  // stale selection.
  function playerForAction(action, targetKey) {
    var targeted = playerByKey(targetKey)
    if (targeted !== null) return targeted

    if (action === "pause" || action === "playPause") {
      var oldest = oldestPlayingPlayer(true) || oldestPlayingPlayer(false)
      if (oldest !== null) return oldest
    }

    if (canHandle(activePlayer, action)) return activePlayer
    for (var i = 0; i < players.length; i++)
      if (MediaModel.hasMetadata(players[i]) && canHandle(players[i], action)) return players[i]
    return activePlayer
  }

  // The icon carries the action; the message carries "Title - Artist"
  // (the player identity when the track has none) and only falls back to
  // the action label when there is nothing to name.
  function mediaMessage(player, fallback) {
    return MediaModel.osdMessage(player, fallback)
  }

  function osdShow(key, message) {
    if (service.osd === null) return
    service.osd.showMessage(key, message)
  }

  // next/previous race the player's metadata update; wait briefly for the
  // new track (Omarchy's pendingTrackOsd) so the popup names it.
  property var pendingTrackOsd: null

  Timer {
    id: trackOsdTimer

    interval: 120
    onTriggered: service.flushPendingTrackOsd()
  }

  function showOsd(actionLabel, key, player) {
    osdShow(key, mediaMessage(player, actionLabel))
  }

  function scheduleOsd(actionLabel, key, player, waitForTrack, beforeSignature) {
    if (waitForTrack) {
      pendingTrackOsd = {
        actionLabel: actionLabel,
        key: key,
        playerKey: playerKey(player),
        before: beforeSignature,
        attempts: 0
      }
      trackOsdTimer.restart()
    } else {
      showOsd(actionLabel, key, player)
    }
  }

  function flushPendingTrackOsd() {
    var pending = pendingTrackOsd
    if (!pending) return
    // The player may have died mid-wait; the fallback label still shows.
    var player = playerByKey(pending.playerKey)
    if (player === null || MediaModel.trackChanged(pending.before, player) || pending.attempts >= 10) {
      pendingTrackOsd = null
      showOsd(pending.actionLabel, pending.key, player)
      return
    }
    pending.attempts += 1
    pendingTrackOsd = pending
    trackOsdTimer.restart()
  }

  // One entry point for the keys, the panel, and scripts. showFeedback
  // false is the panel's transport: the result is on screen already, an
  // OSD over it is noise. targetKey routes the action at one player (the
  // panel's rows); empty means "the active ladder decides".
  function runAction(action, showFeedback, targetKey) {
    var player = playerForAction(action, targetKey)
    if (!canHandle(player, action)) {
      // Dead keys look broken; say so instead.
      if (showFeedback) osdShow("media", "No media player")
      return false
    }

    var label = "Play/pause"
    var key = "media"
    var before = MediaModel.trackSignature(player)
    var handled = false

    if (action === "next") {
      label = "Next"
      key = "media-next"
      if (player.canGoNext) {
        player.next()
        handled = true
      }
    } else if (action === "previous") {
      label = "Previous"
      key = "media-previous"
      if (player.canGoPrevious) {
        player.previous()
        handled = true
      }
    } else if (action === "play") {
      label = "Play"
      key = "media-play"
      if (player.canPlay) {
        player.play()
        handled = true
      } else if (player.canTogglePlaying && !player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "pause") {
      label = "Pause"
      key = "media-pause"
      if (player.canPause) {
        player.pause()
        handled = true
      } else if (player.canTogglePlaying && player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else {
      label = player.isPlaying ? "Pause" : "Play"
      key = player.isPlaying ? "media-pause" : "media-play"
      if (player.isPlaying && player.canPause) {
        player.pause()
        handled = true
      } else if (!player.isPlaying && player.canPlay) {
        player.play()
        handled = true
      } else if (player.canTogglePlaying) {
        player.togglePlaying()
        handled = true
      }
    }

    if (handled) preferredPlayerKey = playerKey(player)
    if (showFeedback)
      scheduleOsd(label, key, player,
        handled && (action === "next" || action === "previous"), before)
    return handled
  }

  // ----- IPC ---------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call media next` etc.

  IpcHandler {
    target: "media"

    function playPause(): string {
      return service.runAction("playPause", true) ? "ok" : "none"
    }

    function play(): string {
      return service.runAction("play", true) ? "ok" : "none"
    }

    function pause(): string {
      return service.runAction("pause", true) ? "ok" : "none"
    }

    function next(): string {
      return service.runAction("next", true) ? "ok" : "none"
    }

    function previous(): string {
      return service.runAction("previous", true) ? "ok" : "none"
    }

    function status(): string {
      var p = service.activePlayer
      return JSON.stringify({
        players: service.players.length,
        activePlayer: service.mediaMessage(p, ""),
        activePlayerKey: service.playerKey(p),
        playing: p ? !!p.isPlaying : false,
        title: p ? (p.trackTitle || "") : "",
        artist: p ? (p.trackArtist || "") : "",
        album: p ? (p.trackAlbum || "") : "",
        artUrl: p ? (p.trackArtUrl || "") : "",
        canGoNext: p ? !!p.canGoNext : false,
        canGoPrevious: p ? !!p.canGoPrevious : false,
        canTogglePlaying: p ? !!p.canTogglePlaying : false
      })
    }

    function ping(): string {
      return "ok"
    }
  }
}
