import Testing
@testable import PassPhoto

struct CelebrationTests {
    @Test func seededRandomIsRepeatableAndInRange() {
        var a = SeededRandom(42), b = SeededRandom(42)
        for _ in 0..<100 {
            let x = a.next()
            #expect(x == b.next())
            #expect((0..<1).contains(x))
        }
    }

    @Test func everyStyleEndsAndOffDoesNothing() {
        for style in CelebrationStyle.allCases where style != .off {
            #expect(style.duration(reduceMotion: false) > 2)
            #expect(style.duration(reduceMotion: true) < style.duration(reduceMotion: false))
        }
        let jar = TipJar()
        jar.celebrate(.off)
        #expect(jar.celebration == nil)
        jar.celebrate(.planes)
        #expect(jar.celebration?.style == .planes)
    }
}
