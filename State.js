.pragma library
.import "Controls.js" as Controls

// Snapshot/model construction is kept independent from QML delegates. A bad
// snapshot throws before replacing any live state, so the caller can clear its
// masks and show a useful diagnostic instead of leaving stale click targets.
function parseSnapshot(text) {
  return Controls.parseSnapshot(text)
}

function own(object, key) {
  return !!object && Object.prototype.hasOwnProperty.call(object, key)
}

function clientPid(client) {
  var pid = client && Number(client.pid)
  return isFinite(pid) && pid > 0 && Math.floor(pid) === pid ? pid : 0
}

function identityClass(client) {
  var value = client && (client.initialClass || client.class)
  return typeof value === "string" ? value : ""
}

function normalizedCompositorId(value) {
  if (typeof value === "string") return value
  return typeof value === "number" && isFinite(value) ? String(value) : ""
}

function compositorId(client) {
  if (!client) return ""
  // Raw Hyprland clients call this stableId; our rows use stableId for the
  // complete identity key, so they carry the native value separately.
  return normalizedCompositorId(own(client, "compositorId") ? client.compositorId : client.stableId)
}

function stableId(client) {
  var address = Controls.safeAddress(client && client.address)
  if (!address) return ""
  return JSON.stringify([address, clientPid(client), identityClass(client), compositorId(client)])
}

function clientIdentity(client) {
  return stableId(client)
}

function identityMatches(record, client) {
  return !!record && record.pid === clientPid(client)
    && record.class === identityClass(client)
    && record.compositorId === compositorId(client)
    && record.stableId === stableId(client)
}

function copyHomes(homes) {
  var next = {}
  if (!homes || typeof homes !== "object" || Array.isArray(homes)) return next
  for (var address in homes) {
    if (!own(homes, address) || !Controls.safeAddress(address)) continue
    var record = homes[address]
    if (!record || typeof record !== "object" || Array.isArray(record)) continue
    var workspace = Controls.workspaceName({ workspace: record.workspace }, true)
    var pid = clientPid(record)
    var klass = typeof record.class === "string" ? record.class : ""
    var native = normalizedCompositorId(record.compositorId)
    var expected = stableId({ address: address, pid: pid, class: klass, compositorId: native })
    if (!workspace || workspace === "special:li-window-controls"
        || !pid || typeof record.class !== "string" || record.stableId !== expected) continue
    var clean = { workspace: workspace, pid: pid, class: klass, compositorId: native, stableId: expected }
    if (record.legacy === true) clean.legacy = true
    if (typeof record.monitorName === "string") clean.monitorName = record.monitorName
    if (isFinite(record.monitorId)) clean.monitorId = Number(record.monitorId)
    next[address] = clean
  }
  return next
}

// Only records with an address and process identity can survive a reload.
// Old bare workspace strings cannot safely identify a reused address.
function readHomes(json) {
  var value
  try { value = typeof json === "string" ? JSON.parse(json) : json }
  catch (e) { return {} }
  if (value && value.version === 1 && value.homes) value = value.homes
  return copyHomes(value)
}

function rememberHome(homes, client) {
  var next = copyHomes(homes)
  var address = Controls.safeAddress(client && client.address)
  var workspace = Controls.workspaceName(client, true)
  var pid = clientPid(client)
  if (!address || !workspace || workspace === "special:li-window-controls" || !pid) return next
  var record = {
    workspace: workspace,
    pid: pid,
    class: identityClass(client),
    compositorId: compositorId(client),
    stableId: stableId(client)
  }
  if (typeof client.monitorName === "string") record.monitorName = client.monitorName
  if (isFinite(client.monitor)) record.monitorId = Number(client.monitor)
  next[address] = record
  return next
}

function restoreWorkspace(homes, client, fallback) {
  var address = Controls.safeAddress(client && client.address)
  var record = address && homes && homes[address]
  var workspace = identityMatches(record, client)
    ? Controls.workspaceName({ workspace: record.workspace }, true) : ""
  if (workspace && workspace !== "special:li-window-controls") return workspace
  return Controls.workspaceName({ workspace: fallback })
}

