import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.keithnyc.omanetwatch"

  readonly property var monitorService: bar && bar.shell
    ? bar.shell.serviceFor(root.moduleName)
    : null
  readonly property int alertingCount: monitorService ? monitorService.alertingCount : 0
  readonly property int problemCount: monitorService ? monitorService.problemCount : 0
  readonly property bool checking: monitorService ? monitorService.checking : false
  readonly property string icon: alertingCount > 0 ? "󰅚" : (checking ? "󰑓" : "")

  function statusSummary() {
    if (!root.monitorService || root.problemCount === 0) return "OmaNetWatch"
    var parts = []
    if (root.monitorService.outageCount > 0) parts.push(root.monitorService.outageCount + " outage" + (root.monitorService.outageCount === 1 ? "" : "s"))
    if (root.monitorService.degradedCount > 0) parts.push(root.monitorService.degradedCount + " degraded")
    if (root.monitorService.unknownCount > 0) parts.push(root.monitorService.unknownCount + " unknown")
    return parts.join(" · ")
  }

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function checkAllNow(): void {
      if (root.monitorService) root.monitorService.checkAllNow()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.alertingCount > 0
    tooltipText: root.statusSummary()
    onPressed: function(b) {
      if (b === Qt.RightButton && root.monitorService) root.monitorService.checkAllNow()
      else root.toggle()
    }
  }
}
