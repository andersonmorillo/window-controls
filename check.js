const fs = require("fs")
const path = require("path")
const assert = require("assert/strict")

const src = fs.readFileSync(path.join(__dirname, "Controls.js"), "utf8").replace(/^\.pragma library\s*/, "")
const api = new Function(src + "\nreturn { showable, chromeTopLeft, snapRect, resizeHandle, onShelf, workspaceName, safeAddress, windowLabel, monitorRect, workArea, monitorAt, parseSnapshot, luaString, shelfLayout }")()

const visible = { mapped: true, hidden: false, visible: true, at: [324, 38], size: [718, 718] }
assert.equal(api.showable(visible), true, "visible mapped window")
assert.equal(api.showable({ ...visible, visible: false }), false, "hidden workspace")
assert.equal(api.showable({ ...visible, workspace: { name: "special:scratchpad" } }), true, "visible unrelated special workspace retains controls")
assert.equal(api.onShelf({ ...visible, workspace: { name: "special:scratchpad" } }), false, "scratchpad is independent of plugin")
assert.equal(api.showable({ ...visible, workspace: { name: "special:li-window-controls" } }), false, "minimized window hides corner controls")
assert.equal(api.onShelf({ ...visible, workspace: { name: "special:li-window-controls" } }), true)
assert.equal(api.onShelf({ ...visible, mapped: false, workspace: { name: "special:li-window-controls" } }), false)
assert.equal(api.showable({ ...visible, size: [20, 20] }), false)
assert.equal(api.showable({ ...visible, size: [NaN, 100] }), false)
assert.equal(api.workspaceName({ workspace: { name: "Work — diseño 東京" } }), "Work — diseño 東京")
assert.equal(api.workspaceName({ workspace: { name: 'Work "quoted" \\ docs' } }), 'Work "quoted" \\ docs')
for (const name of ["", "   ", "bad\nworkspace", "bad\tworkspace", "bad\u0000workspace", "bad\u0085workspace"])
  assert.equal(api.workspaceName({ workspace: name }, true), "", "reject control characters: " + JSON.stringify(name))
assert.equal(api.workspaceName({ workspace: "special:scratchpad" }), "")
assert.equal(api.workspaceName({ workspace: "special:scratchpad" }, true), "special:scratchpad")
assert.equal(api.safeAddress("0x5a5f88b02ce0"), "0x5a5f88b02ce0")
assert.equal(api.safeAddress('0x5a5f88b02ce0" })'), "")
assert.equal(api.windowLabel({ title: " Notes\n文档 ", class: "org.notes" }), "Notes 文档")
assert.equal(api.luaString('Work "quoted" \\ docs'), '"Work \\"quoted\\" \\\\ docs"')
assert.equal(api.luaString("a\n\r\t\u00001\u001f\u007f"), '"a\\n\\r\\t\\0001\\031\\127"')
assert.equal(api.luaString("東京"), '"東京"')
assert.equal(api.luaString(null), '""')

const monitor = { x: 0, y: 0, width: 1366, height: 768, reserved: [0, 24, 0, 0] }
const screen = { width: 1366, height: 768 }
assert.deepEqual(api.monitorRect(monitor), { x: 0, y: 0, w: 1366, h: 768 })
assert.deepEqual(api.workArea(monitor), { x: 0, y: 24, w: 1366, h: 744 })
assert.deepEqual(api.chromeTopLeft(visible, monitor, screen, 76, 4), { x: 962, y: 42, w: 76, h: 24, scale: 1 })

const scaledMonitor = { x: 2560, y: 0, width: 1920, height: 1080, scale: 1.5, reserved: [0, 35, 0, 0] }
const scaledScreen = { width: 1280, height: 720 }
const scaledWindow = { at: [2560, 35], size: [1280, 685] }
assert.deepEqual(api.monitorRect(scaledMonitor), { x: 2560, y: 0, w: 1280, h: 720 })
assert.deepEqual(api.chromeTopLeft(scaledWindow, scaledMonitor, scaledScreen, 102, 4, 24),
  { x: 1174, y: 39, w: 102, h: 24, scale: 1 }, "live 1.5x coordinates remain logical")
assert.deepEqual(api.resizeHandle(scaledWindow, scaledMonitor, scaledScreen, 18),
  { x: 1262, y: 702, w: 18, h: 18, scale: 1 })
const doubleMonitor = { x: -1000, y: -200, width: 2000, height: 1200, scale: 2 }
assert.deepEqual(api.chromeTopLeft({ at: [-900, -180], size: [500, 400] }, doubleMonitor, { width: 1000, height: 600 }, 80, 4),
  { x: 516, y: 24, w: 80, h: 24, scale: 1 }, "2x monitor with negative origin")
