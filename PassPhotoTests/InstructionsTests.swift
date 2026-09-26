import Testing
@testable import PassPhoto

struct InstructionsTests {
    @Test func babyRulesChangeTheInstructions() throws {
        let spec = try #require(SpecCatalog.all.first { $0.infant?.mouthMayBeOpen == true })
        let adult = SpecInstructions.steps(for: spec, infant: false)
        let baby = SpecInstructions.steps(for: spec, infant: true)
        #expect(adult.first { $0.id == "expression" }?.text.contains("Don’t smile") == true)
        #expect(baby.first { $0.id == "expression" }?.text.contains("baby") == true)
        #expect(baby.first?.id == "baby")
        #expect(!adult.contains { $0.id == "baby" })
    }

    @Test func babyHeadRangeIsUsedWhenGiven() throws {
        let spec = try #require(SpecCatalog.all.first { $0.infant?.headHeightMM != nil })
        #expect(spec.forInfant().headHeightMM == spec.infant?.headHeightMM)
    }

    @Test func glassesInstructionFollowsTheRule() {
        #expect(SpecInstructions.glassesText(.notAllowed) == "Take off your glasses.")
        #expect(SpecInstructions.backgroundPhrase(.lightNotWhite).contains("not white"))
    }
}
