import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "openrouter.spending"
  ipcTarget: "openrouter.spending"
  manageIpc: false

  property var anchorItem: null
  property bool cursorActive: false
  property string statusText: "Loading OpenRouter usage…"
  property string lastUpdated: ""
  property real daily: 0
  property real monthly: 0
  property real total: 0
  property real remaining: -1
  property real limit: -1
  property string keyLabel: ""
  property var models: []
  property string modelsError: ""
  property string errorText: ""
  property bool loading: false
  readonly property int rowsNeeded: Math.max(1, models.length)
  readonly property int popupHeight: Math.max(0, Math.min(popup.screen ? popup.screen.height - Style.gapsOut * 2 : 600, contentColumn.implicitHeight + Style.space(40)))
  property int refreshSerial: 0

  function money(value) {
    var n = Number(value)
    return "$" + (isFinite(n) ? n : 0).toFixed(2)
  }

  function refresh() {
    if (loading) return
    statusText = "Fetching usage…"
    errorText = ""
    loading = true
    fetchProc.command = ["python3", Qt.resolvedUrl("fetch.py").toString().replace("file://", "")]
    fetchProc.running = true
  }

  function open() { root.controller.show(); root.refresh() }
  function openFromHotkey() { open() }
  function close() { root.controller.hide() }
  function toggle() { if (root.opened) close(); else open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root, direction)
    return false
  }

  // KeyboardPanel coordinates popout handoffs against the bar widget owner.
  property bool popoutSwitchClosing: false
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  IpcHandler {
    target: "openrouter.spending"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  Process {
    id: fetchProc
    running: false
    stdout: StdioCollector { onStreamFinished: root.handleResponse(String(text || "")) }
    stderr: StdioCollector { onStreamFinished: function(text) { if (String(text || "").trim() !== "") root.errorText = String(text).trim().slice(0, 220) } }
    onExited: function(exitCode) {
      root.loading = false
      if (exitCode !== 0 && root.errorText === "") root.errorText = "OpenRouter request failed (exit " + exitCode + ")"
      if (root.errorText !== "") root.statusText = root.errorText
    }
  }

  function handleResponse(raw) {
    var data = null
    try { data = JSON.parse(raw) } catch (e) {
      errorText = "Could not read OpenRouter response"
      statusText = errorText
      return
    }
    if (!data || data.error) {
      errorText = data && data.error ? String(data.error) : "OpenRouter returned no usage data"
      statusText = errorText
      return
    }
    daily = Number(data.daily || 0)
    monthly = Number(data.monthly || 0)
    total = Number(data.total || 0)
    limit = data.limit === null || data.limit === undefined ? -1 : Number(data.limit)
    remaining = data.remaining === null || data.remaining === undefined ? -1 : Number(data.remaining)
    keyLabel = String(data.label || "")
    models = Array.isArray(data.models) ? data.models : []
    modelsError = String(data.models_error || "")
    lastUpdated = Qt.formatDateTime(new Date(), "HH:mm")
    statusText = "Updated " + lastUpdated
    errorText = ""
  }

  onOpenedChanged: if (opened) root.refresh()

  Timer {
    interval: 300000
    repeat: true
    running: true
    onTriggered: if (root.opened) root.refresh()
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(440))
    contentHeight: popup.fittedContentHeight(Math.min(contentColumn.implicitHeight, Math.max(Style.space(300), popup.screen.height - Style.gapsOut * 4)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(14)

        Row {
          width: parent.width
          spacing: Style.space(12)
          Text {
            text: "󰄖"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
              text: "OpenRouter"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              text: root.keyLabel ? "Key · " + root.keyLabel : root.statusText
              color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.bar ? root.bar.foreground : Color.foreground; opacity: 0.12 }

        Row {
          width: parent.width
          spacing: Style.space(10)
          Repeater {
            model: [
              { title: "TODAY", amount: root.money(root.daily) },
              { title: "THIS MONTH", amount: root.money(root.monthly) }
            ]
            delegate: Rectangle {
              required property var modelData
              width: (contentColumn.width - Style.space(10)) / 2
              height: Style.space(78)
              radius: Style.cornerRadius
              color: root.bar ? Qt.alpha(root.bar.foreground, 0.055) : "#11000000"
              Column {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(13)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(5)
                Text {
                  text: modelData.title
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.5) : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  font.letterSpacing: 1
                }
                Text {
                  text: modelData.amount
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.display
                  font.bold: true
                }
              }
            }
          }
        }

        Row {
          width: parent.width
          visible: root.total > 0 || root.limit >= 0
          spacing: Style.space(6)
          Text {
            text: "All time  " + root.money(root.total)
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
          }
          Text {
            visible: root.limit >= 0
            text: "·  limit " + root.money(root.limit) + (root.remaining >= 0 ? " (" + root.money(root.remaining) + " left)" : "")
            color: root.bar ? Qt.darker(root.bar.foreground, 1.35) : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Rectangle { width: parent.width; height: Style.spacing.hairline; color: root.bar ? root.bar.foreground : Color.foreground; opacity: 0.12 }

        Column {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "MODEL USAGE · LAST 30 DAYS"
            color: root.bar ? Qt.darker(root.bar.foreground, 1.45) : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1
          }

          Text {
            visible: root.models.length === 0 && root.modelsError !== ""
            width: parent.width
            text: root.modelsError
            wrapMode: Text.Wrap
            color: root.bar ? Qt.darker(root.bar.foreground, 1.25) : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.models.length === 0 && root.modelsError === ""
            text: "No model activity in the last 30 completed UTC days."
            color: root.bar ? Qt.darker(root.bar.foreground, 1.35) : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.models
            delegate: Column {
              required property var modelData
              width: parent.width
              spacing: Style.space(3)

              Row {
                width: parent.width
                spacing: Style.space(10)

                Text {
                  width: Math.max(0, parent.width - spendLabel.implicitWidth - pctLabel.implicitWidth - Style.space(20))
                  text: modelData.model
                  elide: Text.ElideMiddle
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  id: spendLabel
                  text: root.money(modelData.spend)
                  color: root.bar ? root.bar.foreground : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
                Text {
                  id: pctLabel
                  text: Number(modelData.spend_pct || 0).toFixed(1) + "%"
                  color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.foreground
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                }
              }

              Text {
                text: Number(modelData.requests || 0).toLocaleString() + " requests · " + Number(modelData.tokens || 0).toLocaleString() + " tokens (" + Number(modelData.tokens_pct || 0).toFixed(1) + "%)"
                color: root.bar ? Qt.darker(root.bar.foreground, 1.5) : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.errorText !== ""
          text: root.errorText
          wrapMode: Text.Wrap
          color: root.bar ? root.bar.urgent : Color.urgent
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Row {
          spacing: Style.space(8)
          Text {
            text: root.loading ? "◌ Fetching…" : "↻ Refresh"
            color: root.bar ? Qt.darker(root.bar.foreground, 1.35) : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            text: " · " + root.lastUpdated
            visible: root.lastUpdated !== ""
            color: root.bar ? Qt.darker(root.bar.foreground, 1.6) : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
          TapHandler { onTapped: root.refresh() }
          HoverHandler { cursorShape: Qt.PointingHandCursor }
        }
      }
      }
    }
  }
}
