# Calendar

## Sources

| Source | How | Refresh |
| --- | --- | --- |
| `.ics` file | „Kalender → Quellen → .ics-Datei importieren …“ or drag and drop onto the calendar | Import the file again |
| Subscription | Paste an `https://`, `http://` or `webcal://` link | On launch, when the app becomes active and hourly while it runs (`StudyCalendarViewModel.refreshInterval`); failed attempts pause for 10 minutes |

For Stud.IP, the link is under „Planer → Stundenplan“ or „Termine“ → „Exportieren“/„Abonnieren“ (wording differs between installations).

Re-importing or refreshing replaces the events of that source. Events are matched by their **external ID** (`UID`, plus `#<occurrence>` for recurring events), so module links survive every refresh; events that left the feed are removed.

## Supported iCalendar features

Parser: `Data/Calendar/ICalendarParser.swift`

- Properties: `UID`, `DTSTART`, `DTEND`, `DURATION`, `SUMMARY`, `DESCRIPTION`, `LOCATION`, `STATUS` (`CANCELLED` events are skipped), `RECURRENCE-ID`, `EXDATE`, `RRULE`.
- Time formats: UTC, floating and `TZID` (IANA names and common Windows names such as „W. Europe Standard Time“); all-day dates with exclusive end.
- Recurrence: `FREQ` = `DAILY` / `WEEKLY` / `MONTHLY` / `YEARLY` with `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, `BYMONTHDAY`, `BYMONTH`. Series without an end are expanded about one year ahead.
- Every occurrence is a separate event with its own ID.
- Text: escaped characters, quoted parameters, folded lines.

Not supported: `BYSETPOS`, `BYWEEKNO`, `BYYEARDAY`, hourly/minutely rules, `VTODO`.

## Course detection

`CourseTitleAnalyzer` (`Domain/Entities/CourseTitle.swift`) extracts the course name, kind (lecture, exercise, tutorial, seminar …) and code from titles such as:

| Title | Course | Kind |
| --- | --- | --- |
| „Analysis I (Vorlesung)“ | Analysis I | lecture |
| „Übung zu Analysis I“ | Analysis I | exercise |
| „Tutorium: Lineare Algebra II“ | Lineare Algebra II | tutorial |
| „inf030 Programmierung, Tutorium“ | Programmierung (code inf030) | tutorial |

`DetectModuleCandidatesUseCase` groups events by the normalised course key. A group becomes a module when it is likely a course (keyword or weekly series) and has an event in the current semester window. `SyncModulesWithCalendarUseCase` applies this after every import and refresh unless „Module automatisch aus dem Kalender anlegen“ is off. Modules the user deleted are stored in `ignoredCourseKeys` and never recreated.
