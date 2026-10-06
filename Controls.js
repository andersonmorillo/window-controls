.pragma library

// Qt tooltip labels accept rich text. Escape the complete string at the sink;
// the fixed wrapper also makes entity-only labels render consistently.
function tooltipText(value) {
  var text = value === undefined || value === null ? "" : String(value)
  return "<qt>" + text.replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;")
    .replace(/\r\n|\r|\n/g, "<br>") + "</qt>"
}

function showable(client) {
  if (!client || client.mapped !== true || onShelf(client)) return false
  if (client.hidden === true || client.visible !== true) return false
  var size = client.size
  return !!(size && size.length >= 2 && finite(size[0]) && finite(size[1]) && size[0] >= 64 && size[1] >= 40)
}

// Only windows minimized by this plugin belong on its shelf. Other special
// workspaces can contain visible windows and must retain their own controls.
function onShelf(client) {
  return !!(client && client.mapped === true && workspaceName(client, true) === "special:li-window-controls")
}

function workspaceName(client, allowSpecial) {
  var ws = client && client.workspace
  var name = typeof ws === "string" ? ws : (ws && ws.name)
  if (typeof name !== "string" || !name.trim()) return ""
  if (/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(name)) return ""
  if (!allowSpecial && name.indexOf("special:") === 0) return ""
  return name
}

// Hyprland assigns these. Anything else must not be pasted into a dispatch.
function safeAddress(address) {
  return typeof address === "string" && /^0x[0-9a-fA-F]+$/.test(address) ? address : ""
}

// Complete Lua string literal, including quotes. Three digit escapes prevent
// a following digit from becoming part of a control character escape.
function luaString(value) {
  var s = value === undefined || value === null ? "" : String(value)
  return '"' + s.replace(/[\\"\u0000-\u001f\u007f]/g, function(ch) {
    if (ch === "\\") return "\\\\"
    if (ch === '"') return '\\"'
    if (ch === "\n") return "\\n"
    if (ch === "\r") return "\\r"
    if (ch === "\t") return "\\t"
    return "\\" + ("000" + ch.charCodeAt(0)).slice(-3)
  }) + '"'
}

function plainLabel(value) {
  return value ? String(value).replace(/\s+/g, " ").trim() : ""
}

function windowLabel(client) {
  return plainLabel(client && client.title) || plainLabel(client && client.class) || "Window"
}

// Bar chips name the application, not the document or task in its title.
function appName(client) {
  var klass = plainLabel(client && (client.initialClass || client.class))
  var initial = plainLabel(client && client.initialTitle)
  var title = plainLabel(client && client.title)
  if (/^(brave|chrome|chromium|google-chrome)-/i.test(klass) || klass.indexOf("__-") >= 0) {
    if (initial && !/[\\/|]/.test(initial) && initial.length <= 48) return initial
    return displayName(klass.replace(/__-.*$/, "").split("-")[0]) || title || "Window"
  }
  return prettyClass(klass) || initial || title || "Window"
}

function prettyClass(klass) {
  var parts = plainLabel(klass).replace(/__-.*$/, "").split(".").filter(Boolean)
  if (!parts.length) return ""
  var dns = { com: 1, org: 1, io: 1, net: 1, app: 1, dev: 1, me: 1, name: 1 }
  var segment = parts.length > 1 && !dns[parts[0].toLowerCase()] ? parts[0] : parts[parts.length - 1]
  return displayName(segment)
}

function displayName(segment) {
  segment = plainLabel(segment).replace(/[-_]+/g, " ")
  if (!segment) return ""
  return segment.charAt(0).toUpperCase() + segment.slice(1)
}

// A single JSON envelope has no separator that can collide with a title.
function parseSnapshot(text) {
  var value
  try {
    value = JSON.parse(text)
  } catch (error) {
    throw new Error("Invalid window snapshot JSON: " + error.message)
  }
  if (!value || typeof value !== "object" || Array.isArray(value))
    throw new Error("Window snapshot must be an object with clients and monitors arrays")
  if (!Array.isArray(value.clients)) throw new Error("Window snapshot clients must be an array")
  if (!Array.isArray(value.monitors)) throw new Error("Window snapshot monitors must be an array")
  var names = ["clients", "monitors"]
  for (var group = 0; group < names.length; group++) {
    var name = names[group]
    var entries = value[name]
    for (var index = 0; index < entries.length; index++) {
      var entry = entries[index]
      if (!entry || typeof entry !== "object" || Array.isArray(entry))
        throw new Error("Window snapshot " + name + "[" + index + "] must be an object")
    }
  }
  if (Object.prototype.hasOwnProperty.call(value, "activeWindow")) {
    var active = value.activeWindow
    if (!active || typeof active !== "object" || Array.isArray(active))
      throw new Error("Window snapshot activeWindow must be an object")
    if (Object.prototype.hasOwnProperty.call(active, "address") &&
        (typeof active.address !== "string" || (active.address !== "" && !safeAddress(active.address))))
      throw new Error("Window snapshot activeWindow address must be empty or a valid window address")
  }
  return value
}

