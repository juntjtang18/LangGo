import UIKit
import SwiftUI

/// Simple, lightweight confetti burst using CAEmitterLayer.
struct CelebrationConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = ConfettiHostView()
        view.start()
        // Auto-stop birth after a short burst; remaining particles finish naturally
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            view.stop()
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private final class ConfettiHostView: UIView {
    private let emitter = CAEmitterLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(emitter)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        emitter.emitterShape = .point
    }

    func start() {
        emitter.emitterCells = makeBurstCells()
        emitter.beginTime = CACurrentMediaTime()
        emitter.birthRate = 1.0
    }
    func stop() {
        emitter.birthRate = 0.0
    }

    private func makeBurstCells() -> [CAEmitterCell] {
        let colors: [UIColor] = [.systemPink, .systemTeal, .systemYellow, .systemGreen, .systemPurple, .systemOrange]
        let images: [CGImage] = [
            shapeImage(.circle, color: .white).cgImage!,
            shapeImage(.star, color: .white).cgImage!
        ]
        return (0..<10).map { i in
            let cell = CAEmitterCell()
            cell.contents = images[i % images.count]
            cell.color = colors[i % colors.count].cgColor
            cell.birthRate = 8
            cell.lifetime = 1.6
            cell.velocity = 280
            cell.velocityRange = 120
            cell.scale = 0.06
            cell.scaleRange = 0.03
            cell.emissionRange = .pi * 2 // 360° burst
            cell.spin = 2
            cell.spinRange = 3
            cell.yAcceleration = 40
            return cell
        }
    }

    private enum Shape { case circle, star }

    private func shapeImage(_ shape: Shape, color: UIColor, size: CGFloat = 24) -> UIImage {
        let r = size
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: r, height: r), format: format)
        return renderer.image { ctx in
            color.setFill()
            switch shape {
            case .circle:
                UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: r, height: r)).fill()
            case .star:
                let path = UIBezierPath()
                let center = CGPoint(x: r/2, y: r/2)
                let points = 5
                let outer: CGFloat = r/2
                let inner: CGFloat = outer * 0.45
                for i in 0..<(points*2) {
                    let angle = CGFloat(i) * .pi / CGFloat(points)
                    let radius = (i % 2 == 0) ? outer : inner
                    let pt = CGPoint(
                        x: center.x + radius * sin(angle),
                        y: center.y - radius * cos(angle)
                    )
                    i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                path.close()
                path.fill()
            }
        }
    }
}
