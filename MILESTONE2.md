# StudyApp – Milestone 2: PDF-Import und Viewer

## 1. Dateien einspielen

**Ersetzen** (gleicher Pfad, alte Datei überschreiben):
- `App/AppContainer.swift`
- `App/StudyAppApp.swift`
- `Data/SwiftData/Persistence.swift`
- `Domain/UseCases/ModuleUseCases.swift`
- `Presentation/RootView.swift`
- `Presentation/Modules/ModuleDetailView.swift`
- `Presentation/Modules/ModulesViewModel.swift`
- `StudyAppTests/ModuleUseCaseTests.swift`

**Neu** (in Xcode in die passende Gruppe ziehen, "Create groups"):
- `Domain/Entities/SlideDocument.swift`
- `Domain/Repositories/SlideDocumentRepository.swift`
- `Domain/Repositories/FileStorage.swift`
- `Domain/UseCases/SlideUseCases.swift`
- `Data/SwiftData/SlideDocumentRecord.swift`
- `Data/Repositories/SwiftDataSlideDocumentRepository.swift`
- `Data/Files/LocalFileStorage.swift`
- `Data/PDF/PDFKitInspector.swift`
- `Presentation/Slides/` (5 Dateien)
- `StudyAppTests/SlideUseCaseTests.swift`, `StudyAppTests/SlideDataTests.swift`
  (Target Membership: nur `StudyAppTests`)

Die Ersetzungen am besten direkt im Finder in den Projektordner kopieren, dann in Xcode
nur die neuen Dateien hinzufügen. Alle neuen Quelldateien außer den Tests gehören zum Target `StudyApp`.

## 2. Sandbox prüfen
Target `StudyApp` → Signing & Capabilities → App Sandbox → File Access:
**User Selected File** muss auf **Read Only** (oder Read/Write) stehen, sonst kann der Importdialog
keine PDFs lesen. Bei neuen Xcode-Projekten ist das meist schon gesetzt.

## 3. Datenbank
Das SwiftData-Schema bekommt ein neues Modell. Das ist eine automatische, einfache Migration.
Die Module aus Milestone 1 bleiben erhalten.

## 4. Ausprobieren
- Modul wählen → Tab **Folien** → "PDF importieren" (oder PDFs ins Fenster ziehen)
- Eintrag anklicken öffnet den Viewer
- Text auswählen → Marker-Symbol oder ⇧⌘H markiert, Radierer entfernt Markierungen in der Auswahl
- Markierungen stehen als echte Annotationen in der Kopie im App-Ordner
- Rechtsklick auf einen Eintrag: Umbenennen, Löschen
- Modul löschen entfernt auch seine PDFs

## Bekannte Grenzen
- Import kopiert auf dem Main Thread. Sehr große PDFs (mehrere hundert MB) blockieren kurz die Oberfläche.
- Passwortgeschützte PDFs werden als unlesbar abgelehnt.
- Die zuletzt gelesene Seite wird noch nicht gemerkt.
