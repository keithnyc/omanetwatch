import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property string home: Quickshell.env("HOME")
  readonly property string configPath: home + "/.config/omanetwatch/targets.json"
  readonly property string stateDir: home + "/.local/state/omanetwatch"
  readonly property string statePath: stateDir + "/history.json"
  readonly property int historyLimit: 30
  readonly property string checkerPath: manifest && manifest.__sourceDir
    ? manifest.__sourceDir + "/scripts/check_endpoint.py"
    : ""

  property var targets: []
  property var results: []
  property var nextDue: ({})
  property var pendingIds: []
  property var currentTarget: null
  property string configError: ""
  property string checkOutput: ""
  property string checkError: ""
  property double lastResultAt: 0
  property var persistedHistory: ({})
  property bool stateReady: false
  property int historyRevision: 0

  readonly property bool checking: checkProcess.running || pendingIds.length > 0
  readonly property int healthyCount: countResults("healthy")
  readonly property int downCount: countResults("down")
  readonly property int enabledCount: countEnabledTargets()
  readonly property int pendingCount: Math.max(0, enabledCount - healthyCount - downCount)

  function countEnabledTargets() {
    var count = 0
    for (var i = 0; i < targets.length; i++) if (targets[i].enabled) count++
    return count
  }

  function countResults(kind) {
    var count = 0
    for (var i = 0; i < results.length; i++) {
      if (kind === "healthy" && results[i].ok) count++
      if (kind === "down" && results[i].alerting) count++
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

  function loadState(raw) {
    var stored = {}
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (parsed && parsed.targets && typeof parsed.targets === "object") stored = parsed.targets
    } catch (error) {
      console.warn("omanetwatch: history state error:", String(error))
    }
    persistedHistory = stored
    stateReady = true

    var next = []
    for (var i = 0; i < results.length; i++) {
      var row = results[i]
      var copy = {}
      for (var key in row) copy[key] = row[key]
      copy.history = Model.mergeHistory(row.history, stored[row.id], historyLimit)
      next.push(copy)
    }
    results = next
    historyRevision++
  }

  function historyPayload() {
    var stored = {}
    for (var i = 0; i < results.length; i++) {
      var row = results[i]
      var history = Model.normalizeHistory(row.history, historyLimit)
      if (history.length > 0) stored[row.id] = history
    }
    return { version: 1, targets: stored }
  }

  function persistHistory() {
    if (!stateReady) return
    stateFile.setText(JSON.stringify(historyPayload(), null, 2) + "\n")
  }

  function loadConfig(raw) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      var normalized = Model.normalizeTargets(parsed)
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
        row.history = Model.mergeHistory(previous ? previous.history : [], persistedHistory[target.id], historyLimit)
        row.disabled = !target.enabled
        row.checking = false
        if (!target.enabled) {
          row.ok = false
          row.alerting = false
          row.consecutiveFailures = 0
          row.error = "Disabled"
        } else if (!previous || previous.disabled) {
          row.ok = false
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
    var previous = resultById(target.id)
    var failures = rawResult.ok ? 0 : ((previous && previous.consecutiveFailures) || 0) + 1
    var alerting = !rawResult.ok && failures >= target.failuresBeforeAlert
    var wasAlerting = previous ? previous.alerting === true : false
    var checkedAt = Number(rawResult.checkedAt || Date.now())
    var row = {
      id: target.id,
      name: target.name,
      type: target.type,
      label: Model.targetLabel(target),
      disabled: false,
      ok: rawResult.ok === true,
      alerting: alerting,
      checking: false,
      statusCode: Number(rawResult.statusCode || 0),
      latencyMs: Number(rawResult.latencyMs || 0),
      error: String(rawResult.error || ""),
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

    if (alerting && !wasAlerting) {
      sendNotification(
        target.name + " is down",
        row.error || Model.resultDetail(row),
        "critical",
        "󰅚"
      )
    } else if (row.ok && wasAlerting) {
      sendNotification(
        target.name + " recovered",
        Model.resultDetail(row),
        "normal",
        "󰄬"
      )
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfig(text())
    onLoadFailed: function(error) {
      root.configError = "Create " + root.configPath + " from config.example.json"
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
    command: ["mkdir", "-p", root.stateDir]
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
