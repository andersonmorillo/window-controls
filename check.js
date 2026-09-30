const fs = require("fs")
const path = require("path")

const src = fs.readFileSync(path.join(__dirname, "Controls.js"), "utf8").replace(/^\.pragma library\s*/, "")
const api = new Function(src + "\nreturn { showable, chromeTopLeft, snapRect, resizeHandle, onShelf, workspaceName, safeAddress, windowLabel }")()

function assert(cond, message) {
  if (!cond) throw new Error(message)
}

assert(api.showable({ mapped: true, hidden: false, visible: true, size: [200, 100] }) === true, "visible window")
assert(api.showable({ mapped: true, hidden: false, visible: false, size: [200, 100] }) === false, "hidden workspace")
assert(api.showable({ mapped: true, hidden: false, visible: true, size: [200, 100], workspace: { name: "special:scratchpad" } }) === false, "shelf window has no corner buttons")
assert(api.onShelf({ mapped: true, workspace: { name: "special:scratchpad" } }) === true, "scratchpad is the shelf")
assert(api.onShelf({ mapped: true, workspace: { name: "5" } }) === false, "normal workspace is not the shelf")
assert(api.workspaceName({ workspace: { name: "5" } }) === "5", "home workspace")
assert(api.workspaceName({ workspace: { name: "special:scratchpad" } }) === "", "shelf is not a home")
assert(api.workspaceName({ workspace: { name: "5\" })" } }) === "", "workspace cannot break out of the command")
assert(api.safeAddress("0x5a5f88b02ce0") === "0x5a5f88b02ce0", "hex window address")
assert(api.safeAddress("0x5a5f88b02ce0\" })") === "", "address cannot break out of the command")
assert(api.windowLabel({ title: "Notes", class: "org.notes" }) === "Notes", "title is the chip label")
assert(api.showable({ mapped: true, hidden: false, visible: true, size: [20, 20] }) === false, "tiny window")

const place = api.chromeTopLeft(
  { at: [324, 38], size: [718, 718] },
  { x: 0, y: 0, width: 1366 },
  { width: 1366 },
  76,
  4
)
assert(place.x === 962 && place.y === 42 && place.scale === 1, "corner on a 1x monitor: " + JSON.stringify(place))

const scaled = api.chromeTopLeft(
  { at: [100, 20], size: [500, 400] },
  { x: 0, y: 0, width: 2000 },
  { width: 1000 },
  80,
  4
)
assert(scaled.x === 216 && scaled.y === 14 && scaled.scale === 2, "corner when hyprland px are 2x screen px: " + JSON.stringify(scaled))

const screen = { x: 0, y: 0, width: 1366, height: 768, reserved: [0, 24, 0, 0] }
const tl = api.snapRect(5, 30, screen, 28, 10)
assert(tl && tl.x === 10 && tl.y === 34 && tl.w === 673 && tl.h === 362, "top-left quarter: " + JSON.stringify(tl))
const right = api.snapRect(1360, 400, screen, 28, 10)
assert(right && right.x === 683 && right.w === 673 && right.h === 724, "right half: " + JSON.stringify(right))
const top = api.snapRect(680, 30, screen, 28, 10)
assert(top && top.w === 1346 && top.h === 724, "top fills the work area: " + JSON.stringify(top))
assert(api.snapRect(680, 400, screen, 28, 10) === null, "middle does not snap")

const hung = api.chromeTopLeft(
  { at: [1000, 36], size: [500, 400] },
  { x: 0, y: 0, width: 1366, height: 768 },
  { width: 1366, height: 768 },
  102,
  4
)
assert(hung.x === 1264, "control stays on a 1366-wide screen: " + JSON.stringify(hung))

const handle = api.resizeHandle(
  { at: [180, 140], size: [400, 280] },
  { x: 0, y: 0, width: 1366, height: 768 },
  { width: 1366, height: 768 },
  18
)
assert(handle.x === 562 && handle.y === 402, "resize handle sits on the bottom-right: " + JSON.stringify(handle))

console.log("ok")
