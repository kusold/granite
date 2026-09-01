// M11: the network panel. SUPER+CTRL+W (bound in hyprland.lua via
// `qs ipc call network toggle`, Omarchy Quattro's network binding) opens
// the centered card on the focused monitor with the connection state: a
// hero naming what's connected (Wi-Fi SSID or Ethernet, the radio's
// on/off switch beside it), a stats grid fed by `granite-network-status`
// (internet ping and packet loss from a rolling sample window, live
// receive/send rates from /sys counter deltas, session totals, and the
// route's address and gateway — click either to copy), and the Wi-Fi list
// through Quickshell's NetworkManager service: known and other networks
// sorted connected-first with signal glyphs, an inline passphrase prompt
// (identity field for 802.1X) for protected networks without saved
// credentials, click to connect/disconnect, forget for saved ones, and
// per-row busy/failure states with human failure reasons.
//
// Omarchy behaviors kept: the whole reactive half over Quickshell's
// Networking service — the scanner lifecycle (tracked per device, first
// PHY scan deferred 100ms past the open so NetworkManager's AP flood
// doesn't stall it, released on close), primitive row snapshots so
// NetworkManager churn never leaves a dangling QObject in a delegate's
// var property, serialized per-network actions with completion checks +
// a 30s timeout outlasting the supplicant's 25s auth timeout, wrong-
// password reprompts, and the enterprise EAP connect (secret over stdin,
// never argv). Deliberately NOT here vs Omarchy: band pinning and DNS
// provider pills (omarchy-network-band / omarchy-dns), the speed-test
// and Wi-Fi-QR share buttons (their own summoned plugins), the rotating
// connection phrases, their sectioned keyboard cursor (granite gets the
// same reach from the flat row ladder — return activates, ←→ focus the
// forget action), tooltips, and their plugin/panel platform plumbing.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Wayland
import QtQuick
import "NetworkModel.js" as Model

