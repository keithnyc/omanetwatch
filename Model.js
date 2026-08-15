.pragma library

function positiveInteger(value, fallback) {
  var parsed = Number(value)
  if (!isFinite(parsed) || parsed <= 0) return fallback
  return Math.round(parsed)
}

function normalizeTarget(raw, index) {
  if (!raw || typeof raw !== "object") throw new Error("target " + (index + 1) + " must be an object")

  var type = String(raw.type || "http").toLowerCase()
  if (type !== "http" && type !== "tcp") throw new Error("target " + (index + 1) + " has unsupported type '" + type + "'")

  var name = String(raw.name || "").trim()
  if (!name) throw new Error("target " + (index + 1) + " needs a name")
  if (raw.enabled !== undefined && typeof raw.enabled !== "boolean")
    throw new Error(name + " has a non-boolean enabled flag")

  var target = {
    id: String(raw.id || name.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")),
    name: name,
    type: type,
    enabled: raw.enabled !== false,
    intervalSeconds: positiveInteger(raw.intervalSeconds, 60),
    timeoutSeconds: positiveInteger(raw.timeoutSeconds, 5),
    failuresBeforeAlert: positiveInteger(raw.failuresBeforeAlert, 2)
  }

  if (!target.id) target.id = "target-" + (index + 1)

  if (type === "http") {
    target.url = String(raw.url || "").trim()
    target.expectedStatus = positiveInteger(raw.expectedStatus, 200)
    if (!/^https?:\/\//.test(target.url)) throw new Error(name + " needs an http:// or https:// URL")
  } else {
    target.host = String(raw.host || "").trim()
    target.port = positiveInteger(raw.port, 0)
    if (!target.host || target.port < 1 || target.port > 65535) throw new Error(name + " needs a valid host and port")
  }

  return target
}

function normalizeTargets(raw) {
  if (!Array.isArray(raw)) throw new Error("the config root must be an array")
  var targets = []
  var ids = {}
  for (var i = 0; i < raw.length; i++) {
    var target = normalizeTarget(raw[i], i)
    if (ids[target.id]) throw new Error("duplicate target id '" + target.id + "'")
    ids[target.id] = true
    targets.push(target)
  }
  return targets
}

function targetLabel(target) {
  if (!target) return ""
  return target.type === "tcp" ? target.host + ":" + target.port : target.url
}

function resultDetail(result) {
  if (!result) return "Waiting for first check"
  if (result.disabled) return "Disabled"
  if (result.checking) return "Checking…"
  if (result.ok) {
    if (result.type === "http") return "HTTP " + result.statusCode + " · " + result.latencyMs + " ms"
    return "Connected · " + result.latencyMs + " ms"
  }
  return result.error || "Check failed"
}

function relativeTime(timestamp, now) {
  if (!timestamp) return "never"
  var seconds = Math.max(0, Math.round((now - timestamp) / 1000))
  if (seconds < 5) return "just now"
  if (seconds < 60) return seconds + "s ago"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  return Math.floor(hours / 24) + "d ago"
}

function normalizeHistory(raw, limit) {
  if (!Array.isArray(raw)) return []
  var samples = []
  for (var i = 0; i < raw.length; i++) {
    var sample = raw[i]
    if (!sample || typeof sample !== "object") continue
    var checkedAt = Number(sample.checkedAt || 0)
    if (!checkedAt) continue
    samples.push({
      checkedAt: checkedAt,
      ok: sample.ok === true,
      latencyMs: Math.max(0, Number(sample.latencyMs || 0)),
      statusCode: Math.max(0, Number(sample.statusCode || 0))
    })
  }
  samples.sort(function(a, b) { return a.checkedAt - b.checkedAt })
  return samples.slice(-Math.max(1, Number(limit) || 30))
}

function mergeHistory(first, second, limit) {
  var combined = normalizeHistory(first, limit).concat(normalizeHistory(second, limit))
  var byTimestamp = {}
  for (var i = 0; i < combined.length; i++) byTimestamp[String(combined[i].checkedAt)] = combined[i]
  var merged = []
  for (var key in byTimestamp) merged.push(byTimestamp[key])
  merged.sort(function(a, b) { return a.checkedAt - b.checkedAt })
  return merged.slice(-Math.max(1, Number(limit) || 30))
}

function appendHistory(history, result, limit) {
  return mergeHistory(history, [{
    checkedAt: Number(result.checkedAt || Date.now()),
    ok: result.ok === true,
    latencyMs: Math.max(0, Number(result.latencyMs || 0)),
    statusCode: Math.max(0, Number(result.statusCode || 0))
  }], limit)
}

function uptimePercent(history) {
  var samples = normalizeHistory(history, 100000)
  if (samples.length === 0) return 0
  var healthy = 0
  for (var i = 0; i < samples.length; i++) if (samples[i].ok) healthy++
  return healthy * 100 / samples.length
}

function averageLatency(history) {
  var samples = normalizeHistory(history, 100000)
  var total = 0
  var count = 0
  for (var i = 0; i < samples.length; i++) {
    if (!samples[i].ok) continue
    total += samples[i].latencyMs
    count++
  }
  return count > 0 ? Math.round(total / count) : 0
}

function historySummary(history) {
  var samples = normalizeHistory(history, 100000)
  if (samples.length === 0) return "No history"
  var uptime = uptimePercent(samples)
  var uptimeText = (uptime === 100 || uptime === 0) ? String(Math.round(uptime)) : uptime.toFixed(1)
  var average = averageLatency(samples)
  return uptimeText + "% · " + (average > 0 ? average + " ms avg" : "no latency")
}
