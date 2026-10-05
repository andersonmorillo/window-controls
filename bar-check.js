const fs = require("fs")
const path = require("path")
const assert = require("assert/strict")
const source = fs.readFileSync(path.join(__dirname, "BarModel.js"), "utf8").replace(/^\.pragma library\s*/, "")
const api = new Function(source + "\nreturn { chipsFor, layout }")()

const left = { address: "0x1000", screenName: "left", title: "Left", stableId: "one" }
const right = { address: "0x1001", screenName: "right", title: "Right", stableId: "two" }
assert.deepEqual(api.chipsFor([left, right, left, null, { address: "invalid", screenName: "left" }], "left"), [left], "monitor filtering and address deduplication")
assert.deepEqual(api.chipsFor([left, right], ""), [], "unattached widget has no destinations")
assert.deepEqual(api.chipsFor(null, "left"), [])
assert.equal(api.layout(0, 320, 112, 4, 0).width, 0, "empty widget leaves no space")
assert.equal(api.layout(5, 0, 112, 4, 0).width, 0, "zero budget leaves no space")
const single = api.layout(1, 320, 112, 4, 0)
assert.deepEqual(single.items, [{ index: 0, x: 0, w: 112 }])
assert.equal(single.previous, null)
assert.equal(single.next, null)
assert.equal(single.width, 112)

for (const [count, budget] of [[4, 360], [6, 480], [8, 640]]) {
  const fitted = api.layout(count, budget, 96, 4, 0, 72)
  assert.equal(fitted.pages, 1, "all windows fit at adaptive width for " + count + " windows")
  assert.equal(fitted.items.length, count)
  assert.equal(fitted.capacity, count)
  assert.equal(fitted.previous, null)
  assert.equal(fitted.next, null)
  assert.equal(fitted.counter, null)
  assert.equal(fitted.width, budget)
  for (const item of fitted.items) {
    assert.equal(item.w, (budget - (count - 1) * 4) / count)
    assert(item.w >= 72 && item.w <= 96, "adaptive chip remains within preferred and minimum widths")
  }
}
const adaptiveOverflow = api.layout(13, 360, 96, 4, 0, 72)
assert.equal(adaptiveOverflow.capacity, 3, "overflow fits three windows alongside navigation")
assert.equal(adaptiveOverflow.pages, 5)
assert.equal(adaptiveOverflow.items[0].w, 88)
assert.equal(api.layout(1, 640, 96, 4, 0, 72).width, 96, "spare budget preserves preferred chip width")
for (const minimum of [undefined, null, 0, -1, NaN, Infinity, 300])
  assert.deepEqual(api.layout(13, 360, 96, 4, 0, minimum), api.layout(13, 360, 96, 4, 0), "invalid or excessive minimum preserves preferred width")
for (const count of [-1, 0, NaN, Infinity])
  assert.equal(api.layout(count, 360, 96, 4, 0, 72).width, 0, "invalid or empty counts do not reserve space")
assert.equal(api.layout(4.7, 360, 96, 4, 0, 72).items.length, 4, "fractional counts are bounded to whole windows")

for (const budget of [1, 8, 40, 80, 200, 320, 360]) {
  for (const count of [1, 2, 13, 29, 100]) {
    for (const minimum of [undefined, 72]) {
      const first = api.layout(count, budget, 112, 4, 0, minimum)
      const reached = []
      for (let page = 0; page < first.pages; page++) {
        const plan = api.layout(count, budget, 112, 4, page, minimum)
        assert(plan.width > 0 && plan.width <= budget + 1e-9, "widget respects allotted bar width")
        if (first.pages > 1) assert.equal(plan.width, first.width, "last page preserves neighboring widget positions")
        assert.equal(plan.capacity, first.capacity, "capacity stays stable across pages")
        for (const item of plan.items) {
          assert(item.w > 0 && item.x >= 0 && item.x + item.w <= plan.width + 1e-9, "chip fits inside bar slot")
          assert.equal(item.w, first.items[0].w, "last page preserves chip width")
          reached.push(item.index)
        }
        const controls = [plan.previous, plan.next, plan.counter].filter(Boolean)
        for (let index = 0; index < controls.length; index++) {
          const control = controls[index]
          assert(control.w > 0 && control.x >= 0 && control.x + control.w <= plan.width + 1e-9, "navigation fits inside bar slot")
          if (index) assert(controls[index - 1].x + controls[index - 1].w <= control.x + 1e-9, "navigation targets never overlap")
          for (const item of plan.items)
            assert(item.x + item.w <= control.x + 1e-9 || control.x + control.w <= item.x + 1e-9, "navigation does not cover restore target")
        }
      }
      assert.deepEqual(reached, Array.from({ length: count }, (_, i) => i), "all minimized windows reachable at budget " + budget)
      assert.equal(api.layout(count, budget, 112, 4, 999, minimum).page, first.pages - 1)
      assert.equal(api.layout(count, budget, 112, 4, -10, minimum).page, 0)
    }
  }
}
console.log("Bar checks passed (monitor filtering, adaptive chips, bounded paging, and stable slot width)")