function finite(value) {
  return typeof value === "number" && isFinite(value)
}

function positive(value, fallback) {
  return finite(value) && value > 0 ? value : fallback
}

function nonnegative(value, fallback) {
  return finite(value) && value >= 0 ? value : fallback
}

// Monitor origins, client positions/sizes, cursor positions and Quickshell
// screen dimensions are logical coordinates. Only IPC mode dimensions need
// conversion from physical pixels. Odd transforms exchange width and height.
function monitorRect(monitor, screen) {
  if (!monitor) return null
  var scale = positive(monitor.scale, 1)
  var rotated = finite(monitor.transform) && Math.abs(monitor.transform % 2) === 1
  var physicalW = rotated ? monitor.height : monitor.width
  var physicalH = rotated ? monitor.width : monitor.height
  var w = positive(screen && screen.width, physicalW / scale)
  var h = positive(screen && screen.height, physicalH / scale)
  if (!finite(w) || !finite(h) || w <= 0 || h <= 0) return null
  return { x: finite(monitor.x) ? monitor.x : 0, y: finite(monitor.y) ? monitor.y : 0, w: w, h: h }
}

// IPC reserved edges are already logical [left, top, right, bottom].
function workArea(monitor, screen) {
  var rect = monitorRect(monitor, screen)
  if (!rect) return null
  var edges = monitor.reserved || []
  var left = Math.min(rect.w, nonnegative(edges[0], 0))
  var top = Math.min(rect.h, nonnegative(edges[1], 0))
  var right = Math.min(rect.w - left, nonnegative(edges[2], 0))
  var bottom = Math.min(rect.h - top, nonnegative(edges[3], 0))
  return { x: rect.x + left, y: rect.y + top, w: rect.w - left - right, h: rect.h - top - bottom }
}

function monitorAt(cursorX, cursorY, monitors) {
  if (!finite(cursorX) || !finite(cursorY) || !Array.isArray(monitors)) return null
  for (var i = 0; i < monitors.length; i++) {
    var rect = monitorRect(monitors[i])
    if (contains(rect, cursorX, cursorY)) return monitors[i]
  }
  return null
}

function contains(rect, x, y) {
  return !!(rect && x >= rect.x && y >= rect.y && x < rect.x + rect.w && y < rect.y + rect.h)
}

