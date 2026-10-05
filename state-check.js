const fs = require("fs")
const path = require("path")
const assert = require("assert")

function loadLibrary(file, imports = {}) {
  const source = fs.readFileSync(path.join(__dirname, file), "utf8")
    .replace(/^\.(?:pragma|import)[^\n]*\n/gm, "")
  const names = [...source.matchAll(/^function\s+(\w+)\s*\(/gm)].map(match => match[1])
  return new Function(...Object.keys(imports), source + "\nreturn {" + names.join(",") + "}")(...Object.values(imports))
}

const Controls = loadLibrary("Controls.js")
const State = loadLibrary("State.js", { Controls })
const monitor = {
  id: 0, name: "eDP-1", x: 0, y: 0, width: 1920, height: 1080,
  scale: 1.5, transform: 0, reserved: [0, 24, 0, 0], activeWorkspace: { name: "2" }
}
const screen = { name: "eDP-1", width: 1280, height: 720 }

function client(index, overrides = {}) {
  return Object.assign({
    address: "0x" + index.toString(16), pid: 2000 + index,
    stableId: "native-" + index,
    class: "editor", initialClass: "editor", title: "Window " + index,
    mapped: true, hidden: false, visible: true, monitor: 0,
    workspace: { name: "1" }, at: [100, 100], size: [600, 300],
    floating: false, fullscreen: 0, focusHistoryID: index
  }, overrides)
}

function snapshot(clients, monitors = [monitor]) { return { clients, monitors } }
function build(clients, homes = {}, options = {}, monitors = [monitor], screens = [screen]) {
  return State.buildSnapshot(snapshot(clients, monitors), screens, homes, options)
}

// One JSON envelope makes application titles independent of protocol framing.
const titled = client(1, { title: "Editor ---MON--- notes" })
const framed = JSON.stringify(snapshot([titled]))
const parsed = State.parseSnapshot(framed)
assert.strictEqual(parsed.clients[0].title, titled.title)
assert.strictEqual(State.buildSnapshot(framed, [screen], {}, {}).rows[0].title, titled.title)
assert.throws(() => State.parseSnapshot("[{}]---MON---[]"))
assert.throws(() => State.buildSnapshot({ clients: {}, monitors: [] }, [screen], {}))
assert.throws(() => State.buildSnapshot("{broken", [screen], {}))
assert.strictEqual(build([client(1, { address: "0x1; dispatch close" })]).rows.length, 0)
assert.strictEqual(build([client(1), client(1)]).rows.length, 1, "duplicate addresses do not create competing controls")

// Snapshot integration must preserve compositor logical geometry.
const geometry = build([client(1)]).rows[0]
assert.strictEqual(geometry.x, 594)
assert.strictEqual(geometry.y, 104)
assert.strictEqual(geometry.handleX, 682)
assert.strictEqual(geometry.handleY, 382)
assert.strictEqual(geometry.scale, 1)
assert.strictEqual(geometry.monitorName, screen.name)
assert.strictEqual(geometry.monW, screen.width)

const wideMonitor = Object.assign({}, monitor, { width: 2400, height: 900, scale: 1, reserved: [0, 0, 0, 0] })
const wideScreen = { name: "eDP-1", width: 2400, height: 900 }
const normalWindows = Array.from({ length: 19 }, (_, index) => client(index + 1, {
  at: [index * 120, 100], size: [116, 160], focusHistoryID: index
}))
const manyNormal = build(normalWindows, {}, {}, [wideMonitor], [wideScreen])
assert.strictEqual(manyNormal.rows.length, 19, "normal controls have no twelve-window limit")
assert.strictEqual(new Set(manyNormal.rows.map(row => row.stableId)).size, 19)

// Every minimized address remains in the model and is reachable through pages.
const narrowMonitor = Object.assign({}, monitor, { width: 480, height: 600, scale: 1, reserved: [0, 24, 0, 36] })
const narrowScreen = { name: "eDP-1", width: 480, height: 600 }
const minimizedWindows = Array.from({ length: 29 }, (_, index) => client(index + 1, {
  visible: false, workspace: { name: "special:li-window-controls" }
}))
const firstPage = build(minimizedWindows, {}, {}, [narrowMonitor], [narrowScreen])
assert.strictEqual(firstPage.minimized.length, 29)
assert.strictEqual(firstPage.rows.length, 0)
assert(firstPage.shelves[screen.name].pages > 1)
assert.strictEqual(firstPage.shelves[screen.name].anchor, "top", "restore shelf defaults below the top bar")
assert.strictEqual(firstPage.minimized[0].y, 32, "top shelf respects the reserved bar and gap")
assert.strictEqual(firstPage.shelves[screen.name].pager.y, 64, "pagination sits directly below top chips")
const reachable = new Set()
for (let page = 0; page < firstPage.shelves[screen.name].pages; page++) {
  const pageState = build(minimizedWindows, {}, { shelfPages: { "eDP-1": page } }, [narrowMonitor], [narrowScreen])
  for (const chip of pageState.minimized.filter(chip => chip.pageVisible)) {
    reachable.add(chip.address)
    assert.strictEqual(chip.shelfPage, page)
    assert(chip.x >= 0 && chip.x + chip.w <= narrowScreen.width)
    assert(chip.y >= 24 && chip.y + chip.h <= narrowScreen.height - 36)
  }
}
assert.strictEqual(reachable.size, minimizedWindows.length)
const topOriginMonitor = Object.assign({}, narrowMonitor, { x: -480, y: -200, reserved: [12, 48, 10, 36] })
const topReserved = build(minimizedWindows, {}, { shelfAnchor: "top", shelfPages: { "eDP-1": 2 } }, [topOriginMonitor], [narrowScreen])
const topPager = topReserved.shelves[screen.name].pager
assert.strictEqual(topReserved.shelves[screen.name].page, 2)
assert.strictEqual(topPager.y, 88, "top pager uses screen-local coordinates on displaced monitors")
assert(topPager.x >= 12 && topPager.x + topPager.w <= narrowScreen.width - 10)
assert(topPager.y >= 48 && topPager.y + topPager.h <= narrowScreen.height - 36)
for (const chip of topReserved.minimized) {
  assert.strictEqual(chip.y, 56, "every shelf page shares the reserved top placement")
  assert(chip.x >= 12 && chip.x + chip.w <= narrowScreen.width - 10)
  assert(chip.y + chip.h <= topPager.y, "top chips and pager do not overlap")
}
const bottomOverride = build(minimizedWindows, {}, { shelfAnchor: "bottom" }, [narrowMonitor], [narrowScreen])
assert.strictEqual(bottomOverride.shelves[screen.name].anchor, "bottom")
assert(bottomOverride.minimized[0].y > narrowScreen.height / 2, "explicit bottom anchor remains available")
const clampedPage = build(minimizedWindows, {}, { shelfPages: { "eDP-1": 999 } }, [narrowMonitor], [narrowScreen])
assert.strictEqual(clampedPage.shelves[screen.name].page, firstPage.shelves[screen.name].pages - 1)
const unnamedMonitor = Object.assign({}, narrowMonitor, { name: "" })
const unnamedScreen = Object.assign({}, narrowScreen, { name: "" })
const unnamedShelf = build(minimizedWindows, {}, {}, [unnamedMonitor], [unnamedScreen])
assert.strictEqual(unnamedShelf.minimized.length, minimizedWindows.length)
assert(unnamedShelf.shelves[""].pages > 1, "offscreen unnamed displays still have paginated shelves")
assert(unnamedShelf.minimized.some(chip => chip.pageVisible))

const scratchpad = client(1, { workspace: { name: "special:scratchpad" } })
const unrelated = client(2, { workspace: { name: "special:notes" }, at: [30, 420] })
assert.strictEqual(build([scratchpad, unrelated]).minimized.length, 0, "special workspaces are not automatically minimized")
assert.strictEqual(build([scratchpad, unrelated]).rows.length, 2, "visible special workspace windows retain controls")

// Persistence records carry process identity and remain valid if class changes.
const original = client(10, { workspace: { name: "dev workspace" }, monitorName: "eDP-1" })
const homes = State.rememberHome({}, original)
assert.strictEqual(State.restoreWorkspace(homes, original, "2"), "dev workspace")
assert.strictEqual(State.restoreWorkspace(homes, Object.assign({}, original, { class: "editor-popup" }), "2"), "dev workspace")
assert.strictEqual(State.restoreWorkspace(homes, Object.assign({}, original, { pid: 9999 }), "2"), "2")
assert.strictEqual(State.restoreWorkspace(homes, Object.assign({}, original, { stableId: "new-native-window" }), "2"), "2", "same application can reuse an address for a different native window")
assert.strictEqual(State.restoreWorkspace(homes, Object.assign({}, original, { initialClass: "browser" }), "2"), "2")
assert.deepStrictEqual(State.readHomes(JSON.stringify(homes)), homes)
assert.deepStrictEqual(State.readHomes(JSON.stringify({ version: 1, homes })), homes)
assert.deepStrictEqual(State.readHomes("malformed"), {})
assert.deepStrictEqual(State.readHomes('{"0xa":"1"}'), {}, "legacy strings lack reusable identity")
assert.deepStrictEqual(State.readHomes(JSON.stringify({ [original.address]: Object.assign({}, homes[original.address], { workspace: "bad\nworkspace" }) })), {})
assert.deepStrictEqual(State.pruneHomes(homes, [original]), homes, "pending minimize retains its original workspace")
assert.deepStrictEqual(State.pruneHomes(homes, [Object.assign({}, original, { pid: 9999 })]), {})
assert.deepStrictEqual(State.pruneHomes(homes, [Object.assign({}, original, { stableId: "new-native-window" })]), {})
assert.strictEqual(State.clientIdentity(build([original]).rows[0]), State.clientIdentity(original), "row identity preserves the native compositor ID")
assert.deepStrictEqual(State.pruneHomes(homes, []), {})
const afterReload = Object.assign({}, original, { visible: false, workspace: { name: "special:li-window-controls" } })
const reloadState = build([afterReload], State.readHomes(JSON.stringify(homes)), {}, [Object.assign({}, monitor, { activeWorkspace: { name: "8" } })])
assert.strictEqual(State.restoreWorkspace(reloadState.homes, afterReload, reloadState.minimized[0].fallback), "dev workspace")
assert.strictEqual(reloadState.minimized[0].fallback, "8")

// Only explicitly adopted scratchpad addresses become legacy minimized items.
const legacy = State.importLegacy({}, [scratchpad, unrelated], [monitor], [scratchpad.address, "0x2; unsafe"])
assert.strictEqual(legacy[scratchpad.address].legacy, true)
assert.strictEqual(State.restoreWorkspace(legacy, scratchpad, "3"), "2")
assert.strictEqual(build([scratchpad, unrelated], legacy).minimized.length, 1)
assert.strictEqual(build([scratchpad, unrelated], legacy).rows.length, 1)
assert.deepStrictEqual(State.importLegacy({}, [scratchpad], [monitor], []), {})
assert.deepStrictEqual(State.importLegacy({}, [scratchpad], [monitor], [unrelated.address]), {})

// Minimized windows from a removed monitor move to a connected shelf instead
// of disappearing; even a temporarily screenless snapshot keeps their entries.
const disconnected = client(3, { monitor: 99, visible: false, workspace: { name: "special:li-window-controls" } })
const fallback = build([disconnected])
assert.strictEqual(fallback.minimized[0].screenName, screen.name)
assert.strictEqual(fallback.minimized[0].fallback, "2")
assert.strictEqual(fallback.minimized[0].pageVisible, true)
assert.strictEqual(build([disconnected], {}, {}, [], []).minimized.length, 1)

// Eligibility covers input masks and rendering together. A front window must
// not expose another window's buttons over its content.
const back = client(1, { at: [50, 50], size: [600, 400], focusHistoryID: 2 })
const front = client(2, { at: [500, 50], size: [200, 200], floating: true, focusHistoryID: 0 })
const overlapping = build([back, front], {}, { focusedAddress: front.address })
assert.strictEqual(overlapping.rows.find(row => row.address === back.address).chromeVisible, false)
assert.strictEqual(overlapping.rows.find(row => row.address === back.address).handleVisible, true)
assert.strictEqual(overlapping.rows.find(row => row.address === front.address).chromeVisible, true)
const fullscreen = client(3, { at: [0, 0], size: [1280, 720], fullscreen: 2, focusHistoryID: 0 })
const fullState = build([back, fullscreen], {}, { focusedAddress: fullscreen.address })
assert.strictEqual(fullState.rows.find(row => row.address === back.address).chromeVisible, false)
assert.strictEqual(fullState.rows.find(row => row.address === back.address).handleVisible, false)
assert.strictEqual(fullState.rows.find(row => row.address === fullscreen.address).chromeVisible, true)
const secondMonitor = Object.assign({}, monitor, { id: 1, name: "HDMI-A-1", x: 1280, width: 1280, height: 720, scale: 1 })
const secondScreen = { name: "HDMI-A-1", width: 1280, height: 720 }
const remote = client(4, { monitor: 1, at: [1400, 100] })
const independent = build([fullscreen, remote], {}, { focusedAddress: fullscreen.address }, [monitor, secondMonitor], [screen, secondScreen])
assert.strictEqual(independent.rows.find(row => row.address === remote.address).chromeVisible, true)

// The status bar lists all mapped normal windows on each monitor, independent
// of visibility, overlay geometry, focus order, or the minimize shelf.
const barVisible = client(30)
const barInactive = client(31, { monitor: 1, at: [1400, 100], visible: false, hidden: true, workspace: { name: "8" } })
const barTiny = client(32, { size: [20, 10] })
const barMinimized = client(33, { monitor: 1, visible: false, workspace: { name: "special:li-window-controls" } })
const barLegacy = client(34, { visible: false, workspace: { name: "special:scratchpad" } })
const barSpecial = client(35, { workspace: { name: "special:notes" } })
const barUnmapped = client(36, { mapped: false })
const barDisconnected = client(37, { monitor: 99, visible: false, hidden: true, workspace: { name: "9" } })
const barClients = [barSpecial, barMinimized, barInactive, barUnmapped, barVisible, barTiny, barLegacy, barDisconnected]
const barMonitors = [monitor, secondMonitor]
const barScreens = [screen, secondScreen]
const barHomes = State.importLegacy({}, barClients, barMonitors, [barLegacy.address])
const allWindows = build(barClients, barHomes, { focusedAddress: barVisible.address }, barMonitors, barScreens)
assert(Array.isArray(allWindows.windows), "status bar requires an independent all-window model")
assert.deepStrictEqual(allWindows.windows.map(window => window.address), ["0x1f", "0x21", "0x1e", "0x20", "0x22", "0x25"])
assert.strictEqual(allWindows.windows.find(window => window.address === barInactive.address).screenName, secondScreen.name)
assert.strictEqual(allWindows.windows.find(window => window.address === barInactive.address).workspace, "8")
assert.strictEqual(allWindows.rows.some(row => row.address === barInactive.address || row.address === barTiny.address), false,
  "inactive and tiny windows appear in the bar without gaining corner overlays")
assert.strictEqual(allWindows.windows.find(window => window.address === barMinimized.address).minimized, true)
assert.strictEqual(allWindows.windows.find(window => window.address === barLegacy.address).minimized, true)
assert.strictEqual(allWindows.windows.find(window => window.address === barVisible.address).minimized, false)
assert.strictEqual(allWindows.minimized.length, 2, "all-window model does not replace the minimized overlay model")
assert.strictEqual(allWindows.windows.find(window => window.address === barDisconnected.address).screenName, screen.name)
assert.strictEqual(allWindows.windows.find(window => window.address === barDisconnected.address).fallback, "2")
for (const window of allWindows.windows) {
  assert.strictEqual(State.clientIdentity(window), State.clientIdentity(barClients.find(current => current.address === window.address)))
  assert.strictEqual(typeof window.fullscreen, "number")
  assert.strictEqual(typeof window.focused, "boolean")
  assert.strictEqual(window.focused, window.address === barVisible.address)
}
const changedFocus = build(barClients.slice().reverse(), barHomes, { focusedAddress: barInactive.address }, barMonitors, barScreens)
assert.deepStrictEqual(changedFocus.windows.map(window => window.address), allWindows.windows.map(window => window.address),
  "focus and IPC client ordering do not move status bar buttons")
assert.strictEqual(changedFocus.windows.find(window => window.address === barInactive.address).focused, true)
assert.strictEqual(changedFocus.windows.find(window => window.address === barVisible.address).focused, false)
const maximizedBar = build([client(30, { fullscreen: 1 })]).windows[0]
assert.strictEqual(maximizedBar.fullscreen, 1)
assert.strictEqual(build([barMinimized], {}, {}, [], []).windows.length, 1,
  "temporarily screenless snapshots preserve all-window entries")
assert.strictEqual(build([barInactive], {}, {}, [], []).windows.length, 1)
assert.strictEqual(build([barLegacy], {}).windows.length, 0, "unimported scratchpads stay outside the status bar")
const reusedLegacy = Object.assign({}, barLegacy, { stableId: "replacement-native-window" })
assert.strictEqual(build([reusedLegacy], barHomes).windows.length, 0, "a reused special address does not inherit legacy adoption")
const oldBarIdentity = allWindows.windows.find(window => window.address === barVisible.address).stableId
const replacedBar = build([Object.assign({}, barVisible, { stableId: "new-native-window" })]).windows[0]
assert.notStrictEqual(replacedBar.stableId, oldBarIdentity, "address reuse changes the pinned bar target identity")

console.log("State checks passed (snapshot, identity, restore, paging, monitor fallback, occlusion, and all-window bar model)")
