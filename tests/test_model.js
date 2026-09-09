const fs = require("fs")
const vm = require("vm")

const source = fs.readFileSync("Model.js", "utf8").replace(/^\.pragma library\s*/, "")
const model = {}
vm.createContext(model)
vm.runInContext(source, model)

let failures = 0
function test(name, callback) {
  try {
    callback()
    console.log("ok  ", name)
  } catch (error) {
    failures++
    console.error("fail", name, "-", error.message)
  }
}
function equal(actual, expected) {
  if (actual !== expected) throw new Error(`expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`)
}
function throws(callback, fragment) {
  try { callback() } catch (error) {
    if (String(error).includes(fragment)) return
    throw error
  }
  throw new Error("expected an exception")
}

const jsonTarget = {
  name: "GitHub Status",
  type: "json",
  url: "https://www.githubstatus.com/api/v2/status.json",
  statusPath: "status.indicator",
  reasonPath: "status.description",
  sourceUrl: "https://www.githubstatus.com/",
  statusMap: {none: "operational", minor: "degraded", major: "outage"},
}

test("normalizes a JSON status target", () => {
  const target = model.normalizeTarget(jsonTarget, 0)
  equal(target.type, "json")
  equal(target.statusMap.minor, "degraded")
  equal(model.targetLabel(target), "https://www.githubstatus.com/")
})

test("rejects an absent status path", () => {
  throws(() => model.normalizeTarget({...jsonTarget, statusPath: ""}, 0), "statusPath")
})

test("rejects unsupported mapped states", () => {
  throws(() => model.normalizeTarget({...jsonTarget, statusMap: {none: "fine"}}, 0), "unsupported state")
})

test("formats structured status detail", () => {
  equal(model.resultDetail({type: "json", state: "degraded", reason: "API delays", ok: false}), "Degraded · API delays")
})

test("preserves canonical state in history", () => {
  const history = model.appendHistory([], {checkedAt: 10, ok: false, state: "degraded", latencyMs: 20}, 30)
  equal(history[0].state, "degraded")
})

if (failures) process.exit(1)
console.log("all passing")
