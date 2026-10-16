# Milestone 5 — Calendar

## Features
- Import local iCalendar `.ics` files through the macOS file importer.
- Subscribe to an HTTP(S) `.ics` feed and refresh it on demand.
- Persist calendar sources and imported events in SwiftData.
- View a month grid and a chronological agenda.
- Link events to existing study modules and open a linked module from the event detail sheet.
- Remove a source and its imported events together.

## Architecture
- `Domain/Entities/CalendarEvent.swift`: domain types for events and sources.
- `Domain/Repositories/StudyCalendarRepository.swift`: repository contract.
- `Domain/UseCases/StudyCalendarUseCases.swift`: listing, import, and module-link use cases.
- `Data/Calendar/ICalendarParser.swift`: isolated ICS parsing adapter.
- `Data/SwiftData/StudyCalendarRecords.swift` and `Data/Repositories/SwiftDataStudyCalendarRepository.swift`: persistence.
- `Presentation/Calendar/StudyCalendarViewModel.swift`: orchestration and user-facing state.
- `Presentation/Calendar/StudyCalendarView.swift`: calendar, source management, and event details.

## Current limitations
- RRULE recurrence expansion is not implemented; recurring events are not expanded into occurrences.
- Subscription feeds refresh manually; there is no background polling.
- Subscribed feeds must be reachable by HTTP(S) and provide iCalendar data.
- As in the rest of this source archive, a complete Xcode project file is not included, so an end-to-end macOS build must be run after adding files to the app and test targets.