Item {
  id: service

  // Palette shared with Bar.qml.
  readonly property string fontFamily: "JetBrainsMono Nerd Font"
  readonly property color foreground: "#f2f2f2"
  readonly property color accent: "#00ff99"
  readonly property color urgent: "#ff6e6e"

  // ----- tuning ------------------------------------------------------------

  readonly property int cardWidth: 440
  readonly property int heroHeight: 56
  readonly property int statsHeight: 84
  readonly property int rowHeight: 34
  readonly property int statusExtraHeight: 14
  readonly property int headerHeight: 26
  // A busy neighbourhood caps the ladder instead of pushing the card off
  // screen; what's cut is the weakest "other" networks.
  readonly property int maxNetworkRows: 12
  readonly property int detailsPollMs: 1500
  // Must outlast NetworkManager's 25s supplicant timeout: a wrong saved
  // PSK fails with WifiAuthTimeout at ~25s, and that failure has to land
  // while the action is still tracked to show "Wrong password" and reopen
  // the passphrase prompt.
  readonly property int actionTimeoutMs: 30000
  readonly property int pingHistoryWindow: 24
  readonly property int pingAverageWindow: 5

  // ----- state -------------------------------------------------------------

  property bool opened: false
  property int selectedIndex: 0
  // Left/Right on a network row focuses its Forget action, like the
  // audio panel's ←→ adjust.
  property bool forgetFocused: false

  // The flat cursor ladder: headers, hints, and the stats grid render but
  // never take the cursor; everything else is return-activatable and
  // hover-selectable.
  property var cursorRows: []

  // Live connection details from `granite-network-status`:
  // { iface, type, ip, prefix, gateway, rx_bytes, tx_bytes, ssid,
  //   signal_dbm, freq, bitrate | speed, duplex, router_ping_ms,
  //   internet_ping_ms }
  property var info: ({})

  // Throughput + ping tracking across successive samples. The first
  // sample after an open or an interface switch seeds the counters
  // instead of computing a fake rate from minutes ago.
  property string prevIface: ""
  property real prevRxBytes: 0
  property real prevTxBytes: 0
  property real prevSampleTime: 0
  property real downloadRate: 0
  property real uploadRate: 0
  property string pingIface: ""
  property var routerPingSamples: []
  property var internetPingSamples: []
  property real routerPingLatency: -1
  property real internetPingLatency: -1
  property int internetPingPacketLoss: 0
  readonly property bool hasInternetPing: internetPingSamples.length > 0
  // Every stat cell stays mounted whether or not there is data behind it,
  // so a sample arriving late never reflows the grid. This says whether
  // the numbers are real yet or the cell should read "--".
  readonly property bool hasTransferStats: info.rx_bytes !== undefined

  // ----- the NetworkManager service -----------------------------------------

  readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []

  // Prefer a connected device: a machine can expose several NICs of the
  // same type (an idle onboard port alongside the active adapter), and
  // the first-enumerated one may be carrierless.
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  readonly property var connectedWifiNetwork: findConnectedWifiNetwork()

  // Wired is preferred when both are up, matching the default-route
  // device the status script reports.
  readonly property string kind: {
    if (wiredDevice && wiredDevice.connected) return "ethernet"
    if (connectedWifiNetwork) return "wifi"
    return "disconnected"
  }
  readonly property int signalStrength: connectedWifiNetwork
    ? Math.round((connectedWifiNetwork.signalStrength || 0) * 100)
    : -1
  readonly property string icon: Model.connectionIcon(kind, signalStrength)
  readonly property bool wifiStationAvailable: !!wifiDevice
  readonly property bool canToggleWifi: networkManagerAvailable && wifiStationAvailable

  function findDevice(type) {
    var devices = networkDevices || []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }

  function findConnectedWifiNetwork() {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected) return networks[i]
    }
    return null
  }

  function toggleNetwork() {
    if (!networkManagerAvailable) return "unavailable"
    Networking.wifiEnabled = !Networking.wifiEnabled
    // Re-enabling the radio deserves a deliberate scan; let the state
    // settle first (Omarchy's recipe).
    Qt.callLater(function() { refresh(true) })
    return Networking.wifiEnabled ? "on" : "off"
  }

  // ----- scanner lifecycle ----------------------------------------------------
  //
  // scannerEnabled lives on the shared WifiDevice, which has no reference
  // counting. Tracking the device this panel turned scanning on for keeps
  // the release correct when the panel closes, the device is replaced, or
  // the shell is destroyed — without a closed instance ever claiming the
  // scanner.

  property var scannerDevice: null
  property bool scanning: false

  function setScannerEnabled(enabled) {
    var nextDevice = opened ? wifiDevice : null

    if (scannerDevice && scannerDevice !== nextDevice)
      scannerDevice.scannerEnabled = false

    scannerDevice = nextDevice

    if (scannerDevice)
      scannerDevice.scannerEnabled = enabled
  }

  Component.onDestruction: {
    if (scannerDevice) scannerDevice.scannerEnabled = false
  }

  // ----- the wifi list ---------------------------------------------------------

  // Primitive snapshots (see Model.wifiRow) sorted connected > known >
  // signal. Live WifiNetwork objects are resolved on demand.
  property var wifiNetworks: []

  function syncWifiNetworks() {
    var nets = []
    var networks = wifiNetworkObjects || []

    for (var i = 0; i < networks.length; i++) {
      var network = networks[i]
      if (!network) continue
      checkActionCompletion(network)
      var row = Model.wifiRow(network)
      if (row) nets.push(row)
    }
    wifiNetworks = Model.sortWifiRows(nets)
    rebuildRows()
  }

  function networkForSsid(ssid) {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].name === ssid) return networks[i]
    }
    return null
  }

  function wifiIconFor(strength) {
    return Model.wifiIconFor(strength)
  }

  function wifiSectionTitle(index) {
    return Model.wifiSectionTitle(wifiNetworks, index)
  }

  function isEnterpriseSecurity(security) {
    return security === WifiSecurityType.Wpa2Eap || security === WifiSecurityType.WpaEap
  }

  function requiresCredentials(security) {
    return Model.requiresCredentials(security, WifiSecurityType.Open, WifiSecurityType.Owe)
  }

  function canForgetNetwork(net) {
    return Model.canForgetNetwork(net)
  }

  // ----- per-network actions ------------------------------------------------------
  //
  // One action in flight at a time, tracked by SSID so rows render
  // "Connecting…" / "Disconnecting…" / "Forgetting…". Rows are primitive
  // snapshots that can outlive their WifiNetwork, so actions resolve the
  // live object on demand and a stale row no-ops instead of hitting an
  // unrelated network.

  property string actionSsid: ""
  property string actionKind: ""  // "connect" | "disconnect" | "forget"
  property string failureSsid: ""
  property string failureReason: ""
  property string passwordSsid: ""
  property string passwordText: ""
  property string identityText: ""

  // ConnectionFailReason values as a plain object, so Model helpers stay
  // pure JS.
  readonly property var connectionFailReasons: ({
    NoSecrets: ConnectionFailReason.NoSecrets,
    WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
    WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
    WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
    WifiClientFailed: ConnectionFailReason.WifiClientFailed
  })

  readonly property bool busy: actionKind !== ""

  function runNetworkAction(kind, network, callback) {
    if (actionKind !== "" || !network) return
    var ssid = network.name || ""
    actionSsid = ssid
    actionKind = kind
    failureSsid = ""
    failureReason = ""
    callback(network)
    // Safety net: if the completion checks never fire (process death,
    // signal handler throws), clear the busy state so the row doesn't
    // get stuck on "Connecting…" forever.
    actionTimeout.restart()
  }

  function clearNetworkAction() {
    actionTimeout.stop()
    if (actionKind === "connect") cancelPasswordPrompt()
    failureSsid = ""
    failureReason = ""
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  function failNetworkAction(network, reason) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    actionTimeout.stop()
    failureSsid = actionSsid
    failureReason = Model.networkFailureReason(reason, requiresCredentials(network.security), connectionFailReasons)
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  function checkActionCompletion(network) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    if (actionKind === "connect" && network.connected) clearNetworkAction()
    else if (actionKind === "disconnect" && !network.connected && !network.stateChanging) clearNetworkAction()
    else if (actionKind === "forget" && !network.known && !network.stateChanging) clearNetworkAction()
  }

  function connectDirectly(ssid) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connect() })
  }

  function connectWithPassphrase(ssid, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connectWithPsk(passphrase) })
  }

  // Creates and activates the 802.1X profile (see
  // Model.enterpriseConnectScript). The password goes over stdin, never
  // argv.
  function connectEnterprise(ssid, identity, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) {
      enterpriseConnect.secret = passphrase
      enterpriseConnect.command = ["bash", "-c", Model.enterpriseConnectScript, "nmcli-eap", ssid, identity]
      enterpriseConnect.running = true
    })
  }

  Process {
    id: enterpriseConnect

    property string secret: ""

    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
  }

  function disconnectRow(ssid) {
    runNetworkAction("disconnect", networkForSsid(ssid), function(network) { network.disconnect() })
  }

  function forget(net) {
    runNetworkAction("forget", net ? networkForSsid(net.ssid) : null, function(network) { network.forget() })
  }

  // ----- the passphrase prompt ------------------------------------------------
  //
  // `passwordSsid` is the row currently expanded into password-entry
  // mode; typed text lives here (not in the delegate) so scan refreshes
  // can't eat it, and the delegate restores it if it's recreated.

  function openPasswordPrompt(ssid) {
    if (passwordSsid !== ssid) {
      passwordText = ""
      identityText = ""
    }
    passwordSsid = ssid
  }

  function cancelPasswordPrompt() {
    passwordSsid = ""
    passwordText = ""
    identityText = ""
  }

  // When the prompt closes (Esc / success / failure path), restore focus
  // to the card so the ladder keys resume without a click.
  onPasswordSsidChanged: {
    if (passwordSsid === "" && opened)
      Qt.callLater(function() { if (card) card.forceActiveFocus() })
  }

  function submitPassphrase() {
    if (busy || passwordSsid === "" || passwordText.length === 0) return
    var row = networkRowForSsid(passwordSsid)
    if (!row || !networkForSsid(passwordSsid)) return
    if (isEnterpriseSecurity(row.security)) {
      if (identityText.length > 0) connectEnterprise(passwordSsid, identityText, passwordText)
      return
    }
    connectWithPassphrase(passwordSsid, passwordText)
  }

  // ----- connection details --------------------------------------------------------
  //
  // `granite-network-status` pulls the default route's interface,
  // addresses, counters, link details, and ping probes in one shot; the
  // panel polls it while open and feeds the samples through the Model's
  // state machines.

  Process {
    id: detailsProc

    command: ["granite-network-status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: service.updateDetails(text)
    }
  }

  Timer {
    id: detailsPoll

    interval: service.detailsPollMs
    repeat: true
    running: service.opened
    onTriggered: if (!detailsProc.running) detailsProc.running = true
  }

  function updateDetails(raw) {
    info = Model.parseKeyValue(raw)
    updateThroughput()
    updatePingLatency()
    rebuildRows()
  }

  function updateThroughput() {
    var state = Model.throughputState({
      prevIface: prevIface,
      prevRxBytes: prevRxBytes,
      prevTxBytes: prevTxBytes,
      prevSampleTime: prevSampleTime,
      downloadRate: downloadRate,
      uploadRate: uploadRate
    }, info, Date.now() / 1000)

    prevIface = state.prevIface
    prevRxBytes = state.prevRxBytes
    prevTxBytes = state.prevTxBytes
    prevSampleTime = state.prevSampleTime
    downloadRate = state.downloadRate
    uploadRate = state.uploadRate
  }

  function updatePingLatency() {
    var state = Model.pingLatencyState({
      pingIface: pingIface,
      routerPingSamples: routerPingSamples,
      internetPingSamples: internetPingSamples
    }, info, pingHistoryWindow, pingAverageWindow)

    pingIface = state.pingIface
    routerPingSamples = state.routerPingSamples
    internetPingSamples = state.internetPingSamples
    routerPingLatency = state.routerPingLatency
    internetPingLatency = state.internetPingLatency
    internetPingPacketLoss = state.internetPingPacketLoss
  }

  function formatBytes(bytes) {
    return Model.formatBytes(bytes)
  }

  function formatRate(bytesPerSec) {
    return Model.formatRate(bytesPerSec)
  }

  function formatPingLatency(ms) {
    return Model.formatPingLatency(ms, hasInternetPing)
  }

  function formatPacketLoss(percent) {
    return Model.formatPacketLoss(percent, hasInternetPing)
  }

  function copyToClipboard(value) {
    if (!value) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Model.shellQuote(value) + " | wl-copy"])
  }

  // ----- refresh + scan deferral ------------------------------------------------

  function refresh(scanWifi) {
    if (scanWifi === undefined) scanWifi = false
    if (!detailsProc.running) detailsProc.running = true
    // A closed panel has no list to fill; bare refresh() reaches here
    // from action completion and construction.
    if (opened && wifiDevice) {
      if (scanWifi) {
        scanning = true
        setScannerEnabled(false)
        scanRestart.start()
      } else {
        setScannerEnabled(true)
      }
    }
    syncWifiNetworks()
  }

  // The PHY scan is deferred 100ms past the open so the first frame isn't
  // stalled by NetworkManager's AP flood (Omarchy's recipe); the list
  // settles once the scan lands.
  Timer {
    id: scanRestart

    interval: 100
    onTriggered: {
      if (service.opened && service.wifiDevice) {
        service.setScannerEnabled(true)
        scanDone.start()
      }
    }
  }

  Timer {
    id: scanDone

    interval: 1500
    onTriggered: {
      service.scanning = false
      service.syncWifiNetworks()
    }
  }

  Timer {
    id: actionTimeout

    interval: service.actionTimeoutMs
    onTriggered: {
      if (!service.actionKind) return
      var reason
      if (service.actionKind === "connect") reason = "Timed out connecting"
      else if (service.actionKind === "disconnect") reason = "Timed out disconnecting"
      else reason = "Timed out forgetting"
      service.failureSsid = service.actionSsid
      service.failureReason = reason
      service.actionSsid = ""
      service.actionKind = ""
      service.refresh()
    }
  }

  // ----- the row ladder -------------------------------------------------------------

  function rebuildRows() {
    if (!opened) {
      cursorRows = []
      return
    }

    // Keep the cursor on the same network across rebuilds (scans shift
    // indices constantly), and pinned to the prompt row while it's open.
    var previousSsid = selectedSsid()
    var rows = []

    rows.push({ kind: "hero" })
    if (info.iface) rows.push({ kind: "stats" })
    if (!networkManagerAvailable) rows.push({ kind: "hint", label: "NetworkManager unavailable" })

    if (wifiStationAvailable) {
      rows.push({ kind: "header", label: scanning ? "SCANNING WI-FI…" : "WI-FI" })
      var shown = 0
      for (var i = 0; i < wifiNetworks.length && shown < maxNetworkRows; i++) {
        var title = Model.wifiSectionTitle(wifiNetworks, i)
        if (title !== "") rows.push({ kind: "header", label: title })
        rows.push({ kind: "network", net: wifiNetworks[i] })
        shown++
      }
      if (wifiNetworks.length === 0) {
        rows.push({ kind: "hint", label: Networking.wifiEnabled ? "No networks found" : "Wi-Fi is off" })
      } else if (wifiNetworks.length > shown) {
        rows.push({ kind: "hint", label: "+" + (wifiNetworks.length - shown) + " weaker networks hidden" })
      }
    }

    cursorRows = rows
    restoreSelection(previousSsid)
  }

  function selectedSsid() {
    if (selectedIndex >= 0 && selectedIndex < cursorRows.length && cursorRows[selectedIndex].kind === "network") {
      var net = cursorRows[selectedIndex].net
      return net ? net.ssid : null
    }
    return null
  }

  function rowIndexOfSsid(ssid) {
    for (var i = 0; i < cursorRows.length; i++) {
      if (cursorRows[i].kind === "network" && cursorRows[i].net && cursorRows[i].net.ssid === ssid)
        return i
    }
    return -1
  }

  function networkRowForSsid(ssid) {
    var idx = rowIndexOfSsid(ssid)
    return idx >= 0 ? cursorRows[idx].net : null
  }

  function restoreSelection(previousSsid) {
    if (passwordSsid !== "") {
      var promptIndex = rowIndexOfSsid(passwordSsid)
      if (promptIndex >= 0) {
        selectedIndex = promptIndex
        syncForgetFocus()
        return
      }
    }
    if (previousSsid !== null) {
      var sameIndex = rowIndexOfSsid(previousSsid)
      if (sameIndex >= 0) {
        selectedIndex = sameIndex
        syncForgetFocus()
        return
      }
    }
    clampSelection()
  }

  function syncForgetFocus() {
    if (!canForgetRow(selectedIndex)) forgetFocused = false
  }

  function canForgetRow(index) {
    return index >= 0 && index < cursorRows.length && cursorRows[index].kind === "network"
      && Model.canForgetNetwork(cursorRows[index].net)
  }

  function rowSelectable(entry) {
    if (entry === undefined || entry === null) return false
    if (entry.kind === "network") return true
    // On a wired box with no wifi radio the hero has nothing to switch.
    if (entry.kind === "hero") return canToggleWifi
    return false
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
    if (selectedIndex >= 0 && selectedIndex < cursorRows.length && rowSelectable(cursorRows[selectedIndex])) {
      syncForgetFocus()
      return
    }
    selectedIndex = selectedIndex > lastSelectable() ? lastSelectable() : firstSelectable()
    forgetFocused = false
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
    forgetFocused = false
  }

  // ----- acting on rows -----------------------------------------------------------

  function activateRow(index) {
    if (index < 0 || index >= cursorRows.length) return
    var entry = cursorRows[index]

    if (entry.kind === "hero") {
      toggleNetwork()
      return
    }
    if (entry.kind !== "network" || busy) return
    var net = entry.net

    if (forgetFocused && Model.canForgetNetwork(net)) {
      forget(net)
      return
    }
    if (passwordSsid === net.ssid) {
      // Clicking the row its prompt is attached to keeps the prompt open
      // (with its text intact) rather than submitting behind the field.
      openPasswordPrompt(net.ssid)
      return
    }
    if (net.connected) {
      disconnectRow(net.ssid)
      return
    }
    if (requiresCredentials(net.security) && !net.known) {
      openPasswordPrompt(net.ssid)
      return
    }
    connectDirectly(net.ssid)
  }

  // Left/Right on a network row: focus / unfocus its Forget action.
  function stepRow(direction) {
    if (selectedIndex < 0 || selectedIndex >= cursorRows.length) return
    var entry = cursorRows[selectedIndex]
    if (entry.kind !== "network") return
    if (!Model.canForgetNetwork(entry.net)) {
      forgetFocused = false
      return
    }
    forgetFocused = direction > 0
  }

  // ----- open / close ----------------------------------------------------------------

  function open() {
    service.opened = true
    forgetFocused = false
    refresh(true)
    return "opened"
  }

  function close() {
    service.opened = false
    cancelPasswordPrompt()
    scanRestart.stop()
    scanDone.stop()
    // Reset sampling so the next open doesn't compute a fake rate from a
    // sample taken minutes ago.
    prevSampleTime = 0
    downloadRate = 0
    uploadRate = 0
    pingIface = ""
    routerPingSamples = []
    internetPingSamples = []
    routerPingLatency = -1
    internetPingLatency = -1
    internetPingPacketLoss = 0
    setScannerEnabled(false)
    wifiNetworks = []
    cursorRows = []
    return "closed"
  }

  function toggle() {
    return service.opened ? close() : open()
  }

  onCanToggleWifiChanged: rebuildRows()
  onWifiDeviceChanged: {
    if (opened && wifiDevice) setScannerEnabled(true)
    // Turning the radio off can drop the device entirely; a scan armed
    // against it would otherwise read "SCANNING WI-FI…" forever.
    if (!wifiDevice) scanning = false
    syncWifiNetworks()
  }
  onWifiNetworkObjectsChanged: syncWifiNetworks()
  onOpenedChanged: if (opened) rebuildRows()

  Component.onCompleted: refresh()

  // ----- IPC -------------------------------------------------------------------------
  // Driven by keybinds and scripts: `qs ipc call network toggle`.

  IpcHandler {
    target: "network"

    function toggle(): string {
      return service.toggle()
    }

    function open(): string {
      return service.open()
    }

    function close(): string {
      return service.close()
    }

    function toggleWifi(): string {
      return service.toggleNetwork()
    }

    function status(): string {
      return JSON.stringify({
        opened: service.opened,
        backend: service.networkManagerAvailable ? "networkmanager" : "none",
        kind: service.kind,
        wifiEnabled: Networking.wifiEnabled,
        ssid: service.connectedWifiNetwork ? service.connectedWifiNetwork.name : "",
        iface: service.info.iface || "",
        ip: service.info.ip || "",
        gateway: service.info.gateway || "",
        networks: service.wifiNetworks.length
      })
    }

    function ping(): string {
      return "ok"
    }
  }

  // ----- the overlay -------------------------------------------------------------------
  //
  // Same surface recipe as the launcher, session menu, and audio panel:
  // full-screen transparent layer on the focused Hyprland monitor, scrim
  // closes, card holds the rows, and the layer takes exclusive keyboard
  // focus while visible — the card itself (there is no text field to
  // borrow it from, except while the passphrase prompt is open).

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
    WlrLayershell.namespace: "mike-network"
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
        // While the passphrase prompt is open its TextInput owns input;
        // keys it ignores must not move the ladder behind it. Its own
        // handlers take Escape/Enter before events bubble this far.
        if (service.passwordSsid !== "") {
          if (event.key === Qt.Key_Escape) {
            service.cancelPasswordPrompt()
            event.accepted = true
          }
          return
        }
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
            service.forgetFocused = false
            event.accepted = true
            break
          case Qt.Key_End:
            service.selectedIndex = service.lastSelectable()
            service.forgetFocused = false
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
            readonly property var net: modelData.net || null
            readonly property bool selectable: service.rowSelectable(modelData)
            readonly property bool current: row.selectable && row.index === service.selectedIndex

            // ----- network-row specifics ------------------------------

            readonly property bool isConnected: !!(row.net && row.net.connected)
            readonly property bool needsCredentials: row.net ? service.requiresCredentials(row.net.security) : false
            readonly property bool isEnterprise: row.net ? service.isEnterpriseSecurity(row.net.security) : false
            readonly property bool canForget: service.canForgetNetwork(row.net)
            readonly property bool rowForgetFocused: row.current && service.forgetFocused && row.canForget
            // Gate on the matching *Kind/*Ssid being live so a hidden-SSID
            // row (ssid == "") doesn't collide with the "" defaults.
            readonly property bool isBusy: service.actionKind !== "" && service.actionSsid === (row.net ? row.net.ssid : "")
            readonly property bool isFailed: service.failureReason !== "" && service.failureSsid === (row.net ? row.net.ssid : "")
            readonly property bool isPasswordOpen: service.passwordSsid !== "" && service.passwordSsid === (row.net ? row.net.ssid : "")
            readonly property bool forgetVisible: canForget
              && (!needsCredentials || rowForgetFocused || netMouse.containsMouse || forgetMouse.containsMouse)

            readonly property string statusText: {
              if (!row.net || row.isPasswordOpen) return ""
              if (row.isBusy) {
                if (service.actionKind === "connect") return "Connecting…"
                if (service.actionKind === "disconnect") return "Disconnecting…"
                return "Forgetting…"
              }
              if (row.isFailed) return service.failureReason || "Failed"
              if (row.isConnected) return "Connected"
              return ""
            }

            readonly property color statusColor: {
              if (row.isFailed) return service.urgent
              if (row.isBusy || row.isConnected) return row.current ? "#101014" : service.foreground
              return row.current ? "#80101014" : service.foreground
            }

            width: cardColumn.width
            height: kind === "header" || kind === "hint" ? service.headerHeight
              : kind === "hero" ? service.heroHeight
              : kind === "stats" ? service.statsHeight
              : service.rowHeight
                + (row.statusText !== "" ? service.statusExtraHeight : 0)
                + (row.isPasswordOpen ? passwordPanel.implicitHeight + 8 : 0)
            radius: 6
            color: "transparent"

            // Failure reasons land on the WifiNetwork object this row's
            // SSID resolves to right now; background auto-connect retries
            // fire it too, so only reprompt for connects this panel
            // started.
            Connections {
              target: row.net ? service.networkForSsid(row.net.ssid) : null

              function onConnectionFailed(reason) {
                if (!row.net) return
                var ours = service.actionKind === "connect" && service.actionSsid === row.net.ssid
                service.failNetworkAction(service.networkForSsid(row.net.ssid), reason)
                if (ours && Model.shouldRepromptPassphrase(reason, row.needsCredentials, service.connectionFailReasons))
                  service.openPasswordPrompt(row.net.ssid)
              }
              function onConnectedChanged() {
                if (row.net) service.checkActionCompletion(service.networkForSsid(row.net.ssid))
              }
              function onKnownChanged() {
                if (row.net) service.checkActionCompletion(service.networkForSsid(row.net.ssid))
              }
              function onStateChangingChanged() {
                if (row.net) service.checkActionCompletion(service.networkForSsid(row.net.ssid))
              }
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

            // ----- the connection hero -----------------------------------
            //
            // Icon + name + meta line, with the radio switch beside it.
            // Selection outlines it (a fill would fight the switch).

            Rectangle {
              visible: row.kind === "hero"
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: service.heroHeight
              radius: 6
              color: heroMouse.containsMouse ? "#1affffff" : "transparent"
              border.width: row.current ? 1 : 0
              border.color: service.accent

              Text {
                id: heroIcon

                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: service.icon
                color: service.foreground
                opacity: service.networkManagerAvailable ? 1 : 0.5
                font.family: service.fontFamily
                font.pixelSize: 22
              }

              Column {
                anchors.left: heroIcon.right
                anchors.leftMargin: 12
                anchors.right: heroSwitch.visible ? heroSwitch.left : parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                  width: parent.width

                  readonly property string title: {
                    if (service.info.type === "wifi") return service.info.ssid || "Wi-Fi"
                    if (service.info.type === "ethernet") return "Ethernet"
                    return service.kind === "disconnected" ? "Disconnected" : "No connection"
                  }
                  readonly property string detail: Model.headerDetail(service.info)

                  text: detail !== "" ? title + " (" + detail + ")" : title
                  color: service.foreground
                  font.family: service.fontFamily
                  font.pixelSize: 14
                  font.weight: Font.Bold
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: text !== ""

                  // The wifi meta carries the live band ("CONNECTED ·
                  // 5GHZ"); ethernet needs no qualifier.
                  text: {
                    if (service.kind === "disconnected") return "NOT CONNECTED"
                    if (service.info.type === "wifi") {
                      var band = Model.formatHeaderFreq(service.info.freq)
                      return band !== "" ? "CONNECTED · " + band.toUpperCase() : "CONNECTED"
                    }
                    return "CONNECTED"
                  }
                  color: service.foreground
                  opacity: 0.55
                  font.family: service.fontFamily
                  font.pixelSize: 10
                  font.bold: true
                  font.letterSpacing: 1.2
                  elide: Text.ElideRight
                }
              }

              ToggleSwitch {
                id: heroSwitch

                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: service.canToggleWifi
                checked: Networking.wifiEnabled
                onToggled: service.toggleNetwork()
              }

              MouseArea {
                id: heroMouse

                anchors.fill: parent
                visible: row.kind === "hero"
                enabled: row.selectable
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) service.selectedIndex = row.index
                onClicked: {
                  service.selectedIndex = row.index
                  service.forgetFocused = false
                  service.activateRow(row.index)
                }
              }
            }

            // ----- the stats grid ------------------------------------------
            //
            // Four mounted label/value lines: ping, transfer, totals, and
            // the route's address/gateway (values copy on click). Cells
            // read "--" until a sample lands rather than reflowing in.

            Column {
              visible: row.kind === "stats"
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              anchors.topMargin: 6
              spacing: 3

              Row {
                spacing: 6

                StatLabel { text: "Ping" }
                StatValue {
                  text: service.formatPingLatency(service.internetPingLatency)
                  color: service.internetPingPacketLoss > 0 ? service.urgent : service.foreground
                }
                StatLabel { text: "Packet Loss" }
                StatValue {
                  text: service.formatPacketLoss(service.internetPingPacketLoss)
                  color: service.internetPingPacketLoss > 0 ? service.urgent : service.foreground
                }
              }

              Row {
                spacing: 6

                StatLabel { text: "Receiving" }
                StatValue { text: service.hasTransferStats ? service.formatRate(service.downloadRate) : "--" }
                StatLabel { text: "Sending" }
                StatValue { text: service.hasTransferStats ? service.formatRate(service.uploadRate) : "--" }
              }

              Row {
                spacing: 6

                StatLabel { text: "Downloaded" }
                StatValue { text: service.hasTransferStats ? service.formatBytes(parseFloat(service.info.rx_bytes || "0")) : "--" }
                StatLabel { text: "Uploaded" }
                StatValue { text: service.hasTransferStats ? service.formatBytes(parseFloat(service.info.tx_bytes || "0")) : "--" }
              }

              Row {
                spacing: 6

                StatLabel { text: "IP Address" }
                StatValue {
                  text: service.info.ip || "--"
                  copyable: !!service.info.ip
                }
                StatLabel { text: "Gateway" }
                StatValue {
                  text: service.info.gateway || "--"
                  copyable: !!service.info.gateway
                }
              }
            }

            // ----- network rows -----------------------------------------------

            Rectangle {
              id: body

              visible: row.kind === "network"
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: service.rowHeight + (row.statusText !== "" ? service.statusExtraHeight : 0)
              radius: 6
              color: row.current ? service.accent : netMouse.containsMouse ? "#1affffff" : "transparent"

              Text {
                id: signalGlyph

                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: service.wifiIconFor(row.net ? row.net.signal : 0)
                color: row.statusColor
                font.family: service.fontFamily
                font.pixelSize: 15
              }

              Column {
                anchors.left: signalGlyph.right
                anchors.leftMargin: 10
                anchors.right: rightAction.visible ? rightAction.left : parent.right
                anchors.rightMargin: rightAction.visible ? 6 : 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                  width: parent.width
                  text: row.net ? (row.net.ssid || "Hidden") : ""
                  color: row.current ? "#101014" : service.foreground
                  font.family: service.fontFamily
                  font.pixelSize: 12
                  font.weight: row.isConnected ? Font.Bold : Font.Normal
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: row.statusText !== ""
                  height: visible ? implicitHeight : 0
                  text: row.statusText
                  color: row.statusColor
                  opacity: row.isFailed || row.isBusy || row.isConnected ? 1 : 0.6
                  font.family: service.fontFamily
                  font.pixelSize: 10
                  elide: Text.ElideRight
                }
              }

              // The right edge: a lock for networks that need credentials,
              // swapping to Forget on hover or keyboard focus.
              Item {
                id: rightAction

                visible: row.needsCredentials || row.canForget
                width: 22
                height: 22
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  anchors.centerIn: parent
                  text: row.forgetVisible ? "󰅙" : "󰌾"
                  color: row.forgetVisible
                    ? (row.rowForgetFocused ? "#101014" : service.urgent)
                    : (row.current ? "#80101014" : service.foreground)
                  opacity: row.forgetVisible ? 1 : 0.55
                  font.family: service.fontFamily
                  font.pixelSize: 13
                }

                Rectangle {
                  anchors.fill: parent
                  radius: 5
                  color: "#33ff6e6e"
                  visible: row.rowForgetFocused
                }

                MouseArea {
                  id: forgetMouse

                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: row.canForget && !service.busy
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: {
                    service.selectedIndex = row.index
                    service.forgetFocused = true
                    if (row.net) service.forget(row.net)
                  }
                }
              }

              MouseArea {
                id: netMouse

                anchors.fill: parent
                anchors.rightMargin: rightAction.visible ? rightAction.width + 4 : 0
                hoverEnabled: true
                enabled: !service.busy
                cursorShape: Qt.PointingHandCursor

                // Hover selects; the ladder's single-cursor convention.
                onContainsMouseChanged: if (containsMouse && row.selectable) {
                  service.selectedIndex = row.index
                  service.forgetFocused = false
                }

                onClicked: {
                  if (!row.net) return
                  service.selectedIndex = row.index
                  service.forgetFocused = false
                  service.activateRow(row.index)
                }
              }
            }

            // ----- the inline passphrase prompt ---------------------------------
            //
            // Expanded under its network row: an identity field for
            // 802.1X, the passphrase, and a connect button; while the
            // connect is busy (or failed) a status box takes their place.
            // Typed text lives on the service so scan refreshes can't
            // eat it.

            Item {
              id: passwordPanel

              visible: row.isPasswordOpen
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: body.bottom
              anchors.topMargin: 8
              implicitHeight: visible ? promptColumn.implicitHeight : 0
              height: implicitHeight

              Column {
                id: promptColumn

                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 6

                InputField {
                  id: identityField

                  visible: row.isEnterprise && !row.isBusy && !row.isFailed
                  width: parent.width
                  placeholderText: "Identity (user@domain)"
                  inputText: row.isPasswordOpen ? service.identityText : ""

                  onAccepted: passphraseField.forceActiveFocus()
                  onInputTextChanged: if (row.isPasswordOpen && inputText !== service.identityText) service.identityText = inputText
                  onEscapePressed: service.cancelPasswordPrompt()

                  onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
                  Component.onCompleted: if (visible) Qt.callLater(forceActiveFocus)
                }

                Item {
                  visible: !row.isBusy && !row.isFailed
                  width: parent.width
                  height: 30
                  implicitHeight: 30

                  InputField {
                    id: passphraseField

                    anchors.left: parent.left
                    anchors.right: connectButton.left
                    anchors.rightMargin: 6
                    password: true
                    placeholderText: "Passphrase"
                    inputText: row.isPasswordOpen ? service.passwordText : ""

                    onAccepted: service.submitPassphrase()
                    onInputTextChanged: if (row.isPasswordOpen && inputText !== service.passwordText) service.passwordText = inputText
                    onEscapePressed: service.cancelPasswordPrompt()

                    onVisibleChanged: if (visible && !row.isEnterprise) Qt.callLater(forceActiveFocus)
                    Component.onCompleted: if (visible && !row.isEnterprise) Qt.callLater(forceActiveFocus)
                  }

                  PromptButton {
                    id: connectButton

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰄬"
                    enabled: passphraseField.inputText.length > 0
                      && (!row.isEnterprise || identityField.inputText.length > 0)
                    onTriggered: service.submitPassphrase()
                  }
                }

                Rectangle {
                  visible: row.isBusy || row.isFailed
                  width: parent.width
                  height: 30
                  radius: 6
                  color: "#22000000"
                  border.width: 1
                  border.color: row.isFailed ? "#4dff6e6e" : "#26ffffff"

                  Text {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: row.isFailed ? (service.failureReason || "Failed") : "Connecting…"
                    color: row.isFailed ? service.urgent : service.foreground
                    font.family: service.fontFamily
                    font.pixelSize: 12
                  }
                }
              }

              // A wrong password shows its reason, then hands the inputs
              // back (with the previous passphrase still in place) for
              // another try.
              Timer {
                id: failureTimer

                interval: 2000
                running: row.isFailed && row.isPasswordOpen
                onTriggered: {
                  service.failureSsid = ""
                  service.failureReason = ""
                  if (row.isEnterprise) Qt.callLater(identityField.forceActiveFocus)
                  else Qt.callLater(passphraseField.forceActiveFocus)
                }
              }
            }
          }
        }

        // ----- footer ---------------------------------------------------------

        Item {
          width: parent.width
          height: 24

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "return select · ←→ forget · esc close"
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

  // The radio switch: track fills with the accent when on; Enter on the
  // hero and clicks on the switch both toggle.
  component ToggleSwitch: Rectangle {
    id: toggle

    property bool checked: false
    signal toggled()

    width: 40
    height: 20
    radius: 10
    color: checked ? service.accent : "#33ffffff"

    Rectangle {
      width: 14
      height: 14
      radius: 7
      anchors.verticalCenter: parent.verticalCenter
      x: toggle.checked ? toggle.width - width - 3 : 3
      color: toggle.checked ? "#101014" : service.foreground

      Behavior on x {
        NumberAnimation {
          duration: 120
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: toggle.toggled()
    }
  }

  // One stats-grid label.
  component StatLabel: Text {
    width: 96
    height: 16
    verticalAlignment: Text.AlignVCenter
    color: service.foreground
    opacity: 0.45
    font.family: service.fontFamily
    font.pixelSize: 11
  }

  // One stats-grid value; copyable values show a pointing cursor and copy
  // through wl-copy on click.
  component StatValue: Text {
    id: value

    property bool copyable: false

    width: 103
    height: 16
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignRight
    color: service.foreground
    font.family: service.fontFamily
    font.pixelSize: 11

    MouseArea {
      anchors.fill: parent
      enabled: value.copyable && value.text !== "" && value.text !== "--"
      hoverEnabled: enabled
      cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: service.copyToClipboard(value.text)
    }
  }

  // The passphrase prompt's input: bordered field that highlights with
  // the accent while focused. Escape cancels the whole prompt.
  component InputField: Rectangle {
    id: field

    property string placeholderText: ""
    property bool password: false
    property alias inputText: input.text
    signal accepted()
    signal escapePressed()

    radius: 6
    color: "#22000000"
    border.width: 1
    border.color: input.activeFocus ? service.accent : "#26ffffff"
    height: 30

    TextInput {
      id: input

      anchors.fill: parent
      anchors.leftMargin: 10
      anchors.rightMargin: 10
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      color: service.foreground
      selectionColor: service.accent
      selectedTextColor: "#101014"
      font.family: service.fontFamily
      font.pixelSize: 12
      echoMode: field.password ? TextInput.Password : TextInput.Normal

      onAccepted: field.accepted()
      Keys.onEscapePressed: field.escapePressed()

      // The field is a click target too, not just a label background.
      MouseArea {
        anchors.fill: parent
        onClicked: input.forceActiveFocus()
      }
      Text {
        visible: input.text === "" && !input.activeFocus
        text: field.placeholderText
        color: service.foreground
        opacity: 0.35
        font.family: service.fontFamily
        font.pixelSize: 12
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  // The passphrase prompt's connect button: glyph, hover fill, disabled
  // dim.
  component PromptButton: Rectangle {
    id: button

    property string glyph: ""
    property bool enabled: true
    signal triggered()

    width: 30
    height: 30
    radius: 6
    color: buttonMouse.containsMouse ? "#1affffff" : "transparent"
    opacity: button.enabled ? 1 : 0.35

    Text {
      anchors.centerIn: parent
      text: button.glyph
      color: service.foreground
      font.family: service.fontFamily
      font.pixelSize: 14
    }

    MouseArea {
      id: buttonMouse

      anchors.fill: parent
      hoverEnabled: true
      cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (button.enabled) button.triggered()
    }
  }
}
