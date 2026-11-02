pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "hihry.tasks"

  readonly property var panelScreen: anchorItem && anchorItem.QsWindow.window
    ? anchorItem.QsWindow.window.screen : null
  readonly property var mainScreen: {
    var best = null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (!best || screens[i].width * screens[i].height > best.width * best.height)
        best = screens[i]
    }
    return best
  }
  ipcTarget: panelScreen && panelScreen === mainScreen ? moduleName : ""

  property var anchorItem: null
  property var hostWidget: null
  property var taskService: null
  readonly property var barIdentity: hostWidget || root

  readonly property bool ready: !!taskService && taskService.initialized === true
  readonly property color foreground: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color muted: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // UI state
  property string activeTab: "today"       // "today" | "tomorrow"
  property string newPriority: "normal"    // "high" | "normal" | "low"
  property string editingTaskId: ""
  property string editingTaskText: ""

  readonly property var currentTasks: {
    if (!ready) return []
    return activeTab === "tomorrow" ? taskService.tomorrowTasks : taskService.todayTasks
  }

  readonly property int todayPending: ready ? taskService.todayPendingCount : 0
  readonly property int todayDone: ready ? taskService.todayCompletedCount : 0
  readonly property int tomorrowPending: ready ? taskService.tomorrowPendingCount : 0
  readonly property int tomorrowDone: ready ? taskService.tomorrowCompletedCount : 0

  readonly property string activeDateSubtitle: {
    if (!ready) return ""
    return activeTab === "tomorrow"
      ? "Tomorrow · " + taskService.formatReadableDate(1)
      : "Today · " + taskService.formatReadableDate(0)
  }

  function priorityColor(priority) {
    if (priority === "high") return root.urgent
    if (priority === "normal") return root.accent
    return root.muted
  }

  function priorityShortLabel(priority) {
    if (priority === "high") return "! HIGH"
    if (priority === "normal") return "• NORM"
    return "↓ LOW"
  }

  function openToTab(tabName) {
    if (tabName === "today" || tabName === "tomorrow") {
      root.activeTab = tabName
    }
    if (!root.opened) {
      root.open()
    } else {
      Qt.callLater(function() { taskInput.forceActiveFocus() })
    }
  }

  function submitNewTask() {
    if (!ready) return
    var text = taskInput.text.trim()
    if (text === "") return
    if (taskService.addTask(text, root.activeTab, root.newPriority)) {
      taskInput.text = ""
      Qt.callLater(function() { taskInput.forceActiveFocus() })
    }
  }

  function startEditTask(task) {
    if (!task) return
    editingTaskId = task.id
    editingTaskText = task.text
  }

  function commitEditTask() {
    if (!ready || editingTaskId === "") return
    var cleaned = editingTaskText.trim()
    if (cleaned !== "") {
      taskService.updateTaskText(editingTaskId, cleaned)
    }
    editingTaskId = ""
    editingTaskText = ""
  }

  function cancelEditTask() {
    editingTaskId = ""
    editingTaskText = ""
  }

  onOpenedChanged: {
    if (opened) {
      if (ready) taskService.checkRollover()
      cancelEditTask()
      Qt.callLater(function() {
        if (root.opened) taskInput.forceActiveFocus()
      })
    } else {
      cancelEditTask()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: taskInput
    padding: Style.space(14)
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight + Style.space(8), Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: taskInput.activeFocus || root.editingTaskId !== ""
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        root.activeTab = root.activeTab === "today" ? "tomorrow" : "today"
      }

      Column {
        id: mainColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // --- Header --------------------------------------------------------
        Item {
          width: parent.width
          implicitHeight: headerLeft.implicitHeight

          Column {
            id: headerLeft
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Row {
              spacing: Style.space(6)
              Text {
                textFormat: Text.PlainText
                text: "󰅇"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: "Daily Tasks"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              textFormat: Text.PlainText
              text: root.activeDateSubtitle
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // Summary pill on the right
          Rectangle {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: summaryRow.implicitWidth + Style.space(16)
            height: summaryRow.implicitHeight + Style.space(8)
            radius: Style.cornerRadius > 0 ? Style.space(6) : 0
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.10)
            border.width: 1
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)

            Row {
              id: summaryRow
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: root.todayPending > 0
                  ? root.todayPending + " left today"
                  : "All done today!"
                color: root.todayPending > 0 ? root.foreground : root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }
        }

        // --- Day Tabs ("Today" vs "Tomorrow") ------------------------------
        Row {
          id: tabRow
          width: parent.width
          spacing: Style.space(6)

          readonly property real tabWidth: Math.floor((width - spacing) / 2)

          Button {
            width: tabRow.tabWidth
            text: "Today (" + root.todayPending + ")"
            iconText: root.todayPending > 0 ? "󰃭" : "󰄬"
            selected: root.activeTab === "today"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            tooltipText: "Pending and completed tasks for today"
            onClicked: {
              root.activeTab = "today"
              Qt.callLater(function() { taskInput.forceActiveFocus() })
            }
          }

          Button {
            width: tabRow.tabWidth
            text: "Tomorrow (" + root.tomorrowPending + ")"
            iconText: "󰃰"
            selected: root.activeTab === "tomorrow"
            bordered: true
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            tooltipText: "Plan tasks for tomorrow (auto-moves to Today at midnight)"
            onClicked: {
              root.activeTab = "tomorrow"
              Qt.callLater(function() { taskInput.forceActiveFocus() })
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        // --- Quick-Add Task Box --------------------------------------------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Row {
            id: inputRow
            width: parent.width
            spacing: Style.space(6)

            TextField {
              id: taskInput
              width: parent.width - addBtn.implicitWidth - inputRow.spacing
              placeholderText: root.activeTab === "tomorrow"
                ? "Add a task for tomorrow… (Enter)"
                : "Add a pending task for today… (Enter)"
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily

              onAccepted: root.submitNewTask()
              Keys.onEscapePressed: function(event) {
                root.close()
                event.accepted = true
              }
              Keys.onTabPressed: function(event) {
                root.activeTab = root.activeTab === "today" ? "tomorrow" : "today"
                event.accepted = true
              }
            }

            Button {
              id: addBtn
              text: "Add"
              iconText: "+"
              bordered: true
              selected: taskInput.text.trim() !== ""
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              tooltipText: root.activeTab === "tomorrow"
                ? "Add task to Tomorrow"
                : "Add task to Today"
              onClicked: root.submitNewTask()
            }
          }

          // Priority selector row for new task
          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              textFormat: Text.PlainText
              text: "Priority:"
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            Repeater {
              model: [
                { key: "high", label: "! High", tip: "High priority (pinned to top)" },
                { key: "normal", label: "• Normal", tip: "Normal priority" },
                { key: "low", label: "↓ Low", tip: "Low priority" }
              ]

              delegate: Button {
                required property var modelData
                text: modelData.label
                selected: root.newPriority === modelData.key
                bordered: true
                fontSize: Style.font.caption
                horizontalPadding: Style.space(8)
                verticalPadding: Style.space(3)
                foreground: modelData.key === "high" && root.newPriority === "high"
                  ? root.urgent
                  : root.foreground
                accent: modelData.key === "high" ? root.urgent : root.accent
                fontFamily: root.fontFamily
                tooltipText: modelData.tip
                onClicked: {
                  root.newPriority = modelData.key
                  Qt.callLater(function() { taskInput.forceActiveFocus() })
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        // --- Task List Header ----------------------------------------------
        Item {
          width: parent.width
          implicitHeight: sectionTitle.implicitHeight

          PanelSectionHeader {
            id: sectionTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            fontFamily: root.fontFamily
            text: root.activeTab === "tomorrow"
              ? "TOMORROW'S PLAN (" + root.tomorrowPending + " PLANNED)"
              : "TODAY'S TASKS (" + root.todayPending + " PENDING"
                + (root.todayDone > 0 ? ", " + root.todayDone + " DONE)" : ")")
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.currentTasks.length > 0
            textFormat: Text.PlainText
            text: "Double-click text to edit"
            color: Qt.darker(root.foreground, 1.8)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // --- Empty State ---------------------------------------------------
        Rectangle {
          visible: root.currentTasks.length === 0
          width: parent.width
          height: Style.space(96)
          radius: Style.cornerRadius > 0 ? Style.space(8) : 0
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.03)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

          Column {
            anchors.centerIn: parent
            spacing: Style.space(6)
            width: parent.width - Style.space(24)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: root.activeTab === "tomorrow"
                ? "󰃰  No tasks planned for tomorrow yet"
                : "󰄬  No tasks for today yet"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              textFormat: Text.PlainText
              text: root.activeTab === "tomorrow"
                ? "Type above to plan tomorrow's tasks. At midnight, they automatically roll over into Today!"
                : "Add your tasks for today above, or switch to the Tomorrow tab to plan ahead."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // --- Scrollable Task List ------------------------------------------
        Flickable {
          id: taskFlick
          visible: root.currentTasks.length > 0
          width: parent.width
          height: Math.min(taskListColumn.implicitHeight, Style.space(310))
          contentWidth: width
          contentHeight: taskListColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          QQC.ScrollBar.vertical: QQC.ScrollBar {
            policy: QQC.ScrollBar.AsNeeded
          }

          Column {
            id: taskListColumn
            width: taskFlick.width
            spacing: Style.space(6)

            Repeater {
              model: root.currentTasks

              delegate: Rectangle {
                id: taskRow
                required property var modelData
                required property int index

                readonly property bool isDone: modelData.done === true
                readonly property bool isEditing: root.editingTaskId === modelData.id
                readonly property color priColor: root.priorityColor(modelData.priority)

                width: taskListColumn.width
                implicitHeight: isEditing
                  ? editRow.implicitHeight + Style.space(14)
                  : Math.max(Style.space(36), rowContent.implicitHeight + Style.space(14))
                radius: Style.cornerRadius > 0 ? Style.space(6) : 0
                color: isDone
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.02)
                  : (rowHover.hovered
                    ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04))
                border.width: 1
                border.color: isDone
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                  : (modelData.priority === "high"
                    ? Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.40)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14))

                HoverHandler {
                  id: rowHover
                }

                // Normal display mode
                Item {
                  id: rowContent
                  visible: !taskRow.isEditing
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(6)
                  implicitHeight: Math.max(textWrapper.implicitHeight, actionsRow.implicitHeight)

                  // Checkbox button
                  Rectangle {
                    id: checkBtn
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(18)
                    height: Style.space(18)
                    radius: Style.cornerRadius > 0 ? Style.space(4) : 0
                    color: taskRow.isDone
                      ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25)
                      : "transparent"
                    border.width: 1.5
                    border.color: taskRow.isDone
                      ? root.accent
                      : (checkMouse.containsMouse ? root.accent : root.muted)

                    Text {
                      anchors.centerIn: parent
                      visible: taskRow.isDone
                      textFormat: Text.PlainText
                      text: "✓"
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    MouseArea {
                      id: checkMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.ready) root.taskService.toggleTask(taskRow.modelData.id)
                      }
                    }
                  }

                  // Priority badge (click to cycle priority)
                  Rectangle {
                    id: priBadge
                    anchors.left: checkBtn.right
                    anchors.leftMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    width: priText.implicitWidth + Style.space(10)
                    height: priText.implicitHeight + Style.space(4)
                    radius: Style.cornerRadius > 0 ? Style.space(4) : 0
                    opacity: taskRow.isDone ? 0.45 : 1.0
                    color: Qt.rgba(taskRow.priColor.r, taskRow.priColor.g, taskRow.priColor.b, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(taskRow.priColor.r, taskRow.priColor.g, taskRow.priColor.b, 0.40)

                    Text {
                      id: priText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: root.priorityShortLabel(taskRow.modelData.priority)
                      color: taskRow.priColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    MouseArea {
                      id: priMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.ready) root.taskService.cycleTaskPriority(taskRow.modelData.id)
                      }
                    }

                    PanelToolTip {
                      visible: priMouse.containsMouse
                      text: "Click to cycle priority (Normal → High → Low)"
                      fontFamily: root.fontFamily
                    }
                  }

                  // Task text + optional carriedOver tag
                  Item {
                    id: textWrapper
                    anchors.left: priBadge.right
                    anchors.right: actionsRow.left
                    anchors.leftMargin: Style.space(8)
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: textCol.implicitHeight

                    Column {
                      id: textCol
                      width: parent.width
                      spacing: Style.space(2)

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: taskRow.modelData.text
                        wrapMode: Text.Wrap
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.strikeout: taskRow.isDone
                        color: taskRow.isDone ? root.muted : root.foreground
                      }

                      Text {
                        visible: taskRow.modelData.carriedOver === true && !taskRow.isDone
                        textFormat: Text.PlainText
                        text: "↪ carried over from yesterday"
                        color: root.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.ready) root.taskService.toggleTask(taskRow.modelData.id)
                      }
                      onDoubleClicked: {
                        root.startEditTask(taskRow.modelData)
                      }
                    }
                  }

                  // Right-side action buttons: Edit, Move (Today <-> Tomorrow), Delete
                  Row {
                    id: actionsRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(2)

                    PanelActionButton {
                      iconText: "󰏫"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      tooltipText: "Edit task"
                      onClicked: root.startEditTask(taskRow.modelData)
                    }

                    PanelActionButton {
                      iconText: root.activeTab === "today" ? "󰁔" : "󰁍"
                      foreground: root.foreground
                      hoverColor: root.accent
                      fontFamily: root.fontFamily
                      tooltipText: root.activeTab === "today"
                        ? "Postpone to Tomorrow"
                        : "Move to Today"
                      onClicked: {
                        if (!root.ready) return
                        var targetDay = root.activeTab === "today" ? "tomorrow" : "today"
                        root.taskService.moveTaskDay(taskRow.modelData.id, targetDay)
                      }
                    }

                    PanelActionButton {
                      iconText: "󰅖"
                      foreground: root.foreground
                      hoverColor: root.urgent
                      fontFamily: root.fontFamily
                      tooltipText: "Delete task"
                      onClicked: {
                        if (root.ready) root.taskService.deleteTask(taskRow.modelData.id)
                      }
                    }
                  }
                }

                // Inline edit mode
                Row {
                  id: editRow
                  visible: taskRow.isEditing
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(6)

                  TextField {
                    id: inlineEditField
                    width: parent.width - saveEditBtn.implicitWidth - cancelEditBtn.implicitWidth - editRow.spacing * 2
                    text: root.editingTaskText
                    foreground: root.foreground
                    accent: root.accent
                    font.family: root.fontFamily
                    onTextChanged: {
                      if (taskRow.isEditing) root.editingTaskText = text
                    }
                    onVisibleChanged: {
                      if (visible) {
                        text = root.editingTaskText
                        Qt.callLater(function() {
                          inlineEditField.forceActiveFocus()
                          inlineEditField.selectAll()
                        })
                      }
                    }
                    onAccepted: root.commitEditTask()
                    Keys.onEscapePressed: function(event) {
                      root.cancelEditTask()
                      event.accepted = true
                    }
                  }

                  PanelActionButton {
                    id: saveEditBtn
                    iconText: "✓"
                    foreground: root.accent
                    hoverColor: root.accent
                    bordered: true
                    fontFamily: root.fontFamily
                    tooltipText: "Save changes (Enter)"
                    onClicked: root.commitEditTask()
                  }

                  PanelActionButton {
                    id: cancelEditBtn
                    iconText: "󰅖"
                    foreground: root.muted
                    hoverColor: root.urgent
                    bordered: true
                    fontFamily: root.fontFamily
                    tooltipText: "Cancel (Esc)"
                    onClicked: root.cancelEditTask()
                  }
                }
              }
            }
          }
        }

        // --- Footer / Bulk Actions -----------------------------------------
        PanelSeparator {
          foreground: root.foreground
        }

        Item {
          width: parent.width
          implicitHeight: Math.max(footerHint.implicitHeight, footerActions.implicitHeight)

          Text {
            id: footerHint
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.activeTab === "tomorrow"
              ? "Auto-rolls into Today at midnight"
              : (root.todayDone > 0
                ? "✓ Synced (" + root.todayDone + ") to ~/Documents/Cyber/cyber.md"
                : "Done tasks sync to ~/Documents/Cyber/cyber.md")
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            id: footerActions
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            Button {
              visible: root.activeTab === "today" && root.todayPending > 0
              text: "Postpone all →"
              bordered: true
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              tooltipText: "Move all unfinished Today tasks to Tomorrow"
              onClicked: {
                if (root.ready) root.taskService.postponeAllPendingToday()
              }
            }

            Button {
              visible: root.activeTab === "tomorrow" && root.tomorrowPending > 0
              text: "← Move all to Today"
              bordered: true
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              tooltipText: "Pull all Tomorrow tasks into Today now"
              onClicked: {
                if (root.ready) root.taskService.moveAllTomorrowToToday()
              }
            }

            Button {
              visible: (root.activeTab === "today" && root.todayDone > 0)
                || (root.activeTab === "tomorrow" && root.tomorrowDone > 0)
              text: "Clear done"
              bordered: true
              fontSize: Style.font.caption
              horizontalPadding: Style.space(8)
              verticalPadding: Style.space(3)
              foreground: root.foreground
              accent: root.urgent
              fontFamily: root.fontFamily
              tooltipText: "Remove completed tasks from this list"
              onClicked: {
                if (root.ready) root.taskService.clearCompleted(root.activeTab)
              }
            }
          }
        }
      }
    }
  }
}
