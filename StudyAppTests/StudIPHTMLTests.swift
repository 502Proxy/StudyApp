import Testing
@testable import StudyApp

struct StudIPHTMLTests {
    @Test func keepsParagraphsListsAndLineBreaks() {
        let text = StudIPHTML.plainText(
            "<p>Bitte mitbringen:</p><ul><li>Taschenrechner</li><li>Ausweis</li></ul>Zeile<br/>zwei&nbsp;&amp; Ende"
        )
        #expect(text == "Bitte mitbringen:\n\n• Taschenrechner\n• Ausweis\nZeile\nzwei & Ende")
    }
}
