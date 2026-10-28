import Foundation
import Testing
@testable import StudyApp

@MainActor
struct StudierendenwerkMenuParserTests {
    /// Excerpt of the real answer for Mensa Wechloy: meals before the first heading, then „SUPPEN“.
    static let wechloy = #"""
        <div class='container-fluid'><div class='row gruppenkopf visible-sm-block visible-md-block visible-lg-block'>
        								<div class='col-xs-4 gruppenname'></div>
        								<div class='col-xs-8 preise-head'>PREIS STUDIERENDE | BEDIENSTETE | GÄSTE</div>
        							</div>
        							<div class='row gruppenkopf visible-xs-block'>
        								<div class='col-xs-12 gruppenname'></div>
        							</div><div class='row splMeal' lang='Mi,We,V'>

        								<div class='col-xs-12 visible-xs-block'>
        									<span style='font-size:1.5em'>Zwiebelquiche<div class='kennz'>(Mi, We)</div></span>
        									<div style='height:10px'>&nbsp;</div>
        								</div>

        								<div class='col-xs-12 col-md-4 col-sm-4 contains-foto'>
        									<img src='assets/fotos/mensa-uhlhornsweg/Vegetarisch/434s2n114_zwiebelquiche_t6.jpg?v=2' class='smallFoto img-responsive ptr'>
        								<img src='assets/fotos/mensa-uhlhornsweg/Vegetarisch/434s2n114_zwiebelquiche_t6.jpg?v=2' class='largeFoto hidden hidden-xs'>
        								</div>
        								<div class='col-md-5 col-sm-5 visible-sm-block visible-md-block visible-lg-block'>
        									<span style='font-size:24px'>Zwiebelquiche<div class='kennz'>(Mi, We)</div></span></div>
        								<div class='col-md-3 col-sm-3 visible-sm-block visible-md-block visible-lg-block' style='text-align:right'>
        									<div class='preise'><span>3,30&nbsp;/&nbsp;5,20&nbsp;/&nbsp;5,40&nbsp;&euro;</span><br></div>
        									<div style='margin-top:25px'><img src='assets/icons/V.png' class='iconLarge' title='vegetarisch' alt='icon'></div>
        								</div>

        								<div class='col-xs-5 visible-xs-block' style='height:30px;padding:0 0 10px 0'>
        									<div style='padding:0 0 20px 10px'><br><img src='assets/icons/V.png' class='icon' title='vegetarisch' alt='icon'></div>
        								</div>
        								<div class='col-xs-7 visible-xs-block' style='height:30px;text-align: right'>
        									<div class='preise-head' style='font-size:0.7em;padding:5px 0 2px 0'>PREIS STUDIERENDE | BEDIENSTETE | GÄSTE</div>
        									<div style='font-size:1.3em'>3,30&nbsp;/&nbsp;5,20&nbsp;/&nbsp;5,40&nbsp;&euro;<br></div>
        								</div>

        								<div class='col-xs-12 visible-xs-block'>
        									<div style='height:20px'>&nbsp;</div></div>
        					</div><div class='row gruppenkopf visible-sm-block visible-md-block visible-lg-block'>
        								<div class='col-xs-4 gruppenname'>SUPPEN</div>
        								<div class='col-xs-8 preise-head'>PREIS STUDIERENDE | BEDIENSTETE | GÄSTE</div>
        							</div>
        							<div class='row gruppenkopf visible-xs-block'>
        								<div class='col-xs-12 gruppenname'>SUPPEN</div>
        							</div><div class='row splMeal' lang='2,Kn,Sl,V+'>

        								<div class='col-xs-12 visible-xs-block'>
        									<span style='font-size:1.5em'>Mexikanische Maiscremesuppe<div class='kennz'>(2, Kn, Sl)</div></span>
        									<div style='height:10px'>&nbsp;</div>
        								</div>

