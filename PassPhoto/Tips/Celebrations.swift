import SwiftUI

/// The thank-you celebrations tippers can choose from. Each plays when they save a photo.
enum CelebrationStyle: String, CaseIterable, Identifiable {
    case balloons, stamp, planes, off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .balloons: "Heart Balloons"
        case .stamp: "Approved Stamp"
        case .planes: "Paper Planes"
        case .off: "Off"
        }
    }

    var symbol: String {
        switch self {
        case .balloons: "heart.circle.fill"
        case .stamp: "checkmark.seal.fill"
        case .planes: "paperplane.fill"
        case .off: "circle.slash"
        }
    }

    /// Seconds from start to fully faded.
    func duration(reduceMotion: Bool) -> TimeInterval {
        if reduceMotion { return 2.4 }
        switch self {
        case .balloons: return 5.2
        case .stamp: return 3.4
        case .planes: return 4.2
        case .off: return 0
        }
    }
}

/// One run of a celebration.
struct Celebration: Identifiable, Equatable {
    let id = UUID()
    let style: CelebrationStyle
}

/// Plays a celebration over everything. It never takes touches and removes itself when done.
struct CelebrationView: View {
    let celebration: Celebration
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()
    @State private var seed = UInt64.random(in: 1...UInt64.max)

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            CelebrationFrame(style: celebration.style, time: elapsed, seed: seed, reduceMotion: reduceMotion)
                .onChange(of: elapsed >= celebration.style.duration(reduceMotion: reduceMotion)) { _, done in
                    if done { onFinished() }
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .sensoryFeedback(.success, trigger: celebration.id)
    }
}

/// One frame of a celebration, a pure function of time, so it can be rendered and checked at any moment.
struct CelebrationFrame: View {
    let style: CelebrationStyle
    let time: TimeInterval
    let seed: UInt64
    var reduceMotion = false

    var body: some View {
        Canvas { context, size in
            if reduceMotion {
                calmHeart(&context, size)
                return
            }
            switch style {
            case .balloons: balloons(&context, size)
            case .stamp: stamp(&context, size)
            case .planes: planes(&context, size)
            case .off: break
            }
        }
    }

    // MARK: Shared

    static let pink = Color(red: 1, green: 0.36, blue: 0.48)
    static let coral = Color(red: 1, green: 0.55, blue: 0.42)
    static let gold = Color(red: 1, green: 0.82, blue: 0.40)
    static let sky = Color(red: 0.66, green: 0.74, blue: 0.94)
    static let navy = Color(red: 0.12, green: 0.18, blue: 0.35)
    static let stampInk = Color(red: 0.16, green: 0.25, blue: 0.53)

    /// Everything fades together over the last part of the run.
    private func fade(_ duration: TimeInterval, over length: TimeInterval) -> Double {
        min(1, max(0, (duration - time) / length))
    }

