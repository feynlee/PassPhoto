import CoreGraphics
import Foundation
import Testing
@testable import PassPhoto

struct CropSolverTests {
    /// A 3000 × 4000 portrait with the head in the upper middle.
    let image = CGSize(width: 3000, height: 4000)
    let face = FaceMeasurement(
        crownY: 900, skullTopY: 940, chinY: 2100, eyeY: 1520, centerX: 1500, faceWidth: 850,
        rollDegrees: 0, yawDegrees: 0, faceCount: 1, crownIsEstimated: false, source: .vision
    )

    @Test(arguments: SpecCatalog.all)
    func autoCropMeetsEveryMeasuredRequirement(spec: PhotoSpec) {
        let crop = CropSolver.autoCrop(measurement: face, spec: spec, imageSize: image)
        let geometry = CropSolver.geometry(of: crop, measurement: face, spec: spec, imageSize: image)

        #expect(abs(crop.width / crop.height - spec.aspect) < 0.001)
        #expect(spec.headHeightMM.contains(geometry.headMM))
        if let eye = spec.eyeLineFromBottomMM { #expect(eye.contains(geometry.eyeFromBottomMM)) }
        if let margin = spec.topMarginMM { #expect(margin.contains(geometry.topMarginMM)) }
        #expect(abs(geometry.centerOffsetMM) <= CropSolver.centerToleranceMM)
        #expect(geometry.outsideFraction == 0)

        let failing = Checks.geometry(geometry, measurement: face, spec: spec).filter { $0.status != .pass }
        #expect(failing.isEmpty, "\(failing.map(\.title))")
    }

    @Test func prefersTheMiddleOfTheHeadRange() {
        let spec = SpecCatalog.spec(id: "gb-passport")!
        let crop = CropSolver.autoCrop(measurement: face, spec: spec, imageSize: image)
        let geometry = CropSolver.geometry(of: crop, measurement: face, spec: spec, imageSize: image)
        #expect(abs(geometry.headMM - spec.headHeightMM.mid) < 0.01)
    }

    @Test func shiftsWithinTheAllowedRangeToStayInsideThePhoto() {
        // The face is near the left edge: centred exactly, the frame would run past the photo.
        var nearEdge = face
        nearEdge.centerX = 700
        let spec = SpecCatalog.spec(id: "eu-schengen-visa")!
        let crop = CropSolver.autoCrop(measurement: nearEdge, spec: spec, imageSize: image)
        let geometry = CropSolver.geometry(of: crop, measurement: nearEdge, spec: spec, imageSize: image)
        #expect(crop.minX >= 0)
        #expect(spec.headHeightMM.contains(geometry.headMM))
        #expect(abs(geometry.centerOffsetMM) <= CropSolver.centerToleranceMM)
    }

    @Test func flagsAFrameThatRunsPastThePhoto() {
        // A tight selfie: the head nearly fills the photo.
        let tight = FaceMeasurement(
            crownY: 40, skullTopY: 100, chinY: 3800, eyeY: 1900, centerX: 1500, faceWidth: 2600,
            rollDegrees: 0, yawDegrees: 0, faceCount: 1, crownIsEstimated: false, source: .vision
        )
        let spec = SpecCatalog.spec(id: "us-passport")!
        let crop = CropSolver.autoCrop(measurement: tight, spec: spec, imageSize: image)
        let geometry = CropSolver.geometry(of: crop, measurement: tight, spec: spec, imageSize: image)
        #expect(geometry.outsideFraction > 0)
        #expect(Checks.geometry(geometry, measurement: tight, spec: spec).contains { $0.id == "edges" && $0.status == .fail })
    }

    @Test func backgroundRulesFollowTheSpec() {
        #expect(Checks.backgroundStatus(.white, rule: .lightNotWhite) == .fail)
        #expect(Checks.backgroundStatus(.lightBlue, rule: .lightNotWhite) == .pass)
        #expect(Checks.backgroundStatus(.offWhite, rule: .whiteOrOffWhite) == .pass)
        #expect(Checks.backgroundStatus(.lightGrey, rule: .white) == .fail)
    }

    @Test func exportNamesAreClear() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 14, minute: 32))!
        let name = PhotoStore.exportFileName(name: "United States Passport · Sep 25, 2026", date: date)
        #expect(name == "United States Passport 2026-09-25 14.32.jpg")
    }
}
