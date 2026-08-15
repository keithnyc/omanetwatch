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
  readonly property int downCount: monitorService ? monitorService.downCount : 0
  readonly property bool checking: monitorService ? monitorService.checking : false
  readonly property string icon: downCount > 0 ? "󰅚" : (checking ? "󰑓" : "")

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
    active: root.downCount > 0
    tooltipText: root.downCount > 0
      ? root.downCount + " endpoint" + (root.downCount === 1 ? "" : "s") + " down"
      : "OmaNetWatch"
    onPressed: function(b) {
      if (b === Qt.RightButton && root.monitorService) root.monitorService.checkAllNow()
      else root.toggle()
    }
  }
}