function pruneHomes(homes, clients) {
  clients = Array.isArray(clients) ? clients : []
  var clean = copyHomes(homes)
  var live = {}
  for (var i = 0; i < clients.length; i++) {
    var client = clients[i]
    var address = Controls.safeAddress(client && client.address)
    if (address && client.mapped === true) live[address] = client
  }
  var next = {}
  for (var key in clean) {
    // A record is retained while a minimize dispatch is in flight and the
    // window still occupies its original workspace.
    if (own(clean, key) && live[key] && identityMatches(clean[key], live[key])) next[key] = clean[key]
  }
  return next
}

function monitorFor(client, monitors) {
  for (var i = 0; i < monitors.length; i++) {
    if (monitors[i] && monitors[i].id === client.monitor) return monitors[i]
  }
  return null
}

function importLegacy(homes, clients, monitors, addresses) {
  var next = pruneHomes(homes, clients)
  var requested = {}
  if (!Array.isArray(addresses)) return next
  for (var a = 0; a < addresses.length; a++) {
    var address = Controls.safeAddress(addresses[a])
    if (address) requested[address] = true
  }
  for (var i = 0; i < clients.length; i++) {
    var client = clients[i]
    var key = Controls.safeAddress(client && client.address)
    if (!key || !requested[key] || client.mapped !== true || !clientPid(client)
        || Controls.workspaceName(client, true) !== "special:scratchpad") continue
    var previous = next[key]
    var monitor = monitorFor(client, monitors)
    if (!monitor && monitors.length) monitor = monitors[0]
    var workspace = previous && identityMatches(previous, client) ? previous.workspace
      : Controls.workspaceName({ workspace: monitor && monitor.activeWorkspace })
    if (!workspace) continue
    var record = {
      workspace: workspace,
      pid: clientPid(client),
      class: identityClass(client),
      compositorId: compositorId(client),
      stableId: stableId(client),
      legacy: true
    }
    if (monitor) { record.monitorName = monitor.name; record.monitorId = monitor.id }
    next[key] = record
  }
  return next
}

function isMinimized(client, homes) {
  if (!client || client.mapped !== true) return false
  if (Controls.onShelf(client)) return true
  var record = homes && homes[client.address]
  return Controls.workspaceName(client, true) === "special:scratchpad"
    && !!record && record.legacy === true && identityMatches(record, client)
}

function screenFor(monitor, screens) {
  if (!monitor) return null
  for (var i = 0; i < screens.length; i++) {
    if (screens[i] && screens[i].name === monitor.name) return screens[i]
  }
  return screens.length === 1 ? screens[0] : null
}

function shelfDestination(client, record, monitors, screens) {
  var monitor = monitorFor(client, monitors)
  var screen = screenFor(monitor, screens)
  if (screen) return { monitor: monitor, screen: screen }
  if (record) {
    for (var i = 0; i < monitors.length; i++) {
      var saved = monitors[i]
      if (!saved || (saved.name !== record.monitorName && saved.id !== record.monitorId)) continue
      screen = screenFor(saved, screens)
      if (screen) return { monitor: saved, screen: screen }
    }
  }
  for (var m = 0; m < monitors.length; m++) {
    screen = screenFor(monitors[m], screens)
    if (screen) return { monitor: monitors[m], screen: screen }
  }
  return { monitor: null, screen: screens.length ? screens[0] : null }
}

function clientRect(client) {
  var at = client && client.at
  var size = client && client.size
  if (!Array.isArray(at) || !Array.isArray(size) || at.length < 2 || size.length < 2) return null
  if (!isFinite(at[0]) || !isFinite(at[1]) || !isFinite(size[0]) || !isFinite(size[1])
      || size[0] <= 0 || size[1] <= 0) return null
  return { x: Number(at[0]), y: Number(at[1]), w: Number(size[0]), h: Number(size[1]) }
}

function intersects(a, b) {
  return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
}

// Hyprland does not expose an authoritative stacking list in clients JSON.
// Keep this deliberately conservative: focused windows, fullscreen windows,
// and floating windows can cover background controls; focus history breaks
// remaining ties. Rendering and input masks consume the same eligibility.
function compareFront(a, b, focusedAddress) {
  if (a.address === focusedAddress && b.address !== focusedAddress) return -1
  if (b.address === focusedAddress && a.address !== focusedAddress) return 1
  var fullA = Number(a.fullscreen) > 0, fullB = Number(b.fullscreen) > 0
  if (fullA !== fullB) return fullA ? -1 : 1
  var floatA = a.floating === true, floatB = b.floating === true
  if (floatA !== floatB) return floatA ? -1 : 1
  var historyA = typeof a.focusHistoryID === "number" && a.focusHistoryID >= 0 ? a.focusHistoryID : Infinity
  var historyB = typeof b.focusHistoryID === "number" && b.focusHistoryID >= 0 ? b.focusHistoryID : Infinity
  if (historyA !== historyB) return historyA < historyB ? -1 : 1
  return 0
}

