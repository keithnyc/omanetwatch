import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string originalId: ""
  property string targetType: "http"
  property bool targetEnabled: true
  property int intervalSeconds: 60
  property int timeoutSeconds: 5
  property int failuresBeforeAlert: 2
  property int expectedStatus: 200
  property int tcpPort: 443
  property string errorText: ""
  property bool initializing: false

  signal saveRequested(var target, string originalId)
  signal canceled()

  width: parent ? parent.width : Style.space(500)
  spacing: Style.space(10)

  function mappingValues(mapping, state) {
    var values = []
    if (!mapping) return ""
    for (var key in mapping) if (String(mapping[key]).toLowerCase() === state) values.push(key)
    return values.join(", ")
  }

  function applyStatuspageDefaults() {
    statusPathField.text = "status.indicator"
    reasonPathField.text = "status.description"
    operationalField.text = "none"
    degradedField.text = "minor, maintenance"
    outageField.text = "major, critical"
    unknownField.text = ""
  }

  function load(target, normalizedId) {
    var value = target || ({})
    initializing = true
    originalId = normalizedId || ""
    errorText = ""
    nameField.text = String(value.name || "")
    idField.text = String(value.id || normalizedId || "")
    targetType = String(value.type || "http").toLowerCase()
    targetEnabled = value.enabled !== false
    urlField.text = String(value.url || "")
    hostField.text = String(value.host || "")
    expectedStatus = Number(value.expectedStatus || 200)
    tcpPort = Number(value.port || 443)
    intervalSeconds = Number(value.intervalSeconds || 60)
    timeoutSeconds = Number(value.timeoutSeconds || 5)
    failuresBeforeAlert = Number(value.failuresBeforeAlert || 2)
    statusPathField.text = String(value.statusPath || "")
    reasonPathField.text = String(value.reasonPath || "")
    sourceUrlField.text = String(value.sourceUrl || "")
    operationalField.text = mappingValues(value.statusMap, "operational")
    degradedField.text = mappingValues(value.statusMap, "degraded")
    outageField.text = mappingValues(value.statusMap, "outage")
    unknownField.text = mappingValues(value.statusMap, "unknown")
    if (targetType === "json" && !value.statusMap) applyStatuspageDefaults()
    typeField.value = targetType
    enabledToggle.checked = targetEnabled
    expectedStatusField.value = expectedStatus
    tcpPortField.value = tcpPort
    timeoutField.value = timeoutSeconds
    intervalField.value = intervalSeconds
    failuresField.value = failuresBeforeAlert
    initializing = false
    Qt.callLater(function() { nameField.forceActiveFocus() })
  }

  function addMappingValues(mapping, raw, state) {
    var values = String(raw || "").split(",")
    for (var i = 0; i < values.length; i++) {
      var value = values[i].trim()
      if (!value) continue
      if (mapping[value] !== undefined && mapping[value] !== state)
        return "Status value '" + value + "' appears in more than one group"
      mapping[value] = state
    }
    return ""
  }

  function buildTarget() {
    errorText = ""
    var target = {
      name: nameField.text.trim(),
      type: targetType,
      enabled: targetEnabled,
      intervalSeconds: intervalSeconds,
      timeoutSeconds: timeoutSeconds,
      failuresBeforeAlert: failuresBeforeAlert
    }
    var id = idField.text.trim()
    if (id) target.id = id

    if (targetType === "tcp") {
      target.host = hostField.text.trim()
      target.port = tcpPort
    } else {
      target.url = urlField.text.trim()
      target.expectedStatus = expectedStatus
    }

    if (targetType === "json") {
      target.statusPath = statusPathField.text.trim()
      var reasonPath = reasonPathField.text.trim()
      var sourceUrl = sourceUrlField.text.trim()
      if (reasonPath) target.reasonPath = reasonPath
      if (sourceUrl) target.sourceUrl = sourceUrl
      var mapping = {}
      var mappingError = addMappingValues(mapping, operationalField.text, "operational")
        || addMappingValues(mapping, degradedField.text, "degraded")
        || addMappingValues(mapping, outageField.text, "outage")
        || addMappingValues(mapping, unknownField.text, "unknown")
      if (mappingError) {
        errorText = mappingError
        return null
      }
      target.statusMap = mapping
    } else if (targetType === "feed") {
      var feedSourceUrl = sourceUrlField.text.trim()
      if (feedSourceUrl) target.sourceUrl = feedSourceUrl
    }
    return target
  }

  function submit() {
    var target = buildTarget()
    if (target) saveRequested(target, originalId)
  }

  Row {
    width: parent.width
    spacing: Style.space(8)

    Button {
      iconText: "󰁍"
      tooltipText: "Back"
      foreground: root.foreground
      focusable: true
      onClicked: root.canceled()
    }

    Text {
      width: parent.width - saveButton.width - parent.spacing * 2 - Style.space(34)
      anchors.verticalCenter: parent.verticalCenter
      text: root.originalId ? "Edit service" : "Add service"
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
      font.bold: true
    }

    Button {
      id: saveButton
      text: "Save"
      iconText: "󰆓"
      bordered: true
      focusable: true
      foreground: root.foreground
      onClicked: root.submit()
    }
  }

  Text {
    visible: root.errorText !== ""
    width: parent.width
    text: root.errorText
    wrapMode: Text.WordWrap
    color: Color.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  FormTextField {
    id: nameField
    width: parent.width
    label: "Name"
    placeholderText: "My service"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    onAccepted: root.submit()
  }

  FormTextField {
    id: idField
    width: parent.width
    label: "Stable ID"
    placeholderText: "Derived from name when blank"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  Dropdown {
    id: typeField
    width: parent.width
    label: "Check type"
    value: "http"
    options: [
      { value: "http", label: "HTTP reachability" },
      { value: "tcp", label: "TCP port" },
      { value: "json", label: "JSON service status" },
      { value: "feed", label: "RSS/Atom incident feed" }
    ]
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    onChanged: function(value) {
      root.targetType = value
      if (!root.initializing && value === "json" && statusPathField.text === "") root.applyStatuspageDefaults()
      if (!root.initializing && value === "feed" && root.intervalSeconds === 60) {
        root.intervalSeconds = 300
        intervalField.value = 300
      }
    }
  }

  Toggle {
    id: enabledToggle
    width: parent.width
    label: "Enabled"
    description: root.targetType === "feed"
      ? "Poll the feed and notify about new or updated items"
      : "Run checks and send state-change notifications"
    checked: root.targetEnabled
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    onClicked: root.targetEnabled = !root.targetEnabled
  }

  FormTextField {
    id: urlField
    visible: root.targetType !== "tcp"
    width: parent.width
    label: root.targetType === "json" ? "JSON endpoint URL" : (root.targetType === "feed" ? "RSS/Atom feed URL" : "URL")
    placeholderText: root.targetType === "feed" ? "https://status.example.com/feed.xml" : "https://status.example.com/api/v2/status.json"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  FormTextField {
    id: hostField
    visible: root.targetType === "tcp"
    width: parent.width
    label: "Host"
    placeholderText: "example.com"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  Row {
    width: parent.width
    spacing: Style.space(10)

    NumberField {
      id: tcpPortField
      visible: root.targetType === "tcp"
      width: visible ? (parent.width - parent.spacing) / 2 : 0
      fieldWidth: width
      label: "Port"
      from: 1
      to: 65535
      value: root.tcpPort
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onModified: function(value) { root.tcpPort = value }
    }

    NumberField {
      id: expectedStatusField
      visible: root.targetType !== "tcp"
      width: visible ? (parent.width - parent.spacing) / 2 : 0
      fieldWidth: width
      label: "Expected HTTP"
      from: 100
      to: 599
      value: root.expectedStatus
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onModified: function(value) { root.expectedStatus = value }
    }

    NumberField {
      id: timeoutField
      width: (parent.width - parent.spacing) / 2
      fieldWidth: width
      label: "Timeout (seconds)"
      from: 1
      to: 300
      value: root.timeoutSeconds
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onModified: function(value) { root.timeoutSeconds = value }
    }
  }

  FormTextField {
    id: statusPathField
    visible: root.targetType === "json"
    width: parent.width
    label: "Status field"
    placeholderText: "status.indicator or /status/indicator"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  FormTextField {
    id: reasonPathField
    visible: root.targetType === "json"
    width: parent.width
    label: "Description field (optional)"
    placeholderText: "status.description"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  FormTextField {
    id: sourceUrlField
    visible: root.targetType === "json" || root.targetType === "feed"
    width: parent.width
    label: root.targetType === "feed" ? "Status page (optional)" : "Public status page (optional)"
    placeholderText: "https://status.example.com/"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  Text {
    visible: root.targetType === "json"
    width: parent.width
    text: "Provider values (comma separated)"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }

  FormTextField {
    id: operationalField
    visible: root.targetType === "json"
    width: parent.width
    label: "Operational"
    placeholderText: "none, operational"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  FormTextField {
    id: degradedField
    visible: root.targetType === "json"
    width: parent.width
    label: "Degraded"
    placeholderText: "minor, maintenance"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  FormTextField {
    id: outageField
    visible: root.targetType === "json"
    width: parent.width
    label: "Outage"
    placeholderText: "major, critical"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  FormTextField {
    id: unknownField
    visible: root.targetType === "json"
    width: parent.width
    label: "Unknown (optional)"
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
  }

  Row {
    width: parent.width
    spacing: Style.space(10)

    NumberField {
      id: intervalField
      width: root.targetType === "feed" ? parent.width : (parent.width - parent.spacing) / 2
      fieldWidth: width
      label: "Interval (seconds)"
      from: 5
      to: 86400
      value: root.intervalSeconds
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onModified: function(value) { root.intervalSeconds = value }
    }

    NumberField {
      id: failuresField
      visible: root.targetType !== "feed"
      width: visible ? (parent.width - parent.spacing) / 2 : 0
      fieldWidth: width
      label: "Checks before alert"
      from: 1
      to: 100
      value: root.failuresBeforeAlert
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      onModified: function(value) { root.failuresBeforeAlert = value }
    }
  }
}
