# Milestone 5 — Calendar & Navigation

## Features
- Import local iCalendar `.ics` files (file dialog or drag and drop onto the calendar).
- Subscribe to an HTTP(S) or `webcal://` feed; refresh one or all subscriptions on demand.
- Refreshing reconciles with the feed: new events are added, changed ones updated, removed ones deleted. Module links survive.
- Month grid with event chips, keyboard navigation (arrow keys, Page Up/Down, Return) and a day inspector.
- Agenda view (chronological, grouped by day) and search across title, location, notes and module name.
- All-day and multi-day events are shown on every day they span.
- Link events to modules and jump straight into a module section from the event detail sheet.
- Upcoming linked events appear on the module overview; the sidebar badge shows today's events.

## Navigation
- `AppNavigation` is the single source of truth: current destination, last section per module, back/forward history, persisted across launches.
- Sidebar, shortcuts, quick navigator and calendar deep links all go through the same methods.
- Shortcuts: `⌘K` quick navigator, `⇧⌘C` calendar, `⌘1`–`⌘5` module sections, `⌘[` / `⌘]` back/forward, `⇧⌘T` today, `⇧⌘N` new module.

## Architecture
- `Domain/Entities/CalendarEvent.swift`: events, sources, time logic (`occupiedDays`, `upcoming`).
- `Domain/Repositories/StudyCalendarRepository.swift`, `CalendarFeed.swift`: repository and ports (feed loading, parsing).
- `Domain/UseCases/StudyCalendarUseCases.swift`: import file, sync subscription, link, remove source, feed URL normalization.
- `Data/Calendar/`: `ICalendarParser` (+ port adapter) and `URLSessionCalendarFeedLoader`.
- `Data/SwiftData/StudyCalendarRecords.swift`, `Data/Repositories/SwiftDataStudyCalendarRepository.swift`: persistence.
- `Presentation/Calendar/`: view model, month grid math, month/agenda/search views, day inspector, event detail and sources sheets.
- `Presentation/Navigation/`: destinations, `AppNavigation`, quick navigator, menu commands.

## Parser behaviour
- Cancelled events (`STATUS:CANCELLED`) are skipped; nested components such as `VALARM` are ignored.
- Events without `UID` get a stable ID derived from start and title.

## Current limitations
- RRULE recurrence expansion is not implemented; recurring events show only their first occurrence.
- Subscription feeds refresh manually; there is no background polling.
- Windows time zone names (e.g. "W. Europe Standard Time") fall back to the system time zone.