const portrait = { x: -720, y: -360, width: 1920, height: 1080, scale: 1.5, transform: 1, reserved: [8, 36, 12, 20] }
assert.deepEqual(api.monitorRect(portrait), { x: -720, y: -360, w: 720, h: 1280 })
assert.deepEqual(api.workArea(portrait), { x: -712, y: -324, w: 700, h: 1224 })
assert.deepEqual(api.monitorRect(portrait, { width: 719, height: 1279 }), { x: -720, y: -360, w: 719, h: 1279 }, "Qt dimensions are authoritative")
for (const transform of [1, 3, 5, 7]) assert.equal(api.monitorRect({ ...portrait, transform }).w, 720)
for (const transform of [0, 2, 4, 6]) assert.equal(api.monitorRect({ ...portrait, transform }).w, 1280)
assert.equal(api.monitorRect({ width: -1, height: 1 }), null)

assert.deepEqual(api.chromeTopLeft({ at: [1000, 36], size: [500, 400] }, monitor, screen, 102, 4),
  { x: 1264, y: 40, w: 102, h: 24, scale: 1 }, "offscreen right edge remains accessible")
assert.deepEqual(api.chromeTopLeft({ at: [10, 10], size: [64, 40] }, monitor, screen, 102, 4),
  { x: 10, y: 14, w: 64, h: 24, scale: 1 }, "chrome shrinks to its window")
assert.deepEqual(api.resizeHandle({ at: [180, 140], size: [400, 280] }, monitor, screen, 18),
  { x: 562, y: 402, w: 18, h: 18, scale: 1 })
assert.equal(api.chromeTopLeft({ at: [-400, 10], size: [200, 100] }, monitor, screen, 102, 4), null)
assert.equal(api.resizeHandle({ at: [1400, 10], size: [200, 100] }, monitor, screen, 18), null)
const tinyScreen = { width: 8, height: 7 }
assert.deepEqual(api.chromeTopLeft({ at: [-2, -2], size: [12, 12] }, monitor, tinyScreen, 102, 4),
  { x: 0, y: 0, w: 8, h: 7, scale: 1 }, "tiny displays never produce negative positions")
assert.deepEqual(api.resizeHandle({ at: [-2, -2], size: [12, 12] }, monitor, tinyScreen, 18),
  { x: 0, y: 0, w: 8, h: 7, scale: 1 })

assert.deepEqual(api.snapRect(5, 30, monitor, 28, 10), { x: 10, y: 34, w: 673, h: 362 })
assert.deepEqual(api.snapRect(1360, 400, monitor, 28, 10), { x: 683, y: 34, w: 673, h: 724 })
assert.deepEqual(api.snapRect(680, 30, monitor, 28, 10), { x: 10, y: 34, w: 1346, h: 724 })
assert.equal(api.snapRect(680, 400, monitor, 28, 10), null)
assert.equal(api.snapRect(680, 767, monitor, 28, 10), null, "bottom edge alone does not snap")
for (const point of [[1700, 400], [-1, 400], [400, -1], [400, 768], [1366, 400], [NaN, 10]])
  assert.equal(api.snapRect(...point, monitor, 28, 10), null, "outside-monitor pointer: " + point)
assert.deepEqual(api.snapRect(2565, 40, scaledMonitor, 28, 10), { x: 2570, y: 45, w: 630, h: 333 }, "snap uses logical scaled work area")
assert.deepEqual(api.snapRect(-715, -355, portrait, 28, 10), { x: -702, y: -314, w: 340, h: 602 }, "portrait snap respects reserved edges")
assert.deepEqual(api.snapRect(680, 25, monitor, 28, 0), { x: 0, y: 24, w: 1366, h: 744 }, "explicit zero gap")
assert.equal(api.monitorAt(2570, 500, [monitor, scaledMonitor]), scaledMonitor, "mixed scale destination monitor")
assert.equal(api.monitorAt(-400, 0, [monitor, scaledMonitor, portrait]), portrait)
assert.equal(api.monitorAt(2000, 500, [monitor, scaledMonitor]), null, "gap between displays")
assert.equal(api.monitorAt(1366, 10, [monitor, { ...monitor, x: 1366 }]).x, 1366, "shared edge chooses destination")
assert.equal(api.monitorAt(3840, 500, [scaledMonitor]), null, "right edge is exclusive")

const delimiterTitle = { clients: [{ title: 'Notes ---MON--- "雪"' }], monitors: [monitor] }
assert.deepEqual(api.parseSnapshot(JSON.stringify(delimiterTitle)), delimiterTitle)
for (const raw of ["not JSON", "{}", "[]", "null", '{"clients":{},"monitors":[]}', '{"clients":[],"monitors":null}'])
  assert.throws(() => api.parseSnapshot(raw), /snapshot/i, "invalid envelope: " + raw)
