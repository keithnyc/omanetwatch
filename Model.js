.pragma library

function positiveInteger(value, fallback) {
  var parsed = Number(value)
  if (!isFinite(parsed) || parsed <= 0) return fallback
  return Math.round(parsed)
}

function isCanonicalState(value) {
  return value === "operational" || value === "degraded" || value === "outage" || value === "unknown"
}

function canonicalState(value) {
  var state = String(value || "").toLowerCase()
  return isCanonicalState(state) ? state : "unknown"
}

function stateLabel(value) {
  var state = canonicalState(value)
  if (state === "operational") return "Operational"
  if (state === "degraded") return "Degraded"
  if (state === "outage") return "Outage"
  return "Unknown"
}

function resultState(result) {
  if (!result) return "unknown"
  if (result.state !== undefined) return canonicalState(result.state)
  return result.ok === true ? "operational" : "outage"
}

function normalizeTarget(raw, index) {
  if (!raw || typeof raw !== "object") throw new Error("target " + (index + 1) + " must be an object")

  var type = String(raw.type || "http").toLowerCase()
  if (type !== "http" && type !== "tcp" && type !== "json")
    throw new Error("target " + (index + 1) + " has unsupported type '" + type + "'")

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

  if (type === "http" || type === "json") {
    target.url = String(raw.url || "").trim()
    target.expectedStatus = positiveInteger(raw.expectedStatus, 200)
    if (!/^https?:\/\//.test(target.url)) throw new Error(name + " needs an http:// or https:// URL")
    if (type === "json") {
      target.statusPath = String(raw.statusPath || "").trim()
      if (!target.statusPath) throw new Error(name + " needs a statusPath")
      if (!raw.statusMap || typeof raw.statusMap !== "object" || Array.isArray(raw.statusMap))
        throw new Error(name + " needs a statusMap object")
      target.statusMap = {}
      var mapped = 0
      for (var statusValue in raw.statusMap) {
        var mappedState = String(raw.statusMap[statusValue] || "").toLowerCase()
        if (!isCanonicalState(mappedState))
          throw new Error(name + " maps '" + statusValue + "' to unsupported state '" + mappedState + "'")
        target.statusMap[String(statusValue)] = mappedState
        mapped++
      }
      if (mapped === 0) throw new Error(name + " needs at least one statusMap entry")
      target.reasonPath = String(raw.reasonPath || "").trim()
      target.sourceUrl = String(raw.sourceUrl || target.url).trim()
      if (!/^https?:\/\//.test(target.sourceUrl)) throw new Error(name + " needs an http:// or https:// sourceUrl")
    }
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
  if (target.type === "tcp") return target.host + ":" + target.port
  return target.sourceUrl || target.url
}

function resultDetail(result) {
  if (!result) return "Waiting for first check"
  if (result.disabled) return "Disabled"
  if (result.checking) return "Checking…"
  if (result.ok) {
    if (result.type === "json") {
      var healthyReason = String(result.reason || "").trim()
      return "Operational" + (healthyReason ? " · " + healthyReason : "") + " · " + result.latencyMs + " ms"
    }
    if (result.type === "http") return "HTTP " + result.statusCode + " · " + result.latencyMs + " ms"
    return "Connected · " + result.latencyMs + " ms"
  }
  if (result.type === "json") {
    var detail = String(result.reason || result.error || "").trim()
    return stateLabel(resultState(result)) + (detail ? " · " + detail : "")
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
      state: resultState(sample),
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
    state: resultState(result),
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