    /// A heart centred on `center`, `size` wide.
    static func heart(center: CGPoint, size: CGFloat) -> Path {
        let s = size / 2
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y + s * 0.9))
        path.addCurve(to: CGPoint(x: center.x - s, y: center.y - s * 0.2),
                      control1: CGPoint(x: center.x - s * 0.35, y: center.y + s * 0.55),
                      control2: CGPoint(x: center.x - s, y: center.y + s * 0.25))
        path.addArc(center: CGPoint(x: center.x - s * 0.5, y: center.y - s * 0.3), radius: s * 0.52,
                    startAngle: .degrees(170), endAngle: .degrees(-20), clockwise: false)
        path.addArc(center: CGPoint(x: center.x + s * 0.5, y: center.y - s * 0.3), radius: s * 0.52,
                    startAngle: .degrees(200), endAngle: .degrees(10), clockwise: false)
        path.addCurve(to: CGPoint(x: center.x, y: center.y + s * 0.9),
                      control1: CGPoint(x: center.x + s, y: center.y + s * 0.25),
                      control2: CGPoint(x: center.x + s * 0.35, y: center.y + s * 0.55))
        path.closeSubpath()
        return path
    }

    private func calmHeart(_ context: inout GraphicsContext, _ size: CGSize) {
        let appear = min(1, time / 0.5), opacity = appear * fade(2.4, over: 0.8)
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
        context.opacity = opacity
        context.fill(Self.heart(center: center, size: 90), with: .color(Self.pink))
    }

    // MARK: Heart balloons

    /// Heart-shaped balloons on strings float up from below, swaying; a few pop into tiny hearts near the top.
    private func balloons(_ context: inout GraphicsContext, _ size: CGSize) {
        var rng = SeededRandom(seed)
        let palette = [Self.pink, Self.coral, Self.gold, Self.sky, Self.pink, Self.navy]
        let count = 16
        context.opacity = fade(5.2, over: 0.9)
        for i in 0..<count {
            let delay = rng.next() * 1.4
            let speed = size.height * (0.26 + rng.next() * 0.16)
            let width = 36 + rng.next() * 26
            let startX = size.width * (0.06 + 0.88 * (Double(i) + rng.next()) / Double(count))
            let swayAmount = 10 + rng.next() * 18, swaySpeed = 1.2 + rng.next() * 1.4, phase = rng.next() * .pi * 2
            let pops = rng.next() < 0.35
            let popAt = size.height * (0.12 + rng.next() * 0.2)
            let color = palette[i % palette.count]

            let t = time - delay
            guard t > 0 else { continue }
            let y = size.height + width - speed * t
            let x = startX + sin(t * swaySpeed + phase) * swayAmount
            let tilt = cos(t * swaySpeed + phase) * 0.12

            if pops, y < popAt {
                // A little burst of hearts where it popped, fading over half a second.
                let popTime = (size.height + width - popAt) / speed
                let since = t - popTime
                guard since < 0.6 else { continue }
                let popX = startX + sin(popTime * swaySpeed + phase) * swayAmount
                for k in 0..<6 {
                    let angle = Double(k) / 6 * .pi * 2 + phase
                    let distance = 12 + since * 90
                    let point = CGPoint(x: popX + cos(angle) * distance, y: popAt + sin(angle) * distance)
                    var piece = context
                    piece.opacity *= 1 - since / 0.6
                    piece.fill(Self.heart(center: point, size: 10), with: .color(color))
                }
                continue
            }

            // String: a gentle curve hanging below the balloon.
            var string = Path()
            let knot = CGPoint(x: x, y: y + width * 0.48)
            string.move(to: knot)
            string.addCurve(to: CGPoint(x: x - tilt * 60, y: knot.y + width * 1.3),
                            control1: CGPoint(x: x + 8, y: knot.y + width * 0.4),
                            control2: CGPoint(x: x - 8, y: knot.y + width * 0.9))
            context.stroke(string, with: .color(.gray.opacity(0.55)), lineWidth: 1)

            var balloon = context
            balloon.translateBy(x: x, y: y)
            balloon.rotate(by: .radians(tilt))
            let shape = Self.heart(center: .zero, size: width)
            balloon.fill(shape, with: .color(color))
            // Shine, so it reads as a balloon rather than a sticker.
            balloon.fill(Path(ellipseIn: CGRect(x: -width * 0.32, y: -width * 0.36, width: width * 0.18, height: width * 0.26)),
                         with: .color(.white.opacity(0.55)))
        }
    }

    // MARK: Approved stamp

    /// A big "APPROVED" passport stamp thumps down in the middle, with an ink splash, then smaller visa
    /// stamps land around it.
    private func stamp(_ context: inout GraphicsContext, _ size: CGSize) {
        var rng = SeededRandom(seed)
        context.opacity = fade(3.4, over: 0.7)
        let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
        let land = 0.32

        // A tiny shake when it lands.
        if time > land, time < land + 0.18 {
            let shake = sin((time - land) * 90) * 4 * (1 - (time - land) / 0.18)
            context.translateBy(x: shake, y: 0)
        }

        // Ink splash when it lands.
        if time > land {
            let t = min(1, (time - land) / 0.35)
            for _ in 0..<22 {
                let angle = rng.next() * .pi * 2, reach = 110 + rng.next() * 70, dot = 2 + rng.next() * 5
                let point = CGPoint(x: center.x + cos(angle) * reach * t, y: center.y + sin(angle) * reach * t * 0.8)
                var ink = context
                ink.opacity *= 0.8 * (1 - t * 0.4)
                ink.fill(Path(ellipseIn: CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)),
                         with: .color(Self.stampInk))
            }
        }

        // Smaller stamps landing around it.
        let small = [("OK", Self.pink), ("✓", Self.stampInk), ("VALID", Color(red: 0.2, green: 0.55, blue: 0.35)), ("♥", Self.pink)]
        for (i, item) in small.enumerated() {
            let at = land + 0.45 + Double(i) * 0.22
            let spot = CGPoint(x: size.width * (i % 2 == 0 ? 0.22 : 0.78) + (rng.next() - 0.5) * 30,
                               y: size.height * (i < 2 ? 0.22 : 0.64) + (rng.next() - 0.5) * 40)
            drawStamp(&context, text: item.0, color: item.1, center: spot, radius: 34, rotation: (rng.next() - 0.5) * 0.7,
                      progress: (time - at) / 0.18, round: true)
        }

        drawStamp(&context, text: "APPROVED", color: Self.stampInk, center: center, radius: 96, rotation: -0.2,
                  progress: time / land, round: false)
    }

    /// A stamp that drops from above (progress 0→1) and sits in place after (progress > 1).
    private func drawStamp(_ context: inout GraphicsContext, text: String, color: Color, center: CGPoint, radius: CGFloat,
                           rotation: Double, progress: Double, round: Bool) {
        guard progress > 0 else { return }
        let p = min(1, progress)
        let scale = 2.2 - 1.2 * (p * p)
        var stamp = context
        stamp.opacity *= min(1, p * 1.6) * 0.9
        stamp.translateBy(x: center.x, y: center.y)
        stamp.rotate(by: .radians(rotation))
        stamp.scaleBy(x: scale, y: scale)

        if round {
            stamp.stroke(Path(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)), with: .color(color), lineWidth: 3)
            stamp.stroke(Path(ellipseIn: CGRect(x: -radius + 5, y: -radius + 5, width: radius * 2 - 10, height: radius * 2 - 10)), with: .color(color), lineWidth: 1.2)
            stamp.draw(Text(text).font(.system(size: radius * 0.5, weight: .heavy, design: .rounded)).foregroundStyle(color), at: .zero)
        } else {
            let box = CGRect(x: -radius * 1.35, y: -radius * 0.55, width: radius * 2.7, height: radius * 1.1)
            stamp.stroke(Path(roundedRect: box, cornerRadius: 14), with: .color(color), lineWidth: 6)
            stamp.stroke(Path(roundedRect: box.insetBy(dx: 9, dy: 9), cornerRadius: 8), with: .color(color), lineWidth: 2)
            stamp.draw(Text(text).font(.system(size: radius * 0.42, weight: .black, design: .rounded)).kerning(3).foregroundStyle(color),
                       at: CGPoint(x: 0, y: -radius * 0.06))
            stamp.draw(Text("★ PASSPHOTO ★").font(.system(size: radius * 0.13, weight: .bold, design: .rounded)).kerning(2).foregroundStyle(color),
                       at: CGPoint(x: 0, y: radius * 0.3))
        }
    }

    // MARK: Paper planes

    /// Paper planes take off from the bottom and loop across the screen, each leaving a dashed flight path.
    private func planes(_ context: inout GraphicsContext, _ size: CGSize) {
        var rng = SeededRandom(seed)
        let colors = [Self.sky, Self.pink, Self.gold, Self.coral, Self.sky, Self.navy, Self.pink]
        context.opacity = fade(4.2, over: 0.8)
        for i in 0..<colors.count {
            let delay = Double(i) * 0.18 + rng.next() * 0.2
            let fromLeft = i % 2 == 0
            let start = CGPoint(x: fromLeft ? -30 : size.width + 30, y: size.height * (0.72 + rng.next() * 0.25))
            let end = CGPoint(x: fromLeft ? size.width + 40 : -40, y: size.height * (0.08 + rng.next() * 0.3))
            let control = CGPoint(x: size.width * (0.3 + rng.next() * 0.4), y: size.height * (0.1 + rng.next() * 0.5))
            let loops = rng.next() < 0.4
            let flight = 2.2 + rng.next() * 0.8
            let t = (time - delay) / flight
            guard t > 0 else { continue }
            let u = min(1, t)

            func position(_ u: Double) -> CGPoint {
                let a = 1 - u
                var p = CGPoint(x: a * a * start.x + 2 * a * u * control.x + u * u * end.x,
                                y: a * a * start.y + 2 * a * u * control.y + u * u * end.y)
                if loops {
                    // One loop-the-loop in the middle of the flight.
                    let l = max(0, min(1, (u - 0.4) / 0.25))
                    p.x += sin(l * .pi * 2) * 40 * (fromLeft ? 1 : -1)
                    p.y -= (1 - cos(l * .pi * 2)) * 40
                }
                return p
            }

            // Dashed flight path behind the plane.
            var trail = Path()
            let tail = max(0, u - 0.35)
            trail.move(to: position(tail))
            for step in stride(from: tail, through: u, by: 0.01) { trail.addLine(to: position(step)) }
            context.stroke(trail, with: .color(colors[i].opacity(0.7)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 7]))

            guard t < 1 else { continue }
            let here = position(u), ahead = position(min(1, u + 0.01))
            let angle = atan2(ahead.y - here.y, ahead.x - here.x)
            var plane = context
            plane.translateBy(x: here.x, y: here.y)
            plane.rotate(by: .radians(angle))
            plane.scaleBy(x: 1.5, y: 1.5)
            var body = Path()
            body.move(to: CGPoint(x: 18, y: 0))
            body.addLine(to: CGPoint(x: -14, y: -11))
            body.addLine(to: CGPoint(x: -8, y: 0))
            body.addLine(to: CGPoint(x: -14, y: 11))
            body.closeSubpath()
            plane.fill(body, with: .color(colors[i]))
            var fold = Path()
            fold.move(to: CGPoint(x: 18, y: 0))
            fold.addLine(to: CGPoint(x: -8, y: 0))
            plane.stroke(fold, with: .color(.black.opacity(0.25)), lineWidth: 1)
        }
    }
}

/// A small, fast, repeatable random sequence (SplitMix64), so a frame depends only on its seed and time.
struct SeededRandom {
    private var state: UInt64

    init(_ seed: UInt64) { state = seed }

    /// A value in 0..<1.
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
