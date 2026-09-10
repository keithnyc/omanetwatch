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

const feedTarget = {
  name: "xAI incidents",
  type: "feed",
  url: "https://status.x.ai/feed.xml",
  sourceUrl: "https://status.x.ai/",
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

test("editor updates preserve unknown fields", () => {
  const merged = model.mergeTargetConfig(
    {name: "Old", type: "http", url: "https://old.example", customMetadata: "keep"},
    {name: "New", type: "tcp", host: "example.com", port: 443}
  )
  equal(merged.customMetadata, "keep")
  equal(merged.type, "tcp")
  equal(merged.url, undefined)
  equal(merged.host, "example.com")
})

test("normalizes an incident feed target", () => {
  const target = model.normalizeTarget(feedTarget, 0)
  equal(target.type, "feed")
  equal(model.targetLabel(target), "https://status.x.ai/")
})

test("first feed check establishes a quiet baseline", () => {
  const item = {id: "one", fingerprint: "a", title: "Incident", link: "https://status.example/one"}
  const update = model.updateFeedState(null, [item], 200)
  equal(update.changes.length, 0)
  equal(update.state.initialized, true)
  equal(update.state.latest.title, "Incident")
})

test("feed state detects new and updated items", () => {
  const original = {id: "one", fingerprint: "a", title: "Incident"}
  const prior = model.updateFeedState(null, [original], 200).state
  equal(model.updateFeedState(prior, [original], 200).changes.length, 0)
  const update = model.updateFeedState(prior, [
    {id: "two", fingerprint: "b", title: "New incident"},
    {id: "one", fingerprint: "c", title: "Incident updated"}
  ], 200)
  equal(update.changes.length, 2)
  equal(update.changes[0].kind, "new")
  equal(update.changes[1].kind, "updated")
})

if (failures) process.exit(1)
console.log("all passing")
