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

for (const budget of [1, 8, 40, 80, 200, 320, 360]) {
  for (const count of [1, 2, 13, 29, 100]) {
    const first = api.layout(count, budget, 112, 4, 0)
    const reached = []
    for (let page = 0; page < first.pages; page++) {
      const plan = api.layout(count, budget, 112, 4, page)
      assert(plan.width > 0 && plan.width <= budget + 1e-9, "widget respects allotted bar width")
      if (first.pages > 1) assert.equal(plan.width, first.width, "last page preserves neighboring widget positions")
      for (const item of plan.items) {
        assert(item.w > 0 && item.x >= 0 && item.x + item.w <= plan.width + 1e-9, "chip fits inside bar slot")
        reached.push(item.index)
      }
      for (const control of [plan.previous, plan.next, plan.counter]) {
        if (!control) continue
        assert(control.w > 0 && control.x >= 0 && control.x + control.w <= plan.width + 1e-9, "navigation fits inside bar slot")
        for (const item of plan.items)
          assert(item.x + item.w <= control.x + 1e-9 || control.x + control.w <= item.x + 1e-9, "navigation does not cover restore target")
      }
    }
    assert.deepEqual(reached, Array.from({ length: count }, (_, i) => i), "all minimized windows reachable at budget " + budget)
    assert.equal(api.layout(count, budget, 112, 4, 999).page, first.pages - 1)
    assert.equal(api.layout(count, budget, 112, 4, -10).page, 0)
  }
}
console.log("Bar checks passed (monitor filtering, empty width, bounded paging, and stable slot width)")
