# Exam phase

StudyApp shows upcoming exams with a countdown and a study plan that spreads the module's material over the days until the exam.

## Where

- **Heute → Klausuren:** every upcoming exam with countdown and progress; a click opens the module's exam section.
- **Module → Klausur** (⌘8): countdown, room, study plan with check boxes, „Termin eintragen …“ for exams that are not in the calendar.
- **Module overview:** a „Klausur“ tile with the countdown.

## Detection

`ExamDetector` (`Domain/UseCases/ExamUseCases.swift`) runs a chain of `ExamDetectionRule`s; the first rule with an answer wins:

1. `ExcludedExamTopicsRule` – „Klausurvorbereitung“, „Klausureinsicht“, „Probeklausur“, „Fragestunde“ … are not exams.
2. `CourseKindExamRule` – `CourseTitleAnalyzer` recognises the exam kind („Klausur“, „Nachklausur“, „Prüfung“, „Exam“, „Testat“ …).

An exam belongs to the module its event is linked to, or to the module whose name appears in the title. Detected exams are derived from the calendar on every load and get a stable ID from the event's external ID (`UUID.stable(from:)`), so date and room follow the calendar automatically. Only state the user creates is stored (`ExamRecord`): exams entered by hand, hidden detected exams and ticked study plan items. Exams of archived modules and past exams are not shown.

## Study plan

`StudyPlanGenerator` is a pure function of the exam, the module's slide sets, whether the module has flashcards and today's date:

- The learning days run from today to the day before the exam (only today if the exam is today).
- Every slide set that is not ticked off is one item; open items are spread evenly over the days. Because the plan is recalculated every day, missed items move forward automatically.
- Each day has a flashcard review (if the module has cards).
- With at least two learning days, the last one is reserved for a final review.

Item IDs (`slides.<document>`, `cards.<date>`, `review.final`) are stored in `Exam.completedPlanItems`; progress is ticked items / all items.
