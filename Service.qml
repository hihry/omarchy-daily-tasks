import QtQuick
import Quickshell
import Quickshell.Io

// Headless task planner service. Loaded once at shell startup so task state
// and automatic midnight rollover stay consistent across all monitors and
// while the popup panel is closed.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || (homeDir + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy"
  readonly property string statePath: stateDir + "/daily-tasks.json"
  readonly property string cyberMdPath: homeDir + "/Documents/Cyber/cyber.md"

  readonly property int maxStateBytes: 65536
  property bool initialized: false
  property bool stateFileLoaded: false
  property string loadedStateText: ""
  property string lastSavedStateText: ""

  // Persisted state
  property string activeDate: ""
  property var tasks: []
  property int nextIdCounter: 1

  readonly property var validPriorities: ["high", "normal", "low"]
  readonly property var validDays: ["today", "tomorrow", "scheduled", "history"]

  function priorityRank(priority) {
    if (priority === "high") return 0
    if (priority === "normal") return 1
    return 2
  }

  function isValidDateKey(value) {
    return typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value.trim())
  }

  function sanitizeColor(value) {
    if (typeof value !== "string") return ""
    var trimmed = value.trim()
    return /^#[0-9A-Fa-f]{6}$/.test(trimmed) ? trimmed : ""
  }

  function formatDateKey(d) {
    var year = d.getFullYear()
    var month = String(d.getMonth() + 1).padStart(2, "0")
    var day = String(d.getDate()).padStart(2, "0")
    return year + "-" + month + "-" + day
  }

  function todayDateKey() {
    return formatDateKey(new Date())
  }

  function tomorrowDateKey() {
    var now = new Date()
    var tmr = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
    return formatDateKey(tmr)
  }

  function cutoffHistoryDateKey(daysBack) {
    var now = new Date()
    var cutoff = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (daysBack || 60))
    return formatDateKey(cutoff)
  }

  function dayRoleForDate(dateKey, isDone) {
    var todayKey = todayDateKey()
    var tomorrowKey = tomorrowDateKey()
    if (dateKey === todayKey) return "today"
    if (dateKey === tomorrowKey) return "tomorrow"
    if (dateKey > tomorrowKey) return "scheduled"
    return isDone ? "history" : "today"
  }

  function formatReadableDate(offsetDays) {
    var now = new Date()
    var target = new Date(now.getFullYear(), now.getMonth(), now.getDate() + (offsetDays || 0))
    return Qt.formatDate(target, "ddd, d MMM")
  }

  function sortedTasksForDay(dayKey) {
    var filtered = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (item && item.day === dayKey) filtered.push(item)
    }
    filtered.sort(function(a, b) {
      if (!!a.done !== !!b.done) return a.done ? 1 : -1
      var pa = root.priorityRank(a.priority)
      var pb = root.priorityRank(b.priority)
      if (pa !== pb) return pa - pb
      return (Number(a.createdAt) || 0) - (Number(b.createdAt) || 0)
    })
    return filtered
  }

  function sortedTasksForDate(dateKey) {
    var filtered = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (item && item.date === dateKey) filtered.push(item)
    }
    filtered.sort(function(a, b) {
      if (!!a.done !== !!b.done) return a.done ? 1 : -1
      var pa = root.priorityRank(a.priority)
      var pb = root.priorityRank(b.priority)
      if (pa !== pb) return pa - pb
      return (Number(a.createdAt) || 0) - (Number(b.createdAt) || 0)
    })
    return filtered
  }

  readonly property var todayTasks: sortedTasksForDay("today")
  readonly property var tomorrowTasks: sortedTasksForDay("tomorrow")

  readonly property int todayPendingCount: {
    var count = 0
    for (var i = 0; i < todayTasks.length; i++) {
      if (!todayTasks[i].done) count++
    }
    return count
  }

  readonly property int todayCompletedCount: {
    var count = 0
    for (var i = 0; i < todayTasks.length; i++) {
      if (todayTasks[i].done) count++
    }
    return count
  }

  readonly property int todayHighPriorityPendingCount: {
    var count = 0
    for (var i = 0; i < todayTasks.length; i++) {
      if (!todayTasks[i].done && todayTasks[i].priority === "high") count++
    }
    return count
  }

  readonly property int tomorrowPendingCount: {
    var count = 0
    for (var i = 0; i < tomorrowTasks.length; i++) {
      if (!tomorrowTasks[i].done) count++
    }
    return count
  }

  readonly property int tomorrowCompletedCount: {
    var count = 0
    for (var i = 0; i < tomorrowTasks.length; i++) {
      if (tomorrowTasks[i].done) count++
    }
    return count
  }

  readonly property int tomorrowTotalCount: tomorrowTasks.length

  function sanitizeTask(raw) {
    if (!raw || typeof raw !== "object") return null
    var text = String(raw.text || "").trim()
    if (text === "") return null
    var isDone = raw.done === true
    var todayKey = todayDateKey()
    var tomorrowKey = tomorrowDateKey()

    var rawDay = validDays.indexOf(raw.day) >= 0 ? String(raw.day) : "today"
    var dateKey = ""
    if (isValidDateKey(raw.date)) {
      dateKey = raw.date.trim()
    } else if (rawDay === "tomorrow") {
      dateKey = tomorrowKey
    } else {
      dateKey = todayKey
    }

    var day = dayRoleForDate(dateKey, isDone)
    var carriedOver = raw.carriedOver === true
    if (dateKey < todayKey && !isDone) {
      dateKey = todayKey
      day = "today"
      carriedOver = true
    }

    var priority = validPriorities.indexOf(raw.priority) >= 0 ? String(raw.priority) : "normal"
    var color = sanitizeColor(raw.color)
    var id = String(raw.id || "").trim()
    if (id === "") {
      id = "t_" + Date.now() + "_" + (nextIdCounter++)
    }
    return {
      id: id,
      text: text,
      day: day,
      date: dateKey,
      priority: priority,
      color: color,
      done: isDone,
      createdAt: Number(raw.createdAt) > 0 ? Number(raw.createdAt) : Date.now(),
      completedAt: isDone ? (Number(raw.completedAt) > 0 ? Number(raw.completedAt) : Date.now()) : 0,
      carriedOver: carriedOver
    }
  }

  function formatPriorityLabel(priority) {
    if (priority === "high") return "High"
    if (priority === "low") return "Low"
    return "Normal"
  }

  // Writes /home/hihry/Documents/Cyber/cyber.md with only Today's completed tasks
  // and the current date & time as the heading.
  function syncCyberMd() {
    if (!initialized) return
    var now = new Date()
    var dateHeading = Qt.formatDateTime(now, "dddd, d MMM yyyy — HH:mm:ss")

    var completedToday = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (t && t.day === "today" && t.done === true) {
        completedToday.push(t)
      }
    }

    completedToday.sort(function(a, b) {
      var ca = Number(a.completedAt) || Number(a.createdAt) || 0
      var cb = Number(b.completedAt) || Number(b.createdAt) || 0
      return ca - cb
    })

    var lines = []
    lines.push("# " + dateHeading)
    lines.push("")

    if (completedToday.length === 0) {
      lines.push("_No completed tasks for today._")
    } else {
      for (var j = 0; j < completedToday.length; j++) {
        var item = completedToday[j]
        var doneTime = Number(item.completedAt) > 0
          ? Qt.formatDateTime(new Date(Number(item.completedAt)), "HH:mm")
          : Qt.formatDateTime(now, "HH:mm")
        lines.push("- [x] " + item.text + " *(" + formatPriorityLabel(item.priority) + " · " + doneTime + ")*")
      }
    }

    lines.push("")
    cyberMdFile.setText(lines.join("\n"))
  }

  // Automatic midnight rollover:
  // - Completed tasks from past days (up to 60 days) are archived with day: "history"
  //   so past calendar dates retain their completion indicators
  // - Unfinished tasks in "today" stay pending in "today" (marked carriedOver: true)
  // - Tasks planned for the new today ("tomorrow" or scheduled for currentKey) become "today"
  // - Tasks scheduled for the new tomorrow become "tomorrow"
  function checkRollover() {
    var currentKey = todayDateKey()
    var tomorrowKey = tomorrowDateKey()
    var cutoffKey = cutoffHistoryDateKey(60)
    if (activeDate === "") {
      activeDate = currentKey
      saveState()
      return false
    }
    if (activeDate === currentKey) return false

    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      var itemDate = isValidDateKey(t.date)
        ? t.date
        : (t.day === "tomorrow" ? currentKey : activeDate)

      if (t.done) {
        if (itemDate >= cutoffKey) {
          var doneRole = dayRoleForDate(itemDate, true)
          nextList.push({
            id: t.id,
            text: t.text,
            day: doneRole,
            date: itemDate,
            priority: t.priority,
            color: sanitizeColor(t.color),
            done: true,
            createdAt: t.createdAt,
            completedAt: Number(t.completedAt) || Date.now(),
            carriedOver: false
          })
        }
        continue
      }

      if (itemDate < currentKey || t.day === "today") {
        // Unfinished past/Today task carries over into Today
        nextList.push({
          id: t.id,
          text: t.text,
          day: "today",
          date: currentKey,
          priority: t.priority,
          color: sanitizeColor(t.color),
          done: false,
          createdAt: t.createdAt,
          completedAt: 0,
          carriedOver: true
        })
      } else if (itemDate === currentKey || t.day === "tomorrow") {
        // Tomorrow's tasks or tasks scheduled for today roll into Today
        nextList.push({
          id: t.id,
          text: t.text,
          day: "today",
          date: currentKey,
          priority: t.priority,
          color: sanitizeColor(t.color),
          done: false,
          createdAt: t.createdAt,
          completedAt: 0,
          carriedOver: false
        })
      } else if (itemDate === tomorrowKey) {
        nextList.push({
          id: t.id,
          text: t.text,
          day: "tomorrow",
          date: tomorrowKey,
          priority: t.priority,
          color: sanitizeColor(t.color),
          done: false,
          createdAt: t.createdAt,
          completedAt: 0,
          carriedOver: false
        })
      } else {
        nextList.push({
          id: t.id,
          text: t.text,
          day: "scheduled",
          date: itemDate,
          priority: t.priority,
          color: sanitizeColor(t.color),
          done: false,
          createdAt: t.createdAt,
          completedAt: 0,
          carriedOver: false
        })
      }
    }

    activeDate = currentKey
    tasks = nextList
    saveState()
    return true
  }

  function addTask(text, day, priority, customColor) {
    var targetDate = day === "tomorrow" ? tomorrowDateKey() : todayDateKey()
    return addTaskForDate(text, targetDate, priority, customColor)
  }

  function addTaskForDate(text, dateKey, priority, customColor) {
    checkRollover()
    var cleanText = String(text || "").trim()
    if (cleanText === "") return false
    var todayKey = todayDateKey()
    var cleanDate = isValidDateKey(dateKey) ? dateKey.trim() : todayKey
    if (cleanDate < todayKey) cleanDate = todayKey
    var cleanDay = dayRoleForDate(cleanDate, false)
    var cleanPriority = validPriorities.indexOf(priority) >= 0 ? priority : "normal"
    var cleanColor = sanitizeColor(customColor)

    var newTask = {
      id: "t_" + Date.now() + "_" + (nextIdCounter++),
      text: cleanText,
      day: cleanDay,
      date: cleanDate,
      priority: cleanPriority,
      color: cleanColor,
      done: false,
      createdAt: Date.now(),
      completedAt: 0,
      carriedOver: false
    }

    var nextList = (root.tasks || []).slice()
    nextList.push(newTask)
    root.tasks = nextList
    saveState()
    return true
  }

  function toggleTask(taskId) {
    checkRollover()
    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      if (t.id === taskId) {
        var nextDone = !t.done
        var itemDate = isValidDateKey(t.date) ? t.date : todayDateKey()
        nextList.push({
          id: t.id,
          text: t.text,
          day: dayRoleForDate(itemDate, nextDone),
          date: itemDate,
          priority: t.priority,
          color: sanitizeColor(t.color),
          done: nextDone,
          createdAt: t.createdAt,
          completedAt: nextDone ? Date.now() : 0,
          carriedOver: t.carriedOver
        })
      } else {
        nextList.push(t)
      }
    }
    root.tasks = nextList
    saveState()
  }

  function deleteTask(taskId) {
    checkRollover()
    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (t && t.id !== taskId) nextList.push(t)
    }
    root.tasks = nextList
    saveState()
  }

  function cycleTaskPriority(taskId) {
    checkRollover()
    var order = ["normal", "high", "low"]
    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      if (t.id === taskId) {
        var idx = order.indexOf(t.priority)
        var nextPri = order[(idx + 1) % order.length]
        nextList.push({
          id: t.id,
          text: t.text,
          day: t.day,
          date: isValidDateKey(t.date) ? t.date : todayDateKey(),
          priority: nextPri,
          color: sanitizeColor(t.color),
          done: t.done,
          createdAt: t.createdAt,
          completedAt: Number(t.completedAt) || 0,
          carriedOver: t.carriedOver
        })
      } else {
        nextList.push(t)
      }
    }
    root.tasks = nextList
    saveState()
  }

  function setTaskColor(taskId, colorHex) {
    checkRollover()
    var cleanColor = sanitizeColor(colorHex)
    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      if (t.id === taskId) {
        nextList.push({
          id: t.id,
          text: t.text,
          day: t.day,
          date: isValidDateKey(t.date) ? t.date : todayDateKey(),
          priority: t.priority,
          color: cleanColor,
          done: t.done,
          createdAt: t.createdAt,
          completedAt: Number(t.completedAt) || 0,
          carriedOver: t.carriedOver
        })
      } else {
        nextList.push(t)
      }
    }
    root.tasks = nextList
    saveState()
  }

  function moveTaskDay(taskId, targetDay) {
    checkRollover()
    var cleanDay = targetDay === "tomorrow" ? "tomorrow" : "today"
    var targetDate = cleanDay === "tomorrow" ? tomorrowDateKey() : todayDateKey()
    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      if (t.id === taskId) {
        nextList.push({
          id: t.id,
          text: t.text,
          day: cleanDay,
          date: targetDate,
          priority: t.priority,
          color: sanitizeColor(t.color),
          done: t.done,
          createdAt: t.createdAt,
          completedAt: Number(t.completedAt) || 0,
          carriedOver: false
        })
      } else {
        nextList.push(t)
      }
    }
    root.tasks = nextList
    saveState()
  }

  function updateTaskText(taskId, newText) {
    checkRollover()
    var cleanText = String(newText || "").trim()
    if (cleanText === "") return false
    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      if (t.id === taskId) {
        nextList.push({
          id: t.id,
          text: cleanText,
          day: t.day,
          date: isValidDateKey(t.date) ? t.date : todayDateKey(),
          priority: t.priority,
          color: sanitizeColor(t.color),
          done: t.done,
          createdAt: t.createdAt,
          completedAt: Number(t.completedAt) || 0,
          carriedOver: t.carriedOver
        })
      } else {
        nextList.push(t)
      }
    }
    root.tasks = nextList
    saveState()
    return true
  }

  function clearCompleted(dayKey) {
    checkRollover()
    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      if (t.done && (!dayKey || t.day === dayKey)) continue
      nextList.push(t)
    }
    root.tasks = nextList
    saveState()
  }

  function postponeAllPendingToday() {
    checkRollover()
    var tomorrowKey = tomorrowDateKey()
    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      if (t.day === "today" && !t.done) {
        nextList.push({
          id: t.id,
          text: t.text,
          day: "tomorrow",
          date: tomorrowKey,
          priority: t.priority,
          color: sanitizeColor(t.color),
          done: false,
          createdAt: t.createdAt,
          completedAt: 0,
          carriedOver: false
        })
      } else {
        nextList.push(t)
      }
    }
    root.tasks = nextList
    saveState()
  }

  function moveAllTomorrowToToday() {
    checkRollover()
    var todayKey = todayDateKey()
    var nextList = []
    var list = root.tasks || []
    for (var i = 0; i < list.length; i++) {
      var t = list[i]
      if (!t) continue
      if (t.day === "tomorrow") {
        nextList.push({
          id: t.id,
          text: t.text,
          day: "today",
          date: todayKey,
          priority: t.priority,
          color: sanitizeColor(t.color),
          done: t.done,
          createdAt: t.createdAt,
          completedAt: Number(t.completedAt) || 0,
          carriedOver: false
        })
      } else {
        nextList.push(t)
      }
    }
    root.tasks = nextList
    saveState()
  }

  function saveState() {
    if (!initialized) return
    var nextText = JSON.stringify({
      version: 1,
      activeDate: activeDate || todayDateKey(),
      tasks: tasks
    }, null, 2) + "\n"
    lastSavedStateText = nextText
    stateFile.setText(nextText)
    syncCyberMd()
  }

  function applyExternalStateText(rawText) {
    if (!initialized) return
    var text = String(rawText || "")
    if (!text || text === lastSavedStateText) return
    try {
      var parsed = JSON.parse(text)
      if (!parsed || typeof parsed !== "object" || !Array.isArray(parsed.tasks)) return
      var nextTasks = []
      for (var i = 0; i < parsed.tasks.length; i++) {
        var clean = sanitizeTask(parsed.tasks[i])
        if (clean) nextTasks.push(clean)
      }
      lastSavedStateText = text
      if (typeof parsed.activeDate === "string" && parsed.activeDate !== "") {
        activeDate = parsed.activeDate
      }
      tasks = nextTasks
      syncCyberMd()
    } catch (e) {
    }
  }

  function initializeIfReady() {
    if (initialized || !stateFileLoaded) return

    var loadedTasks = []
    var loadedDate = ""
    if (loadedStateText !== "") {
      try {
        var parsed = JSON.parse(loadedStateText)
        if (parsed && typeof parsed === "object") {
          if (typeof parsed.activeDate === "string") {
            loadedDate = parsed.activeDate
          }
          if (Array.isArray(parsed.tasks)) {
            for (var i = 0; i < parsed.tasks.length; i++) {
              var clean = sanitizeTask(parsed.tasks[i])
              if (clean) loadedTasks.push(clean)
            }
          }
        }
      } catch (err) {
        console.warn("hihry.tasks: state file unreadable (" + err + "), starting fresh")
      }
    }

    activeDate = loadedDate
    tasks = loadedTasks
    initialized = true

    if (!checkRollover()) {
      saveState()
    }
  }

  // Periodic timer to detect midnight rollover automatically
  Timer {
    interval: 30 * 1000
    running: root.initialized
    repeat: true
    onTriggered: root.checkRollover()
  }

  Process {
    id: stateReader
    command: ["head", "-c", String(root.maxStateBytes), root.statePath]
    running: true
    stdout: StdioCollector { id: stateOut }
    onExited: function(exitCode) {
      if (exitCode === 0 && stateOut.text.length < root.maxStateBytes) {
        root.loadedStateText = stateOut.text
      } else {
        root.loadedStateText = ""
      }
      root.stateFileLoaded = true
      root.initializeIfReady()
    }
  }

  FileView {
    id: stateFile
    path: root.statePath
    preload: false
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyExternalStateText(text())
  }

  FileView {
    id: cyberMdFile
    path: root.cyberMdPath
    preload: false
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  IpcHandler {
    target: "hihry.tasks.service"

    function addToday(text: string): string {
      return root.addTask(text, "today", "normal", "") ? "ok" : "empty"
    }
    function addTomorrow(text: string): string {
      return root.addTask(text, "tomorrow", "normal", "") ? "ok" : "empty"
    }
    function addForDate(dateKey: string, text: string, priority: string, color: string): string {
      return root.addTaskForDate(text, dateKey, priority, color) ? "ok" : "empty"
    }
    function toggle(taskId: string): string {
      root.toggleTask(taskId)
      return "ok"
    }
    function remove(taskId: string): string {
      root.deleteTask(taskId)
      return "ok"
    }
    function cyclePriority(taskId: string): string {
      root.cycleTaskPriority(taskId)
      return "ok"
    }
    function setColor(taskId: string, color: string): string {
      root.setTaskColor(taskId, color)
      return "ok"
    }
    function clearDoneToday(): string {
      root.clearCompleted("today")
      return "ok"
    }
  }
}
