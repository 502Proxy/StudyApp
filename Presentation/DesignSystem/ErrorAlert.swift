import SwiftUI

extension View {
    /// Zeigt `message` als Alert, solange sie nicht `nil` ist. `onDismiss` setzt sie zurück.
    func errorAlert(_ title: String = "Fehler", message: String?, onDismiss: @escaping () -> Void) -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { onDismiss() } }
            )
        ) {
            Button("OK", role: .cancel, action: onDismiss)
        } message: {
            Text(message ?? "")
        }
    }
}
