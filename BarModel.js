.pragma library

function finite(value) {
  return typeof value === "number" && isFinite(value)
}

function positive(value, fallback) {
  return finite(value) && value > 0 ? value : fallback
}

function chipsFor(minimized, screenName) {
  var chips = []
  var seen = {}
  if (!screenName || !Array.isArray(minimized)) return chips
  for (var i = 0; i < minimized.length; i++) {
    var chip = minimized[i]
    if (!chip || chip.screenName !== screenName || typeof chip.address !== "string"
        || !/^0x[0-9a-fA-F]+$/.test(chip.address) || seen[chip.address]) continue
    seen[chip.address] = true
    chips.push(chip)
  }
  return chips
}

// Navigation and chips share a fixed budget. Keeping paginated width stable
// prevents a short final page from moving neighboring clock/status widgets.
function layout(count, maxWidth, chipWidth, gap, page) {
  var n = finite(count) && count > 0 ? Math.floor(count) : 0
  var budget = positive(maxWidth, 0)
  var empty = { items: [], page: 0, pages: 1, capacity: 0, width: 0, previous: null, next: null, counter: null }
  if (!n || !budget) return empty
  var desiredW = positive(chipWidth, 112)
  var spacing = Math.min(finite(gap) && gap >= 0 ? gap : 4, budget / 16)
  var unpagedCapacity = Math.max(1, Math.floor((budget + spacing) / (desiredW + spacing)))
  var capacity = unpagedCapacity
  var previous = null, next = null, counter = null
  var itemSpace = budget
  var itemStart = 0
  var width = 0
  if (n > unpagedCapacity) {
    var navigationW = Math.min(22, budget / 5)
    var counterW = Math.min(32, budget / 4)
    itemSpace = budget - navigationW * 2 - counterW - spacing * 3
    capacity = Math.max(1, Math.floor((itemSpace + spacing) / (desiredW + spacing)))
    itemStart = navigationW + spacing
    previous = { x: 0, w: navigationW }
    next = { x: itemStart + itemSpace + spacing, w: navigationW }
    counter = { x: next.x + next.w + spacing, w: counterW }
    width = budget
  }
  var pages = Math.max(1, Math.ceil(n / capacity))
  var current = Math.max(0, Math.min(pages - 1, finite(page) ? Math.floor(page) : 0))
  var itemW = Math.min(desiredW, (itemSpace - spacing * (capacity - 1)) / capacity)
  var start = current * capacity
  var end = Math.min(n, start + capacity)
  var items = []
  for (var i = start; i < end; i++)
    items.push({ index: i, x: itemStart + (i - start) * (itemW + spacing), w: itemW })
  if (!previous) width = items.length * itemW + Math.max(0, items.length - 1) * spacing
  return { items: items, page: current, pages: pages, capacity: capacity, width: width,
           previous: previous, next: next, counter: counter }
}
