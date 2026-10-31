import AppKit
import SwiftUI

private struct CopyCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.24, y: rect.height * 0.51))
        path.addLine(to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.69))
        path.addLine(to: CGPoint(x: rect.width * 0.78, y: rect.height * 0.31))
        return path
    }
}

private struct OrbitSpec {
    let radius: CGFloat
    let angles: (Double, Double, Double)
    let speeds: (Double, Double, Double)
    let opacity: Double

    static let all: [OrbitSpec] = [
        .init(radius: 20.5, angles: (28, 16, -10), speeds: (0.4, 1.2, 0.5), opacity: 1),
        .init(radius: 19.8, angles: (-38, -54, 42), speeds: (-2.1, 2.9, 1.4), opacity: 0.36),
        .init(radius: 19.3, angles: (70, -18, 18), speeds: (1.8, -3.8, -1.1), opacity: 0.28),
        .init(radius: 18.8, angles: (-62, 44, -22), speeds: (-1.5, -4.2, 1.7), opacity: 0.3),
        .init(radius: 18.3, angles: (22, 76, 55), speeds: (2.4, 2.5, -1.3), opacity: 0.25),
        .init(radius: 17.8, angles: (-18, -70, -54), speeds: (-2.2, 3.2, 1.1), opacity: 0.26),
        .init(radius: 17.3, angles: (82, 33, 77), speeds: (1.6, -2.8, -1.6), opacity: 0.23)
    ]
}

private struct OrbitRing: Shape {
    var progress: Double
    let spec: OrbitSpec
    let front: Bool
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let angleX = radians(spec.angles.0 + progress * 41 * spec.speeds.0)
        let angleY = radians(spec.angles.1 + progress * 41 * spec.speeds.1)
        let angleZ = radians(spec.angles.2 + progress * 41 * spec.speeds.2)
        let radius = rect.width * spec.radius / 48
        let points: [(CGPoint, Double)] = (0...96).map { index in
            let theta = Double(index) * .pi * 2 / 96
            let x0 = Double(radius) * cos(theta)
            let y0 = Double(radius) * sin(theta)
            let y1 = y0 * cos(angleX)
            let z1 = y0 * sin(angleX)
            let x2 = x0 * cos(angleY) + z1 * sin(angleY)
            let z2 = -x0 * sin(angleY) + z1 * cos(angleY)
            let point = CGPoint(x: rect.midX + x2 * cos(angleZ) - y1 * sin(angleZ),
                                y: rect.midY + x2 * sin(angleZ) + y1 * cos(angleZ))
            return (point, z2)
        }
        var path = Path()
        var previousFront: Bool?
        for index in 0..<96 {
            let isFront = points[index].1 + points[index + 1].1 >= 0
            if isFront != previousFront { path.move(to: points[index].0) }
            if isFront == front { path.addLine(to: points[index + 1].0) }
            previousFront = isFront
        }
        return path
    }

    private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}

@MainActor final class CopyFeedbackAnimator: ObservableObject {
    @Published private(set) var bookOpacity = 1.0
    @Published private(set) var ringOpacity = 0.0
    @Published private(set) var ringRotation = -110.0
    @Published private(set) var orbitProgress = 0.0
    @Published private(set) var checkOpacity = 0.0
    @Published private(set) var checkProgress = 0.0
    private var animationTask: Task<Void, Never>?

    func reset(animated: Bool = false) {
        animationTask?.cancel()
        if animated {
            withAnimation(.easeInOut(duration: 0.12)) { applyInitialState() }
        } else {
            applyInitialState()
        }
    }

    func start() {
        reset()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            withAnimation(.easeOut(duration: 0.1)) {
                bookOpacity = 0
                checkOpacity = 1
                checkProgress = 1
            }
            return
        }
        animationTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.1)) {
                bookOpacity = 0
                ringOpacity = 1
            }
            withAnimation(.linear(duration: 0.65)) { orbitProgress = 1 }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.65)) {
                ringRotation = 250
            }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.12)) {
                ringOpacity = 0
                checkOpacity = 1
            }
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) {
                checkProgress = 1
            }
        }
    }

    private func applyInitialState() {
        bookOpacity = 1
        ringOpacity = 0
        ringRotation = -110
        orbitProgress = 0
        checkOpacity = 0
        checkProgress = 0
    }
}

struct CopyFeedbackIcon: View {
    @ObservedObject var animator: CopyFeedbackAnimator
    let tight: Bool
    private var diameter: CGFloat { tight ? 20 : 24 }

    var body: some View {
        ZStack {
            Image(systemName: "character.book.closed")
                .font(.system(size: tight ? 16 : 19, weight: .regular))
                .opacity(animator.bookOpacity)

            ZStack {
                ForEach(OrbitSpec.all.indices, id: \.self) { index in
                    let spec = OrbitSpec.all[index]
                    OrbitRing(progress: animator.orbitProgress, spec: spec, front: false)
                        .stroke(Color.secondary.opacity(spec.opacity * 0.27), lineWidth: tight ? 0.45 : 0.55)
                    OrbitRing(progress: animator.orbitProgress, spec: spec, front: true)
                        .stroke(Color.secondary.opacity(spec.opacity * (index == 0 ? 0.55 : 0.4)), lineWidth: tight ? (index == 0 ? 2.3 : 1.6) : (index == 0 ? 2.75 : 1.9))
                        .blur(radius: tight ? 0.32 : 0.4)
                    OrbitRing(progress: animator.orbitProgress, spec: spec, front: true)
                        .stroke(Color.secondary.opacity(spec.opacity * (index == 0 ? 0.95 : 0.75)), lineWidth: tight ? (index == 0 ? 1.17 : 0.44) : (index == 0 ? 1.4 : 0.53))
                }
            }
            .frame(width: diameter, height: diameter)
            .opacity(animator.ringOpacity)

            Circle()
                .trim(from: 0, to: 0.42)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: tight ? 1.7 : 2, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(animator.ringRotation))
                .opacity(animator.ringOpacity)

            Circle()
                .stroke(Color.secondary, lineWidth: tight ? 1.2 : 1.4)
                .frame(width: diameter, height: diameter)
                .opacity(animator.checkOpacity)

            CopyCheckmark()
                .trim(from: 0, to: animator.checkProgress)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: tight ? 1.8 : 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: diameter, height: diameter)
                .opacity(animator.checkOpacity)
        }
        .foregroundStyle(.secondary)
        .frame(width: tight ? 24 : 30, height: 28)
        .contentShape(Rectangle())
    }
}