function metadata(client) {
  return {
    address: Controls.safeAddress(client.address),
    class: typeof client.class === "string" ? client.class : "",
    initialClass: identityClass(client),
    title: Controls.windowLabel(client),
    app: Controls.appName(client),
    pid: clientPid(client),
    compositorId: compositorId(client),
    stableId: stableId(client)
  }
}

function positive(value, fallback) {
  return isFinite(value) && Number(value) > 0 ? Number(value) : fallback
}

function buildSnapshot(snapshot, screens, homes, options) {
  if (typeof snapshot === "string") snapshot = parseSnapshot(snapshot)
  if (!snapshot || !Array.isArray(snapshot.clients) || !Array.isArray(snapshot.monitors))
    throw new Error("Expected a snapshot with clients and monitors arrays")
  screens = screens || []
  options = options || {}
  var clients = snapshot.clients
  var monitors = snapshot.monitors
  var kept = pruneHomes(homes, clients)
  var chromeW = positive(options.chromeW, 102), chromeH = positive(options.chromeH, 24)
  var inset = positive(options.inset, 4), grip = positive(options.grip, 18)
  var chipW = positive(options.chipW, 104), chipH = positive(options.chipH, 24)
  var shelfGap = positive(options.shelfGap, 8)
  var shelfAnchor = options.shelfAnchor === "bottom" ? "bottom" : "top"
  var rows = [], windows = [], minimized = [], foreground = [], seen = {}, shelves = Object.create(null)

  for (var c = 0; c < clients.length; c++) {
    var client = clients[c]
    var address = Controls.safeAddress(client && client.address)
    if (!address || seen[address]) continue
    seen[address] = true
    var minimizedClient = isMinimized(client, kept)
    var workspace = Controls.workspaceName(client, true)
    // Bar entries describe every mapped normal window, including inactive
    // workspaces. Corner overlays below retain their own visibility rules.
    if (client.mapped === true && (minimizedClient || workspace.indexOf("special:") !== 0)) {
      var barDestination = shelfDestination(client, kept[address], monitors, screens)
      var window = metadata(client)
      window.screenName = barDestination.screen ? barDestination.screen.name : ""
      window.monitorName = barDestination.monitor ? barDestination.monitor.name : ""
      window.workspace = workspace
      window.minimized = minimizedClient
      window.fullscreen = Number(client.fullscreen) || 0
      window.focused = address === options.focusedAddress
      window.fallback = Controls.workspaceName({ workspace: barDestination.monitor && barDestination.monitor.activeWorkspace })
      windows.push(window)
    }
    if (minimizedClient) {
      var destination = shelfDestination(client, kept[address], monitors, screens)
      var chip = metadata(client)
      chip.screenName = destination.screen ? destination.screen.name : ""
      chip.monitorName = destination.monitor ? destination.monitor.name : ""
      chip.fallback = Controls.workspaceName({ workspace: destination.monitor && destination.monitor.activeWorkspace })
      chip.workspace = Controls.workspaceName(client, true)
      chip.pageVisible = false
      chip.shelfPage = 0
      chip.pageCount = 1
      chip.x = 0; chip.y = 0; chip.w = 0; chip.h = 0
      minimized.push(chip)
      continue
    }
    var rect = clientRect(client)
    if (client.mapped === true && client.visible === true && client.hidden !== true && rect)
      foreground.push({ client: client, rect: rect })
    var monitor = monitorFor(client, monitors)
    var screen = screenFor(monitor, screens)
    if (!screen || !monitor || !Controls.showable(client)) continue
    var place = Controls.chromeTopLeft(client, monitor, screen, chromeW, inset, chromeH)
    var handle = Controls.resizeHandle(client, monitor, screen, grip)
    if (!place || !handle || !rect) continue
    var row = metadata(client)
    row.x = place.x; row.y = place.y; row.w = place.w; row.h = place.h
    row.handleX = handle.x; row.handleY = handle.y; row.handleW = handle.w; row.handleH = handle.h
    row.atX = rect.x; row.atY = rect.y; row.winW = rect.w; row.winH = rect.h
    row.scale = place.scale
    row.fullscreen = Number(client.fullscreen) || 0
    row.floating = client.floating === true
    row.workspace = Controls.workspaceName(client, true)
    row.screenName = screen.name
    row.monitorName = monitor.name; row.monitor = monitor.id
    row.monX = monitor.x; row.monY = monitor.y
    var bounds = Controls.monitorRect(monitor, screen)
    row.monW = bounds.w; row.monH = bounds.h
    row.reserved = monitor.reserved || [0, 0, 0, 0]
    row.chromeVisible = place.w > 0 && place.h > 0
    row.handleVisible = handle.w > 0 && handle.h > 0
    // A resize handle can collide with the buttons in very small windows.
    if (intersects(place, handle)) row.handleVisible = false
    rows.push(row)
  }

  var byAddress = {}
  for (var ci = 0; ci < clients.length; ci++) {
    var current = clients[ci]
    if (current && Controls.safeAddress(current.address) && !own(byAddress, current.address)) byAddress[current.address] = current
  }
  for (var r = 0; r < rows.length; r++) {
    var target = rows[r]
    var source = byAddress[target.address]
    var chrome = { x: target.x + target.monX, y: target.y + target.monY, w: target.w, h: target.h }
    var resize = { x: target.handleX + target.monX, y: target.handleY + target.monY, w: target.handleW, h: target.handleH }
    for (var front = 0; front < foreground.length; front++) {
      var cover = foreground[front]
      if (cover.client.address === target.address || compareFront(cover.client, source, options.focusedAddress) >= 0) continue
      if (intersects(chrome, cover.rect)) target.chromeVisible = false
      if (intersects(resize, cover.rect)) target.handleVisible = false
    }
  }
  rows.sort(function(a, b) {
    if (a.screenName !== b.screenName) return a.screenName < b.screenName ? -1 : 1
    var stacking = compareFront(byAddress[a.address], byAddress[b.address], options.focusedAddress)
    return stacking ? -stacking : (a.address < b.address ? -1 : a.address > b.address ? 1 : 0)
  })
  minimized.sort(function(a, b) { return a.address < b.address ? -1 : a.address > b.address ? 1 : 0 })
  // Focus changes update the highlight without moving a button under a press.
  windows.sort(function(a, b) {
    if (a.screenName !== b.screenName) return a.screenName < b.screenName ? -1 : 1
    return a.address < b.address ? -1 : a.address > b.address ? 1 : 0
  })

  for (var s = 0; s < screens.length; s++) {
    var shelfScreen = screens[s]
    if (!shelfScreen || typeof shelfScreen.name !== "string") continue
    var group = []
    for (var g = 0; g < minimized.length; g++) if (minimized[g].screenName === shelfScreen.name) group.push(minimized[g])
    if (!group.length) continue
    var shelfMonitor = null
    for (var m = 0; m < monitors.length; m++) if (monitors[m] && monitors[m].name === shelfScreen.name) { shelfMonitor = monitors[m]; break }
    if (!shelfMonitor && monitors.length === 1) shelfMonitor = monitors[0]
    var requestedPage = options.shelfPages && options.shelfPages[shelfScreen.name]
    var layout = Controls.shelfLayout(group.length, shelfMonitor, shelfScreen, chipW, chipH, shelfGap, requestedPage, shelfAnchor)
    layout.pageCount = layout.pages
    shelves[shelfScreen.name] = layout
    for (var page = 0; page < layout.pages; page++) {
      var pageLayout = page === layout.page ? layout
        : Controls.shelfLayout(group.length, shelfMonitor, shelfScreen, chipW, chipH, shelfGap, page, shelfAnchor)
      for (var item = 0; item < pageLayout.items.length; item++) {
        var geom = pageLayout.items[item]
        var entry = group[geom.index]
        if (!entry) continue
        entry.x = geom.x; entry.y = geom.y; entry.w = geom.w; entry.h = geom.h
        entry.pageVisible = page === layout.page
        entry.shelfPage = page
        entry.pageCount = layout.pages
      }
    }
  }
  return { rows: rows, windows: windows, minimized: minimized, homes: kept, monitors: monitors, clients: clients, shelves: shelves }
}
