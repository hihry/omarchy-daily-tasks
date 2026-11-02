# Daily Tasks (`hihry.tasks`)

An [Omarchy](https://omarchy.org/) status bar plugin for managing **Today's pending tasks**, planning **Tomorrow's tasks**, and scheduling tasks on **any calendar date** with priority levels and custom colors.

Works standalone or as a companion to [**`hihry.clock` (Omarchy Calendar & Tasks Clock)**](https://github.com/hihry/omarchy-calendar-clock), sharing `~/.local/state/omarchy/daily-tasks.json` in real time.

## Installation

```bash
omarchy plugin add https://github.com/hihry/omarchy-daily-tasks.git --enable
```

## Features

- **Status Bar Indicator**: Displays `󰅇 <count>` for pending Today tasks (`󰄬 0` when all tasks are completed). Highlights when a high-priority task is pending.
- **Today & Tomorrow Tabs**:
  - **Today**: View and check off pending tasks for today.
  - **Tomorrow**: Note down tasks for the next day ahead of time.
- **Calendar Date Scheduling & Custom Colors**:
  - Supports scheduling tasks for any `YYYY-MM-DD` date and assigning custom hex colors (`#RRGGBB`), rendered directly on the calendar grid when paired with `hihry.clock`.
- **Automatic Midnight Rollover**:
  - At midnight, tasks planned in **Tomorrow** (or scheduled for the new day) automatically move into **Today**.
  - Unfinished **Today** tasks stay pending in **Today** (tagged as carried over).
  - Completed tasks are archived by date for 60 days so past calendar dates retain completion indicators.
- **Priority Levels**: Assign `! High`, `• Normal`, or `↓ Low` priority when creating a task, or click any task's priority badge to cycle its priority.
- **Postpone / Pull Forward**:
  - Click `󰁔` on any Today task to postpone it to Tomorrow (or use **Postpone all →**).
  - Click `󰁍` on any Tomorrow task to move it into Today (or use **← Move all to Today**).
- **Inline Editing**: Double-click any task's text (or click `󰏫`) to edit it inline.

## Bar Interactions

- **Left-click**: Toggle the Daily Tasks popup panel
- **Right-click**: Open directly to the **Tomorrow** tab to plan next-day tasks
- **Middle-click**: Open directly to the **Today** tab

## IPC Commands

```bash
omarchy-shell hihry.tasks.service addToday "Ship feature"
omarchy-shell hihry.tasks.service addTomorrow "Review PRs"
omarchy-shell hihry.tasks.service addForDate "2026-11-10" "Release v1.2" "high" "#e06c75"
```

## License

MIT
