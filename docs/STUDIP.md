# Stud.IP integration

StudyApp talks to the JSON:API of a Stud.IP installation (`<server>/jsonapi.php/v1/`). The default server is `https://elearning.uni-oldenburg.de`; any Stud.IP 5+ installation with the JSON:API enabled should work.

## Sign-in

| Method | When | How it works |
| --- | --- | --- |
| Browser (recommended) | Accounts with two-factor authentication, single sign-on | `StudIPWebLoginSheet` shows the regular Stud.IP login in a `WKWebView`. After every page load the cookies for the server are tried against `users/me`; once that succeeds, the cookie header is stored and the sheet closes. |
| Password | Accounts without 2FA | HTTP Basic authentication with the Stud.IP username (not necessarily the university account name). |

- Credentials live in the keychain (`KeychainStudIPAccountStore`); server and username in `UserDefaults`.
- The web view uses the persistent website data store, so „trust this device“ survives and the next login usually needs no code.
- A browser session eventually expires. The client reports `StudIPError.sessionExpired` (HTTP 401 or an HTML login page); background sync pauses silently and the settings show „Erneut anmelden …“.

## Endpoints

| Purpose | Request |
| --- | --- |
| Current user | `GET users/me` |
| Courses | `GET users/{id}/courses` |
| Semester titles | `GET semesters` |
| Files of a course (flat) | `GET courses/{id}/file-refs` |
| Folder tree | `GET courses/{id}/folders` (relationship `parent`) |
| Download | `GET file-refs/{id}/content` |

Lists are paged with `page[limit]=100` and followed through `links.next` (absolute or relative). Parsing is deliberately lenient (`StudIPJSONAPIParser`): missing attributes never fail a sync.

## Linking and sync

1. „+ → Stud.IP-Veranstaltungen zuordnen …“ lists the active modules; `StudIPCourseMatcher` suggests a course by title, course number and semester.
2. `SyncStudIPCoursesUseCase` runs on launch and every three hours (if enabled), or manually:
   - **PDFs** become slide sets. A changed PDF (new `chdate`) is imported as an additional set titled „… (aktualisiert)“, so annotations on the old one are kept.
   - **All files** are stored in the module's file catalog („Dateien“ section) with their folder path. Files up to 50 MB (`defaultAutoDownloadLimit`) that are not PDFs are downloaded automatically; larger ones on demand.
   - Files deleted in Stud.IP, a changed course link and a deleted module remove the local copies.
3. Archived modules are skipped.

Downloaded files are stored under `Slides/StudIP/<module id>/<file id>/<original name>` in the app container.

## Errors

| Error | Meaning | Effect |
| --- | --- | --- |
| `unauthorized` | Password rejected | Whole sync stops |
| `sessionExpired` | Browser session no longer valid | Whole sync stops, re-login needed |
| `offline` | No network | Whole sync stops, retried later |
| `notFound`, `server`, `invalidResponse` | A course or file failed | Reported, the remaining courses continue |
