.pragma library

function showable(client) {
  if (!client || client.mapped !== true) return false
  if (onShelf(client)) return false
  if (client.hidden === true || client.visible !== true) return false
  var size = client.size
  if (!size || size.length < 2) return false
  if (size[0] < 64 || size[1] < 40) return false
  return true
}

// A minimized window lives on a special workspace. It stays mapped, so the
// corner buttons must not follow it; a shelf chip opens it instead.
function onShelf(client) {
  var name = workspaceName(client, true)
  return !!(client && client.mapped === true && name.indexOf("special:") === 0)
}

function workspaceName(client, allowSpecial) {
  var ws = client && client.workspace
  var name = typeof ws === "string" ? ws : (ws && ws.name)
  if (typeof name !== "string") return ""
  if (!/^[A-Za-z0-9:._-]+$/.test(name)) return ""
  if (!allowSpecial && name.indexOf("special:") === 0) return ""
  return name
}

// Hyprland assigns these. Anything else must not be pasted into a dispatch.
function safeAddress(address) {
  if (typeof address !== "string") return ""
  if (!/^0x[0-9a-fA-F]+$/.test(address)) return ""
  return address
}

function windowLabel(client) {
  var title = client && client.title ? String(client.title).replace(/\s+/g, " ").trim() : ""
  var klass = client && client.class ? String(client.class).trim() : ""
  return title || klass || "Window"
}

// Screen-local top-left of the corner control.
// Hyprland `at`/`size` and the Quickshell screen can differ by monitor scale.
function chromeTopLeft(client, monitor, screen, chromeW, inset) {
  var at = client && client.at
  var size = client && client.size
  if (!at || !size || !monitor || !screen) return null
  var scale = 1
  if (screen.width > 0 && monitor.width > 0) scale = monitor.width / screen.width
  if (!isFinite(scale) || scale <= 0) scale = 1
  var localX = (at[0] - monitor.x) / scale
  var localY = (at[1] - monitor.y) / scale
  var w = size[0] / scale
  return {
    x: clamp(Math.round(localX + w - chromeW - inset), chromeW, screen.width),
    y: clamp(Math.round(localY + inset), 24, screen.height),
    scale: scale
  }
}

function clamp(value, span, limit) {
  if (!limit || limit <= 0) return value
  if (value < 0) return 0
  if (value + span > limit) return Math.round(limit - span)
  return value
}

// Bottom-right resize handle, in screen pixels. Kept on the monitor so a
// window that hangs off the right edge can still be resized.
function resizeHandle(client, monitor, screen, grip) {
  var at = client && client.at
  var size = client && client.size
  if (!at || !size || !monitor || !screen) return null
  var scale = 1
  if (screen.width > 0 && monitor.width > 0) scale = monitor.width / screen.width
  if (!isFinite(scale) || scale <= 0) scale = 1
  var g = grip > 0 ? grip : 18
  var localX = (at[0] - monitor.x) / scale
  var localY = (at[1] - monitor.y) / scale
  return {
    x: clamp(Math.round(localX + size[0] / scale - g), g, screen.width),
    y: clamp(Math.round(localY + size[1] / scale - g), g, screen.height),
    w: g,
    h: g,
    scale: scale
  }
}

// Where a window lands when the pointer is released near a screen edge.
// Corners take a quarter, the sides take a half, the top takes the work area.
// reserved is [left, top, right, bottom]. Bottom edge alone does not snap.
function snapRect(cursorX, cursorY, monitor, threshold, gap) {
  if (!monitor || !monitor.reserved || monitor.reserved.length < 4) return null
  var edge = threshold > 0 ? threshold : 28
  var margin = gap > 0 ? gap : 10
  var left = monitor.x + monitor.reserved[0]
  var top = monitor.y + monitor.reserved[1]
  var right = monitor.x + monitor.width - monitor.reserved[2]
  var bottom = monitor.y + monitor.height - monitor.reserved[3]
  var x = left + margin
  var y = top + margin
  var w = right - left - margin * 2
  var h = bottom - top - margin * 2
  if (w < 64 || h < 40) return null
  var nearL = cursorX - left <= edge
  var nearR = right - cursorX <= edge
  var nearT = cursorY - top <= edge
  var nearB = bottom - cursorY <= edge
  var halfW = Math.round(w / 2)
  var halfH = Math.round(h / 2)
  if (nearT && nearL) return { x: x, y: y, w: halfW, h: halfH }
  if (nearT && nearR) return { x: x + w - halfW, y: y, w: halfW, h: halfH }
  if (nearB && nearL) return { x: x, y: y + h - halfH, w: halfW, h: halfH }
  if (nearB && nearR) return { x: x + w - halfW, y: y + h - halfH, w: halfW, h: halfH }
  if (nearT) return { x: x, y: y, w: w, h: h }
  if (nearL) return { x: x, y: y, w: halfW, h: h }
  if (nearR) return { x: x + w - halfW, y: y, w: halfW, h: h }
  return null
}