        								<div class='col-xs-12 col-md-4 col-sm-4 contains-foto'>
        									<img src='assets/fotos/mensa-uhlhornsweg/Suppe/cm491m38e_mexikanische-maiscremecuppe_s1.jpg?v=2' class='smallFoto img-responsive ptr'>
        								<img src='assets/fotos/mensa-uhlhornsweg/Suppe/cm491m38e_mexikanische-maiscremecuppe_s1.jpg?v=2' class='largeFoto hidden hidden-xs'>
        								</div>
        								<div class='col-md-5 col-sm-5 visible-sm-block visible-md-block visible-lg-block'>
        									<span style='font-size:24px'>Mexikanische Maiscremesuppe<div class='kennz'>(2, Kn, Sl)</div></span></div>
        								<div class='col-md-3 col-sm-3 visible-sm-block visible-md-block visible-lg-block' style='text-align:right'>
        									<div class='preise'><span>0,60&nbsp;/&nbsp;1,25&nbsp;/&nbsp;1,35&nbsp;&euro;</span><br></div>
        									<div style='margin-top:25px'><img src='assets/icons/V+.png' class='iconLarge' title='vegan' alt='icon'></div>
        								</div>

        								<div class='col-xs-5 visible-xs-block' style='height:30px;padding:0 0 10px 0'>
        									<div style='padding:0 0 20px 10px'><br><img src='assets/icons/V+.png' class='icon' title='vegan' alt='icon'></div>
        								</div>
        								<div class='col-xs-7 visible-xs-block' style='height:30px;text-align: right'>
        									<div class='preise-head' style='font-size:0.7em;padding:5px 0 2px 0'>PREIS STUDIERENDE | BEDIENSTETE | GÄSTE</div>
        									<div style='font-size:1.3em'>0,60&nbsp;/&nbsp;1,25&nbsp;/&nbsp;1,35&nbsp;&euro;<br></div>
        								</div>

        								<div class='col-xs-12 visible-xs-block'>
        									<div style='height:20px'>&nbsp;</div></div>
        					</div></div>
        """#

    @Test func readsMealsWithCategoryPriceAndNotes() {
        let meals = StudierendenwerkMenuParser.meals(Self.wechloy)

        #expect(meals.map(\.name) == ["Zwiebelquiche", "Mexikanische Maiscremesuppe"])
        #expect(meals.map(\.category) == ["Gerichte", "Suppen"])
        #expect(meals.map(\.studentPrice) == [3.3, 0.6])
        #expect(meals.map(\.id) == [0, 1])
        #expect(!StudierendenwerkMenuParser.isClosed(Self.wechloy))
    }

    @Test func readsCounterHeadingsMaximumPricesAndSeveralIcons() {
        let html = """
            <div class='row gruppenkopf visible-sm-block'><div class='col-xs-4 gruppenname'>AUSGABE DREI</div></div>
            <div class='row splMeal' lang='Kn,We,R'>
            <div class='col-md-5 col-sm-5 visible-sm-block'>
            <span style='font-size:24px'>Chili con Carne, Fladenbrot<div class='kennz'>(Kn, We)</div></span></div>
            <div class='col-md-3 col-sm-3'><div class='preise'><span>max. 2,50*&nbsp;/&nbsp;5,00&nbsp;/&nbsp;5,20&nbsp;&euro;</span><br></div>
            <div><img src='assets/icons/R.png' class='iconLarge' title='mit Rindfleisch' alt='icon'>\
            <img src='assets/icons/AT.png' class='iconLarge' title='mit Rindfleisch' alt='icon'></div>
            <img src='assets/icons/R.png' class='icon' title='mit Rindfleisch' alt='icon'></div>
            </div>
            """

        let meal = StudierendenwerkMenuParser.meals(html).first

        #expect(meal?.name == "Chili con Carne, Fladenbrot")
        #expect(meal?.category == "Ausgabe Drei")
        #expect(meal?.studentPrice == 2.5)
        #expect(meal?.notes == ["mit Rindfleisch"])
    }

    @Test func recognisesClosedDays() {
        let html = """
            <div class='container-fluid'><div class='row nodata'>
            <div class='col-xs-12'>Die Mensa hat an diesem Tag geschlossen.</div></div></div>
            """

        #expect(StudierendenwerkMenuParser.isClosed(html))
        #expect(StudierendenwerkMenuParser.meals(html).isEmpty)
    }
}
