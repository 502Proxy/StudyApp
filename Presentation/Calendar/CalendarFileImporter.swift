import SwiftUI
import UniformTypeIdentifiers

private struct CalendarFileImporter: ViewModifier {
    @Binding var isPresented: Bool
    let viewModel: StudyCalendarViewModel

    private static let contentTypes: [UTType] = [UTType(filenameExtension: "ics"), UTType.calendarEvent].compactMap { $0 }

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: Self.contentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): viewModel.importFiles(urls)
            case .failure(let error): viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

extension View {
    /// Dateiauswahl für .ics-Dateien. Wird von Kalenderansicht und Quellenverwaltung gemeinsam genutzt.
    func calendarFileImporter(isPresented: Binding<Bool>, viewModel: StudyCalendarViewModel) -> some View {
        modifier(CalendarFileImporter(isPresented: isPresented, viewModel: viewModel))
    }
}
