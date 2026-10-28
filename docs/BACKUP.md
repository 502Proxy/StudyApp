# Backup and restore

„Ablage → Backup erstellen …“ writes a `.studyappbackup` file; „Ablage → Backup wiederherstellen …“ replaces all data with its content. The same actions, the folder of automatic backups and the weekly schedule are in Settings → Backup.

## What is included

Modules (with semester, grade, ECTS and Stud.IP link), slide documents and their PDFs including annotations, notes, flashcards with their review schedule, study sheets, assignments, exams (manual ones and the study plan progress of detected ones), calendar sources and events, the Stud.IP file catalog and downloaded course files.

Not included: the Stud.IP password or session (keychain), app settings (`UserDefaults`) and reading positions. After restoring, sign in to Stud.IP again.

## File format (version 1)

A `.studyappbackup` file is an [Apple Archive](https://developer.apple.com/documentation/applearchive) compressed with LZFSE. It can be inspected with `aa extract -i Backup.studyappbackup -d out/`.

```text
manifest.json   formatVersion, appVersion, createdAt, moduleCount, fileCount
data.json       BackupSnapshot: modules, slideDocuments, notes, flashcards, studySheets,
                assignments, calendarSources, calendarEvents, courseFiles, exams
files/…         stored files with the same relative paths as in the app's storage
```

- JSON uses sorted keys; dates are seconds since 1 January 2001, Foundation's native representation (exact, unlike ISO 8601 or seconds since 1970); a semester is its raw value such as `"2025W"`.
- Entities are encoded with their `Codable` conformance. New optional properties keep older backups readable. Incompatible changes require increasing `BackupManifest.currentFormatVersion`; archives with a newer version are rejected with a clear message.

## Restore

1. The archive is extracted to a temporary folder and `manifest.json` / `data.json` are decoded – nothing has changed yet.
2. Archives from a newer format and file names that would leave the storage folder (`..`, absolute paths) are rejected.
3. StudyApp saves the current data as a safety backup („Vor Wiederherstellung“) in the backup folder.
4. All data is deleted and the snapshot is inserted; files are copied into the app's storage. Files the archive lacks are reported, not fatal.

## Automatic backups

With „Wöchentlich automatisch sichern“ enabled, StudyApp creates a backup on launch when the last one is at least seven days old and keeps the newest three (`AutomaticBackupPolicy`). They live in `~/Library/Containers/<bundle id>/Data/Library/Application Support/StudyApp/Backups`; „Ordner zeigen“ opens it in Finder. Copy a backup to an external drive or cloud folder to survive a broken Mac.

## Code

| Layer | Types |
| --- | --- |
| Domain | `BackupSnapshot`, `BackupManifest`, `AutomaticBackupPolicy` (`Domain/Entities/Backup.swift`); ports `BackupArchiving`, `BackupFolder`, parameter object `StudyDataRepositories`; use cases in `Domain/UseCases/BackupUseCases.swift` |
| Data | `AppleArchiveBackupArchiver`, `BackupJSONCoding`, `LocalBackupFolder` (`Data/Backup/`) |
| Presentation | `BackupViewModel`, `BackupCommands`, `BackupSettingsSection`, `BackupPanels` (`Presentation/Backup/`) |
