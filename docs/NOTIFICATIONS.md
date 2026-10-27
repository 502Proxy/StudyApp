# Notifications

Settings → Mitteilungen turns on three kinds of local notifications. All are off by default; macOS asks for permission when the first one is turned on.

| Kind | When | Click opens |
| --- | --- | --- |
| Lecture | A configurable number of minutes (0–60, default 10) before a lecture linked to an active module | The module's slides, where you stopped reading |
| Assignment | The day before and three hours before an open assignment is due | The module's assignments |
| New Stud.IP files | After an automatic sync brought new slides or files | Today |

## How planning works

`NotificationPlanner` (`Domain/UseCases/NotificationUseCases.swift`) is a pure function from events, assignments, modules and settings to the wanted notifications. Each kind is a `NotificationRule` (strategy pattern); a new kind is a new rule, the planner does not change.

`SyncNotificationsUseCase` runs on launch, every five minutes and when a setting changes. It schedules every planned notification under a stable identifier (re-scheduling replaces the old request, e.g. after a room change) and cancels StudyApp requests that are no longer planned (a cancelled lecture, a completed assignment). Requests of other components are never touched: StudyApp's identifiers start with `studyapp.`.

- Lectures are planned seven days ahead; at most 60 requests are pending (macOS allows 64 per app).
- Archived modules, all-day events and events without a module are not reminded.
- `UserNotificationScheduler` (`Data/Notifications/`) adapts the port to `UNUserNotificationCenter`; `NotificationResponder` (`App/`) turns a click into navigation and shows banners while the app is in front.
