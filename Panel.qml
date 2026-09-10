import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.keithnyc.omanetwatch"
  ipcTarget: "io.github.keithnyc.omanetwatch"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property var monitorService: bar && bar.shell
    ? bar.shell.serviceFor("io.github.keithnyc.omanetwatch")
    : null
  readonly property var rows: monitorService ? monitorService.results : []
  readonly property int problemCount: monitorService ? monitorService.problemCount : 0
  readonly property bool checking: monitorService ? monitorService.checking : false
  readonly property int historyRevision: monitorService ? monitorService.historyRevision : 0
  property double now: Date.now()
  property bool manageMode: false
  property bool editorOpen: false
  property string deleteTargetId: ""
  property string deleteTargetName: ""
  property string mutationError: ""

  onOpenedChanged: if (!opened) {
    manageMode = false
    editorOpen = false
    deleteConfirm.opened = false
  }

  function startAdd() {
    mutationError = ""
    editorOpen = true
    manageMode = false
    Qt.callLater(function() { targetEditor.load(null, "") })
  }

  function startEdit(id) {
    if (!monitorService) return
    var target = monitorService.targetConfig(id)
    if (!target) {
      mutationError = "Target no longer exists"
      return
    }
    mutationError = ""
    editorOpen = true
    manageMode = false
    Qt.callLater(function() { targetEditor.load(target, id) })
  }

  function saveEditor(target, originalId) {
    if (!monitorService) return
    var error = monitorService.saveTarget(originalId, target)
    targetEditor.errorText = error
    if (!error) editorOpen = false
  }

  function askRemove(id, name) {
    deleteTargetId = id
    deleteTargetName = name
    deleteConfirm.opened = true
  }

  function confirmRemove() {
    deleteConfirm.opened = false
    if (!monitorService || !deleteTargetId) return
    mutationError = monitorService.removeTarget(deleteTargetId)
    deleteTargetId = ""
    deleteTargetName = ""
  }

  function statusSummary() {
    if (!root.monitorService || root.problemCount === 0)
      return root.rows.length > 0 ? "All systems operational" : "OmaNetWatch"
    var parts = []
    if (root.monitorService.outageCount > 0) parts.push(root.monitorService.outageCount + " outage" + (root.monitorService.outageCount === 1 ? "" : "s"))
    if (root.monitorService.degradedCount > 0) parts.push(root.monitorService.degradedCount + " degraded")
    if (root.monitorService.unknownCount > 0) parts.push(root.monitorService.unknownCount + " unknown")
    return parts.join(" · ")
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.now = Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.editorOpen) root.editorOpen = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(10)

        Row {
          visible: !root.editorOpen
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - addButton.width - manageButton.width - refreshButton.width - parent.spacing * 3
            text: root.statusSummary()
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          Button {
            id: addButton
            iconText: "+"
            tooltipText: "Add service"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            focusable: true
            onClicked: root.startAdd()
          }

          Button {
            id: manageButton
            iconText: "󰏫"
            tooltipText: root.manageMode ? "Done managing" : "Manage services"
            selected: root.manageMode
            foreground: root.bar ? root.bar.foreground : Color.foreground
            focusable: true
            onClicked: root.manageMode = !root.manageMode
          }

          Button {
            id: refreshButton
            iconText: "󰑐"
            tooltipText: "Check all now"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            iconSpinning: root.checking
            onClicked: if (root.monitorService) root.monitorService.checkAllNow()
          }
        }

        TargetEditor {
          id: targetEditor
          visible: root.editorOpen
          width: parent.width
          foreground: root.bar ? root.bar.foreground : Color.foreground
          accent: Color.accent
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onSaveRequested: function(target, originalId) { root.saveEditor(target, originalId) }
          onCanceled: root.editorOpen = false
        }

        Text {
          visible: !root.editorOpen && root.monitorService && root.monitorService.configError !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: root.monitorService ? root.monitorService.configError : ""
          color: Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          visible: !root.editorOpen && root.mutationError !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: root.mutationError
          color: Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {
          visible: !root.editorOpen && root.rows.length > 0
          foreground: root.bar ? root.bar.foreground : Color.foreground
        }

        Repeater {
          model: root.editorOpen ? [] : root.rows

          Item {
            id: endpointRow
            required property var modelData
            readonly property var samples: {
              root.historyRevision
              return root.monitorService ? root.monitorService.historyFor(modelData.id) : []
            }
            width: content.width
            height: Style.space(70)

            Rectangle {
              id: statusDot
              width: Style.space(9)
              height: width
              radius: width / 2
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.topMargin: Style.space(7)
              color: modelData.disabled ? Color.muted
                : modelData.checking ? Color.accent
                : modelData.state === "outage" ? Color.urgent
                : modelData.state === "degraded" ? Color.accent
                : modelData.state === "unknown" ? Color.muted
                : (root.bar ? root.bar.foreground : Color.foreground)
            }

            Column {
              anchors.left: statusDot.right
              anchors.leftMargin: Style.space(10)
              anchors.right: chartColumn.left
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(2)

              Row {
                width: parent.width

                Text {
                  width: parent.width - checkedText.width - Style.space(8)
                  text: modelData.name
                  elide: Text.ElideRight
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                }

                Text {
                  id: checkedText
                  text: Model.relativeTime(modelData.checkedAt, root.now)
                  color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35)
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                width: parent.width
                text: Model.resultDetail(modelData)
                elide: Text.ElideRight
                color: modelData.state === "outage" ? Color.urgent
                  : modelData.state === "degraded" ? Color.accent
                  : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.2)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                id: sourceText
                width: parent.width
                text: modelData.label || ""
                elide: Text.ElideMiddle
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption

                MouseArea {
                  anchors.fill: parent
                  enabled: !!modelData.sourceUrl
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: Qt.openUrlExternally(modelData.sourceUrl)
                }
              }
            }

            Column {
              id: chartColumn
              visible: !root.manageMode
              width: Style.space(118)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Sparkline {
                width: parent.width
                height: Style.space(34)
                history: endpointRow.samples
                lineColor: root.bar ? root.bar.foreground : Color.foreground
                failureColor: Color.urgent
                mutedColor: Color.muted
                opacity: modelData.disabled ? 0.45 : 1
              }

              Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                text: Model.historySummary(endpointRow.samples)
                elide: Text.ElideLeft
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.35)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              visible: root.manageMode
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              PanelActionButton {
                iconText: modelData.disabled ? "󰐕" : "󰒘"
                tooltipText: modelData.disabled ? "Enable" : "Disable"
                foreground: root.bar ? root.bar.foreground : Color.foreground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                focusable: true
                onClicked: {
                  if (root.monitorService)
                    root.mutationError = root.monitorService.setTargetEnabled(modelData.id, modelData.disabled)
                }
              }

              PanelActionButton {
                iconText: "󰏫"
                tooltipText: "Edit"
                foreground: root.bar ? root.bar.foreground : Color.foreground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                focusable: true
                onClicked: root.startEdit(modelData.id)
              }

              PanelActionButton {
                iconText: "󰆴"
                tooltipText: "Remove"
                foreground: root.bar ? root.bar.foreground : Color.foreground
                hoverColor: Color.urgent
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                focusable: true
                onClicked: root.askRemove(modelData.id, modelData.name)
              }
            }
          }
        }

        Text {
          visible: !root.editorOpen && root.rows.length === 0 && (!root.monitorService || root.monitorService.configError === "")
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "No services configured · press + to add one"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          visible: !root.editorOpen
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Right-click the bar icon to check now"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.45)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
        }
      }

      ConfirmDialog {
        id: deleteConfirm
        anchors.fill: parent
        z: 20
        message: "Remove " + root.deleteTargetName + "?"
        cancelText: "Cancel"
        confirmText: "Remove"
        foreground: root.bar ? root.bar.foreground : Color.foreground
        background: Color.popups.background
        onCanceled: opened = false
        onConfirmed: root.confirmRemove()
      }
    }
  }
}