for (const name of ["clients", "monitors"]) {
  for (const entry of [null, false, 17, "invalid", []]) {
    const malformed = { clients: [], monitors: [] }
    malformed[name] = [{}, entry]
    assert.throws(() => api.parseSnapshot(JSON.stringify(malformed)),
      new RegExp(name + "\\[1\\] must be an object"), "invalid " + name + " entry: " + JSON.stringify(entry))
  }
}
assert.deepEqual(api.parseSnapshot('{"clients":[],"monitors":[]}'), { clients: [], monitors: [] }, "empty current desktop is valid")
for (const activeWindow of [{}, { address: "" }, { address: "0xA012f", title: 'Active "雪"', workspace: { name: "3" } }]) {
  const snapshot = { clients: [], monitors: [], activeWindow }
  assert.deepEqual(api.parseSnapshot(JSON.stringify(snapshot)), snapshot, "valid optional active window stays intact")
}
for (const activeWindow of [null, false, 17, "invalid", []])
  assert.throws(() => api.parseSnapshot(JSON.stringify({ clients: [], monitors: [], activeWindow })),
    /activeWindow.*object/, "invalid active window: " + JSON.stringify(activeWindow))
for (const address of [null, false, 17, {}, [], "a012f", "0x", " 0xa012f", '0xa012f; hl.dsp.exit()'])
  assert.throws(() => api.parseSnapshot(JSON.stringify({ clients: [], monitors: [], activeWindow: { address } })),
    /activeWindow.*address/, "invalid active window address: " + JSON.stringify(address))

function inside(child, area) {
  assert(child.w > 0 && child.h > 0, "positive item size")
  assert(child.x >= area.x && child.y >= area.y && child.x + child.w <= area.x + area.w + 1e-9 && child.y + child.h <= area.y + area.h + 1e-9,
    "item stays within usable screen: " + JSON.stringify({ child, area }))
}
for (const setup of [
  { mon: monitor, screen, count: 37 },
  { mon: { x: -720, y: -360, width: 683, height: 420, reserved: [10, 24, 20, 60] }, screen: { width: 683, height: 420 }, count: 13 },
  { mon: portrait, screen: { width: 720, height: 1280 }, count: 57 },
  { mon: { x: 0, y: 0, width: 9, height: 9, reserved: [1, 1, 1, 1] }, screen: { width: 9, height: 9 }, count: 15 }
]) {
  for (const anchor of ["top", "bottom"]) {
    const first = api.shelfLayout(setup.count, setup.mon, setup.screen, 176, 28, 6, 0, anchor)
    const reached = []
    const globalWork = api.workArea(setup.mon, setup.screen)
    const localWork = { ...globalWork, x: globalWork.x - setup.mon.x, y: globalWork.y - setup.mon.y }
    for (let page = 0; page < first.pages; page++) {
      const layout = api.shelfLayout(setup.count, setup.mon, setup.screen, 176, 28, 6, page, anchor)
      assert.equal(layout.page, page)
      assert.equal(layout.anchor, anchor)
      for (const item of layout.items) { inside(item, layout.area); inside(item, localWork); reached.push(item.index) }
      if (layout.pager) {
        inside(layout.pager, layout.area); inside(layout.pager, localWork)
        assert(layout.pager.y >= layout.items[0].y + layout.items[0].h, anchor + " pager follows chips")
      }
      if (anchor === "top") assert.equal(layout.items[0].y, layout.area.y, "top chips begin below reserved area")
    }
    assert.deepEqual(reached, Array.from({ length: setup.count }, (_, i) => i), "every minimized window is reachable at " + anchor)
    assert.equal(api.shelfLayout(setup.count, setup.mon, setup.screen, 176, 28, 6, 999, anchor).page, first.pages - 1)
    assert.equal(api.shelfLayout(setup.count, setup.mon, setup.screen, 176, 28, 6, -5, anchor).page, 0)
  }
}
assert.deepEqual(api.shelfLayout(0, monitor, screen, 176, 28, 6, 5).items, [])
const topShelf = api.shelfLayout(20, scaledMonitor, scaledScreen, 128, 28, 8, 1, "top")
assert.equal(topShelf.capacity, 9)
assert.equal(topShelf.pages, 3)
assert.deepEqual(topShelf.items.map(item => item.index), [9, 10, 11, 12, 13, 14, 15, 16, 17], "top shelf pagination uses the selected page")
assert.deepEqual(topShelf.items[0], { index: 9, x: 8, y: 43, w: 128, h: 28 }, "top shelf clears the 35px bar and 8px gap on 1.5x display")
assert.deepEqual(topShelf.pager, { x: 8, y: 79, w: 200, h: 24 })
const bottomShelf = api.shelfLayout(20, scaledMonitor, scaledScreen, 128, 28, 8, 1, "bottom")
assert.equal(bottomShelf.items[0].y, 652)
assert.equal(bottomShelf.pager.y, 688)
assert.deepEqual(api.shelfLayout(20, scaledMonitor, scaledScreen, 128, 28, 8, 1), bottomShelf, "omitted anchor preserves bottom layout")
const oneTopChip = api.shelfLayout(1, scaledMonitor, scaledScreen, 128, 28, 8, 0, "top")
assert.equal(oneTopChip.items[0].y, 43)
assert.equal(oneTopChip.pager, null, "unpaginated top shelf uses one row")

console.log("Controls regression checks passed")
