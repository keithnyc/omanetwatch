import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string configDir: home + "/.config/omanetwatch"
  readonly property string configPath: home + "/.config/omanetwatch/targets.json"
  readonly property string stateDir: home + "/.local/state/omanetwatch"
  readonly property string statePath: stateDir + "/history.json"
  readonly property int historyLimit: 30
  // Third-party manifests expose public metadata only; resolve helper files
  // relative to this component instead of relying on host-private fields.
  readonly property string checkerPath: String(Qt.resolvedUrl("scripts/check_endpoint.py"))
    .replace(/^file:\/\//, "")

  property var targets: []
  property var rawTargets: []
  property var results: []
  property var nextDue: ({})
  property var pendingIds: []
  property var currentTarget: null
  property string configError: ""
  property string checkOutput: ""
  property string checkError: ""
  property double lastResultAt: 0
  property var persistedHistory: ({})
  property var feedStates: ({})
  property bool stateReady: false
  property int historyRevision: 0

  readonly property bool checking: checkProcess.running || pendingIds.length > 0
  readonly property int healthyCount: countResults("healthy")
  readonly property int degradedCount: countResults("degraded")
  readonly property int outageCount: countResults("outage")
  readonly property int unknownCount: countResults("unknown")
  readonly property int problemCount: degradedCount + outageCount + unknownCount
  readonly property int alertingCount: countResults("alerting")
  readonly property int downCount: alertingCount
  readonly property int enabledCount: countEnabledTargets()
  readonly property int enabledHealthCount: countEnabledHealthTargets()
  readonly property int pendingCount: Math.max(0, enabledHealthCount - healthyCount - problemCount)
  readonly property int feedCount: countTargetType("feed")
  readonly property int healthTargetCount: targets.length - feedCount

  function countTargetType(type) {
    var count = 0
    for (var i = 0; i < targets.length; i++) if (targets[i].type === type) count++
    return count
  }

  function countEnabledTargets() {
    var count = 0
    for (var i = 0; i < targets.length; i++) if (targets[i].enabled) count++
    return count
  }

  function countEnabledHealthTargets() {
    var count = 0
    for (var i = 0; i < targets.length; i++)
      if (targets[i].enabled && targets[i].type !== "feed") count++
    return count
  }

  function countResults(kind) {
    var count = 0
    for (var i = 0; i < results.length; i++) {
      var row = results[i]
      if (row.type === "feed") continue
      if (row.disabled || !row.checkedAt) continue
      if (kind === "healthy" && row.ok) count++
      if (kind === "degraded" && row.state === "degraded") count++
      if (kind === "outage" && row.state === "outage") count++
      if (kind === "unknown" && row.state === "unknown") count++
      if (kind === "alerting" && row.alerting) count++
    }
    return count
  }

  function targetById(id) {
    for (var i = 0; i < targets.length; i++) if (targets[i].id === id) return targets[i]
    return null
  }

  function resultById(id) {
    for (var i = 0; i < results.length; i++) if (results[i].id === id) return results[i]
    return null
  }

  function historyFor(id) {
    var row = resultById(id)
    return row && Array.isArray(row.history) ? row.history : []
  }

  function clone(value) {
    return JSON.parse(JSON.stringify(value))
  }

  function rawIndexForId(id) {
    for (var i = 0; i < rawTargets.length; i++) {
      try {
        if (Model.normalizeTarget(rawTargets[i], i).id === id) return i
      } catch (error) {}
    }
    return -1
  }

  function targetConfig(id) {
    var index = rawIndexForId(id)
    return index >= 0 ? clone(rawTargets[index]) : null
  }

  function writeTargets(next) {
    try {
      Model.normalizeTargets(next)
      var serialized = JSON.stringify(next, null, 2) + "\n"
      configError = ""
      configFile.setText(serialized)
      // FileView's own writes do not trigger onFileChanged, so update the
      // running service immediately instead of waiting for an external edit.
      loadConfig(serialized)
      return ""
    } catch (error) {
      return String(error)
    }
  }

  function saveTarget(originalId, input) {
    var next = clone(rawTargets)
    var index = originalId ? rawIndexForId(originalId) : -1
    if (originalId && index < 0) return "Target no longer exists"

    var target = Model.mergeTargetConfig(index >= 0 ? next[index] : null, input)

    if (index >= 0) next[index] = target
    else next.push(target)
    return writeTargets(next)
  }

  function removeTarget(id) {
    var index = rawIndexForId(id)
    if (index < 0) return "Target no longer exists"
    var next = clone(rawTargets)
    next.splice(index, 1)
    return writeTargets(next)
  }

  function setTargetEnabled(id, enabled) {
    var index = rawIndexForId(id)
    if (index < 0) return "Target no longer exists"
    var next = clone(rawTargets)
    next[index].enabled = enabled === true
    return writeTargets(next)
  }

  function loadState(raw) {
    var stored = {}
    var storedFeeds = {}
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (parsed && parsed.targets && typeof parsed.targets === "object") stored = parsed.targets
      if (parsed && parsed.feeds && typeof parsed.feeds === "object") storedFeeds = parsed.feeds
    } catch (error) {
      console.warn("omanetwatch: history state error:", String(error))
    }
    persistedHistory = stored
    feedStates = clone(storedFeeds)
    stateReady = true

    var next = []
    for (var i = 0; i < results.length; i++) {
      var row = results[i]
      var copy = {}
      for (var key in row) copy[key] = row[key]
      if (row.type === "feed") {
        var feed = storedFeeds[row.id]
        var latest = feed && feed.latest ? feed.latest : null
        copy.latestItemTitle = latest ? String(latest.title || "") : ""
        copy.latestItemStatus = latest ? String(latest.status || "") : ""
        copy.latestItemLink = latest ? String(latest.link || "") : ""
        copy.latestItemPublished = latest ? String(latest.published || "") : ""
        copy.label = latest && latest.link ? String(latest.link) : copy.label
        copy.sourceUrl = latest && latest.link ? String(latest.link) : copy.sourceUrl
      } else copy.history = Model.mergeHistory(row.history, stored[row.id], historyLimit)
      next.push(copy)
    }
    results = next
    historyRevision++
  }

  function historyPayload() {
    var stored = {}
    var feeds = {}
    for (var i = 0; i < results.length; i++) {
      var row = results[i]
      if (row.type === "feed") {
        if (feedStates[row.id]) feeds[row.id] = feedStates[row.id]
        continue
      }
      var history = Model.normalizeHistory(row.history, historyLimit)
      if (history.length > 0) stored[row.id] = history
    }
    return { version: 2, targets: stored, feeds: feeds }
  }

  function persistHistory() {
    if (!stateReady) return
    stateFile.setText(JSON.stringify(historyPayload(), null, 2) + "\n")
  }

  function loadConfig(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      var normalized = Model.normalizeTargets(parsed)
      rawTargets = clone(parsed)
      var kept = []
      for (var i = 0; i < normalized.length; i++) {
        var target = normalized[i]
        var previous = resultById(target.id)
        var row = {}
        if (previous) for (var key in previous) row[key] = previous[key]
        row.id = target.id
        row.name = target.name
        row.type = target.type
        row.label = Model.targetLabel(target)
        row.sourceUrl = target.sourceUrl || target.url || ""
        row.history = Model.mergeHistory(previous ? previous.history : [], persistedHistory[target.id], historyLimit)
        row.disabled = !target.enabled
        row.checking = false
        if (target.type === "feed") {
          var savedFeed = feedStates[target.id]
          var latest = savedFeed && savedFeed.latest ? savedFeed.latest : null
          row.latestItemTitle = latest ? String(latest.title || "") : ""
          row.latestItemStatus = latest ? String(latest.status || "") : ""
          row.latestItemLink = latest ? String(latest.link || "") : ""
          row.latestItemPublished = latest ? String(latest.published || "") : ""
        }
        if (!target.enabled) {
          row.ok = false
          row.state = "unknown"
          row.alerting = false
          row.consecutiveFailures = 0
          row.error = "Disabled"
        } else if (!previous || previous.disabled) {
          row.ok = false
          row.state = "unknown"
          row.alerting = false
          row.consecutiveFailures = 0
          row.checkedAt = 0
          row.error = "Waiting for first check"
        }
        kept.push(row)
      }
      targets = normalized
      results = kept
      historyRevision++
      nextDue = ({})
      pendingIds = []
      configError = ""
      if (stateReady) stateWriteTimer.restart()
      checkAllNow()
    } catch (error) {
      configError = String(error)
      targets = []
      results = []
      pendingIds = []
      console.warn("omanetwatch: config error:", configError)
    }
  }

  function enqueueDue() {
    if (!stateReady) return
    var now = Date.now()
    var queued = pendingIds.slice(0)
    for (var i = 0; i < targets.length; i++) {
      var id = targets[i].id
      if (!targets[i].enabled) continue
      if (currentTarget && currentTarget.id === id) continue
      if (queued.indexOf(id) !== -1) continue
      if (!nextDue[id] || nextDue[id] <= now) queued.push(id)
    }
    pendingIds = queued
    runNext()
  }

  function checkAllNow() {
    var due = {}
    for (var key in nextDue) due[key] = nextDue[key]
    for (var i = 0; i < targets.length; i++) {
      if (targets[i].enabled) due[targets[i].id] = 0
    }
    nextDue = due
    enqueueDue()
  }

  function markChecking(id) {
    var next = []
    for (var i = 0; i < results.length; i++) {
      var row = results[i]
      if (row.id === id) {
        var copy = {}
        for (var key in row) copy[key] = row[key]
        copy.checking = true
        next.push(copy)
      } else next.push(row)
    }
    results = next
  }

  function runNext() {
    if (checkProcess.running || currentTarget || pendingIds.length === 0 || checkerPath === "") return
    var queue = pendingIds.slice(0)
    var id = queue.shift()
    pendingIds = queue
    currentTarget = targetById(id)
    if (!currentTarget) {
      currentTarget = null
      runNext()
      return
    }
    markChecking(id)
    checkOutput = ""
    checkError = ""
    checkProcess.command = ["python3", checkerPath, JSON.stringify(currentTarget)]
    checkProcess.running = true
  }

  function sendNotification(title, body, urgency, glyph) {
    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "omanetwatch",
      "--urgency", urgency,
      "--glyph", glyph,
      title,
      body
    ])
  }

  function applyResult(target, rawResult) {
    if (target.type === "feed") {
      applyFeedResult(target, rawResult)
      return
    }
    var previous = resultById(target.id)
    var state = Model.resultState(rawResult)
    var operational = state === "operational"
    var failures = operational ? 0 : ((previous && previous.consecutiveFailures) || 0) + 1
    var alerting = !operational && failures >= target.failuresBeforeAlert
    var wasAlerting = previous ? previous.alerting === true : false
    var previousState = previous ? Model.resultState(previous) : "unknown"
    var checkedAt = Number(rawResult.checkedAt || Date.now())
    var row = {
      id: target.id,
      name: target.name,
      type: target.type,
      label: Model.targetLabel(target),
      disabled: false,
      ok: operational,
      state: state,
      alerting: alerting,
      checking: false,
      statusCode: Number(rawResult.statusCode || 0),
      latencyMs: Number(rawResult.latencyMs || 0),
      error: String(rawResult.error || ""),
      reason: String(rawResult.reason || ""),
      statusValue: String(rawResult.statusValue || ""),
      sourceUrl: target.sourceUrl || target.url || "",
      consecutiveFailures: failures,
      checkedAt: checkedAt
    }
    row.history = Model.appendHistory(previous ? previous.history : [], row, historyLimit)

    var next = []
    var replaced = false
    for (var i = 0; i < results.length; i++) {
      if (results[i].id === target.id) {
        next.push(row)
        replaced = true
      } else next.push(results[i])
    }
    if (!replaced) next.push(row)
    results = next
    lastResultAt = checkedAt
    historyRevision++
    stateWriteTimer.restart()

    var due = {}
    for (var key in nextDue) due[key] = nextDue[key]
    due[target.id] = Date.now() + target.intervalSeconds * 1000
    nextDue = due

    if (alerting && (!wasAlerting || previousState !== state)) {
      var alertTitle = target.name + " is down"
      if (target.type === "json") {
        if (state === "degraded") alertTitle = target.name + " is degraded"
        else if (state === "outage") alertTitle = target.name + " reports an outage"
        else alertTitle = target.name + " status is unknown"
      }
      var alertBody = row.error || Model.resultDetail(row)
      if (target.type === "json" && row.sourceUrl) alertBody += "\n" + row.sourceUrl
      sendNotification(
        alertTitle,
        alertBody,
        "critical",
        "󰅚"
      )
    } else if (operational && wasAlerting) {
      var recoveryBody = Model.resultDetail(row)
      if (target.type === "json" && row.sourceUrl) recoveryBody += "\n" + row.sourceUrl
      sendNotification(
        target.name + " recovered",
        recoveryBody,
        "normal",
        "󰄬"
      )
    }
  }

  function applyFeedResult(target, rawResult) {
    var checkedAt = Number(rawResult.checkedAt || Date.now())
    var feedOk = rawResult.ok === true
    var update = null
    var latest = null
    if (feedOk) {
      var priorState = feedStates[target.id]
      if (!priorState || String(priorState.sourceUrl || "") !== target.url) priorState = null
      update = Model.updateFeedState(priorState, rawResult.items, 200)
      update.state.sourceUrl = target.url
      var states = clone(feedStates)
      states[target.id] = update.state
      feedStates = states
      latest = update.state.latest
    } else {
      var saved = feedStates[target.id]
      latest = saved && saved.latest ? saved.latest : null
    }

    var row = {
      id: target.id,
      name: target.name,
      type: "feed",
      label: latest && latest.link ? String(latest.link) : Model.targetLabel(target),
      disabled: false,
      ok: feedOk,
      state: feedOk ? "operational" : "unknown",
      alerting: false,
      checking: false,
      statusCode: Number(rawResult.statusCode || 0),
      latencyMs: Number(rawResult.latencyMs || 0),
      error: String(rawResult.error || ""),
      reason: "",
      sourceUrl: latest && latest.link ? String(latest.link) : (target.sourceUrl || target.url || ""),
      consecutiveFailures: 0,
      checkedAt: checkedAt,
      latestItemTitle: latest ? String(latest.title || "") : "",
      latestItemStatus: latest ? String(latest.status || "") : "",
      latestItemLink: latest ? String(latest.link || "") : "",
      latestItemPublished: latest ? String(latest.published || "") : "",
      history: []
    }

    var next = []
    var replaced = false
    for (var i = 0; i < results.length; i++) {
      if (results[i].id === target.id) {
        next.push(row)
        replaced = true
      } else next.push(results[i])
    }
    if (!replaced) next.push(row)
    results = next
    lastResultAt = checkedAt
    historyRevision++
    stateWriteTimer.restart()

    var due = {}
    for (var key in nextDue) due[key] = nextDue[key]
    due[target.id] = Date.now() + target.intervalSeconds * 1000
    nextDue = due

    if (update) {
      var notifyLimit = Math.min(update.changes.length, 5)
      for (var changeIndex = 0; changeIndex < notifyLimit; changeIndex++) {
        var change = update.changes[changeIndex]
        var item = change.item || ({})
        var title = target.name + (change.kind === "updated" ? ": incident updated" : ": new incident")
        var body = String(item.title || "Untitled feed item")
        if (item.status) body = String(item.status) + " · " + body
        if (item.link) body += "\n" + String(item.link)
        sendNotification(title, body, "normal", "󰑫")
      }
      if (update.changes.length > notifyLimit)
        sendNotification(target.name + ": more incident activity", String(update.changes.length - notifyLimit) + " additional updates", "normal", "󰑫")
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: function(error) {
      root.rawTargets = []
      root.targets = []
      root.results = []
      root.configError = ""
    }
    onFileChanged: reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onLoadFailed: root.stateReady = true
  }

  Process {
    command: ["mkdir", "-p", root.configDir, root.stateDir]
    running: true
    onExited: stateFile.reload()
  }

  Timer {
    id: stateWriteTimer
    interval: 250
    repeat: false
    onTriggered: root.persistHistory()
  }

  Timer {
    interval: 1000
    running: root.targets.length > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.enqueueDue()
  }

  Process {
    id: checkProcess
    running: false
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.checkOutput = String(text || "").trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.checkError = String(text || "").trim()
    }
    onExited: function(exitCode) {
      var target = root.currentTarget
      root.currentTarget = null
      var liveTarget = target ? root.targetById(target.id) : null
      if (liveTarget && liveTarget.enabled) {
        var result
        try {
          result = JSON.parse(root.checkOutput)
        } catch (error) {
          result = {
            ok: false,
            checkedAt: Date.now(),
            error: root.checkError || "Checker returned invalid output"
          }
        }
        root.applyResult(liveTarget, result)
      }
      Qt.callLater(root.runNext)
    }
  }
}
