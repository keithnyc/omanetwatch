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
  readonly property int downCount: monitorService ? monitorService.downCount : 0
  readonly property bool checking: monitorService ? monitorService.checking : false
  readonly property int historyRevision: monitorService ? monitorService.historyRevision : 0
  property double now: Date.now()

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
      onCloseRequested: root.close()
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
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width - refreshButton.width - parent.spacing
            text: root.downCount > 0
              ? root.downCount + " endpoint" + (root.downCount === 1 ? "" : "s") + " down"
              : (root.rows.length > 0 ? "All systems operational" : "OmaNetWatch")
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
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

        Text {
          visible: root.monitorService && root.monitorService.configError !== ""
          width: parent.width
          wrapMode: Text.Wrap
          text: root.monitorService ? root.monitorService.configError : ""
          color: Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {
          visible: root.rows.length > 0
          foreground: root.bar ? root.bar.foreground : Color.foreground
        }

        Repeater {
          model: root.rows

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
                : modelData.ok ? (root.bar ? root.bar.foreground : Color.foreground)
                : modelData.alerting ? Color.urgent
                : Color.muted
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
                color: modelData.alerting ? Color.urgent
                  : Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.2)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                width: parent.width
                text: modelData.label || ""
                elide: Text.ElideMiddle
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Column {
              id: chartColumn
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
          }
        }

        Text {
          visible: root.rows.length === 0 && (!root.monitorService || root.monitorService.configError === "")
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "No endpoints configured"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          text: "Right-click the bar icon to check now"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.45)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }
        }
      }
    }
  }
}
