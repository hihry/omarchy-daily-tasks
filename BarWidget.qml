import QtQuick
import qs.Commons
import qs.Ui

// Status bar widget for Daily Tasks: displays an icon + pending Today task
// count directly in the bar.
// - Left-click: toggle popup panel
// - Right-click: open directly to Tomorrow's task planner
// - Middle-click: open directly to Today's pending tasks
BarWidget {
  id: root
  moduleName: "hihry.tasks"

  readonly property var taskService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName)
    : null

  readonly property bool serviceReady: !!taskService && taskService.initialized === true
  readonly property int pendingCount: serviceReady ? taskService.todayPendingCount : 0
  readonly property int completedCount: serviceReady ? taskService.todayCompletedCount : 0
  readonly property int highPriorityCount: serviceReady ? taskService.todayHighPriorityPendingCount : 0
  readonly property int tomorrowCount: serviceReady ? taskService.tomorrowPendingCount : 0

  readonly property string barLabel: {
    var icon = pendingCount > 0 ? "󰅇" : "󰄬"
    if (vertical) return String(pendingCount)
    return icon + " " + String(pendingCount)
  }

  readonly property string statusTooltip: {
    if (!serviceReady) return "Daily Tasks"
    var todayPart = "Today: " + pendingCount + " pending"
    if (highPriorityCount > 0) todayPart += " (" + highPriorityCount + " high)"
    if (completedCount > 0) todayPart += ", " + completedCount + " done"
    var tomorrowPart = "Tomorrow: " + tomorrowCount + " planned"
    return todayPart + " · " + tomorrowPart + "\nLeft-click: Toggle · Right-click: Plan Tomorrow"
  }

  // Panel lifecycle forwarding required by the bar's popout coordinator
  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false
  readonly property real openPanelIndicatorWidth: button.labelWidth > 0
    ? button.labelWidth
    : Style.bar.iconCanvas
  readonly property real openPanelIndicatorHeight: Math.max(
    Style.space(10),
    Math.round(Style.bar.iconSlot * 0.55)
  )

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("taskService" in target) target.taskService = root.taskService
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function openTab(tabName) {
    if (!panelLoader.item) return
    if ("openToTab" in panelLoader.item) {
      panelLoader.item.openToTab(tabName)
    } else {
      panelLoader.item.open()
    }
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: Qt.callLater(injectPanel)
  onSettingsChanged: Qt.callLater(injectPanel)
  onTaskServiceChanged: Qt.callLater(injectPanel)
  Component.onCompleted: Qt.callLater(injectPanel)

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: root.injectPanel()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barLabel
    labelVisible: true
    hasVisualContent: true
    active: root.highPriorityCount > 0
    dimmed: !root.serviceReady
    tooltipText: root.statusTooltip
    horizontalMargin: 8.5
    verticalPadding: 6

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        root.openTab("tomorrow")
      } else if (buttonCode === Qt.MiddleButton) {
        root.openTab("today")
      } else {
        root.toggle()
      }
    }
  }
}