function bounded(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function clamp(value, span, limit) {
  if (!finite(limit) || limit <= 0) return value
  return bounded(value, 0, Math.max(0, limit - span))
}

// The visible intersection is used for both dimensions so an offscreen or
// narrow window cannot leave a button outside the window or on another screen.
function visibleWindow(client, monitor, screen) {
  var rect = monitorRect(monitor, screen)
  var at = client && client.at
  var size = client && client.size
  if (!rect || !at || !size || !finite(at[0]) || !finite(at[1]) ||
      !finite(size[0]) || !finite(size[1]) || size[0] <= 0 || size[1] <= 0) return null
  var x = at[0] - rect.x
  var y = at[1] - rect.y
  var left = Math.max(0, x)
  var top = Math.max(0, y)
  var right = Math.min(rect.w, x + size[0])
  var bottom = Math.min(rect.h, y + size[1])
  if (right <= left || bottom <= top) return null
  return { x: x, y: y, w: size[0], h: size[1], left: left, top: top, right: right, bottom: bottom }
}

function chromeTopLeft(client, monitor, screen, chromeW, inset, chromeH) {
  var win = visibleWindow(client, monitor, screen)
  if (!win) return null
  var w = Math.min(positive(chromeW, 102), win.right - win.left)
  var h = Math.min(positive(chromeH, 24), win.bottom - win.top)
  var margin = nonnegative(inset, 4)
  return {
    x: bounded(Math.round(win.x + win.w - w - margin), win.left, win.right - w),
    y: bounded(Math.round(win.y + margin), win.top, win.bottom - h),
    w: w, h: h, scale: 1
  }
}

function resizeHandle(client, monitor, screen, grip) {
  var win = visibleWindow(client, monitor, screen)
  if (!win) return null
  var g = positive(grip, 18)
  var w = Math.min(g, win.right - win.left)
  var h = Math.min(g, win.bottom - win.top)
  return {
    x: bounded(Math.round(win.x + win.w - w), win.left, win.right - w),
    y: bounded(Math.round(win.y + win.h - h), win.top, win.bottom - h),
    w: w, h: h, scale: 1
  }
}

// Corners take a quarter, sides a half, top the work area. A point outside
// this monitor never snaps here, even if it is near an edge on another screen.
function snapRect(cursorX, cursorY, monitor, threshold, gap) {
  if (!finite(cursorX) || !finite(cursorY) || !contains(monitorRect(monitor), cursorX, cursorY)) return null
  var area = workArea(monitor)
  if (!area) return null
  var edge = positive(threshold, 28)
  var margin = nonnegative(gap, 10)
  var x = area.x + margin
  var y = area.y + margin
  var w = area.w - margin * 2
  var h = area.h - margin * 2
  if (w < 64 || h < 40) return null
  var nearL = cursorX - area.x <= edge
  var nearR = area.x + area.w - cursorX <= edge
  var nearT = cursorY - area.y <= edge
  var nearB = area.y + area.h - cursorY <= edge
  var halfW = Math.round(w / 2)
  var halfH = Math.round(h / 2)
  if (nearT && nearL) return halfW >= 64 && halfH >= 40 ? { x: x, y: y, w: halfW, h: halfH } : null
  if (nearT && nearR) return halfW >= 64 && halfH >= 40 ? { x: x + w - halfW, y: y, w: halfW, h: halfH } : null
  if (nearB && nearL) return halfW >= 64 && halfH >= 40 ? { x: x, y: y + h - halfH, w: halfW, h: halfH } : null
  if (nearB && nearR) return halfW >= 64 && halfH >= 40 ? { x: x + w - halfW, y: y + h - halfH, w: halfW, h: halfH } : null
  if (nearT) return { x: x, y: y, w: w, h: h }
  if (nearL) return halfW >= 64 ? { x: x, y: y, w: halfW, h: h } : null
  if (nearR) return halfW >= 64 ? { x: x + w - halfW, y: y, w: halfW, h: h } : null
  return null
}

// A bounded shelf row is paginated rather than dropping windows or growing
// past the display. Navigation sits beside the row vertically, away from the
// selected screen edge. Existing callers retain the bottom placement.
function shelfLayout(count, monitor, screen, chipW, chipH, gap, page, anchor) {
  var topAnchored = anchor === "top"
  var rect = monitorRect(monitor, screen)
  var usable = workArea(monitor, screen)
  var empty = { items: [], page: 0, pages: 1, capacity: 0, area: null, pager: null, anchor: topAnchored ? "top" : "bottom" }
  if (!rect || !usable || usable.w <= 0 || usable.h <= 0) return empty
  var requestedGap = nonnegative(gap, 6)
  var outerGap = Math.min(requestedGap, usable.w / 4, usable.h / 4)
  var area = { x: usable.x - rect.x + outerGap, y: usable.y - rect.y + outerGap,
               w: usable.w - outerGap * 2, h: usable.h - outerGap * 2 }
  var desiredW = positive(chipW, 176)
  var desiredH = positive(chipH, 28)
  var n = finite(count) && count > 0 ? Math.floor(count) : 0
  var capacity = Math.max(1, Math.floor((area.w + requestedGap) / (desiredW + requestedGap)))
  var pages = Math.max(1, Math.ceil(n / capacity))
  var current = bounded(finite(page) ? Math.floor(page) : 0, 0, pages - 1)
  var itemW = Math.min(desiredW, (area.w - requestedGap * (capacity - 1)) / capacity)
  var pager = null
  var itemH = Math.min(desiredH, area.h)
  var itemY = topAnchored ? area.y : area.y + area.h - itemH
  if (pages > 1) {
    var rowGap = Math.min(requestedGap, area.h / 8)
    var maxH = (area.h - rowGap) / 2
    itemH = Math.min(desiredH, maxH)
    var pagerH = Math.min(24, maxH)
    if (topAnchored) {
      itemY = area.y
      pager = { x: area.x, y: itemY + itemH + rowGap, w: Math.min(area.w, 200), h: pagerH }
    } else {
      pager = { x: area.x, y: area.y + area.h - pagerH, w: Math.min(area.w, 200), h: pagerH }
      itemY = pager.y - rowGap - itemH
    }
  }
  var items = []
  var start = current * capacity
  for (var i = start; i < Math.min(n, start + capacity); i++) {
    items.push({ index: i, x: area.x + (i - start) * (itemW + requestedGap),
                 y: itemY, w: itemW, h: itemH })
  }
  return { items: items, page: current, pages: pages, capacity: capacity, area: area, pager: pager, anchor: topAnchored ? "top" : "bottom" }
}
