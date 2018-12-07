import SpriteKit
import ARKit

enum DistanceState {
    case close
    case tooFar
}

enum VisibleState {
    case visible
    case invisible
}

/// Text badge showing guidance.
class Guidance: SKShapeNode {
    static private let fontSize: CGFloat = 14
    static private let font = UIFont.systemFont(ofSize: Guidance.fontSize,
                                                weight: UIFont.Weight.medium)
    static private let background = UIColor.black.withAlphaComponent(0.9)
    static private let outsets = UIEdgeInsets(top: -6, left: -10, bottom: -6, right: -10)
    static private let radius: CGFloat = 2
    
    private var text = SKLabelNode(fontNamed: Guidance.font.fontName)
    private var distanceState = DistanceState.tooFar
    private var trackingState = ARCamera.TrackingState.notAvailable
    private var visibleState = VisibleState.invisible
    
    /// - Parameter visionSquare: The square the vision model processes
    /// - Parameter viewSize: The size of the containing view
    init(visionSquare: CGRect, viewSize: CGSize) {
        super.init()
        
        text.fontSize = Guidance.fontSize
        text.position = nodeCenter(visionSquare: visionSquare, viewSize: viewSize)
        
        self.lineWidth = 0
        self.fillColor = Guidance.background
        self.addChild(text)
        self.alpha = 0
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Stateful updates
    
    func update(to state: ARCamera.TrackingState) {
        DispatchQueue.main.async {
            self.trackingState = state
            self.update()
        }
    }
    
    func update(to state: DistanceState) {
        DispatchQueue.main.async {
            self.distanceState = state
            self.update()
        }
    }
    
    /// Shows tracking issue messages first, then distance messages.
    private func update() {
        switch trackingState {
        case .notAvailable, .limited:
            setMessage(trackingState.presentationString)
            update(to: .visible)
        case .normal:
            switch distanceState {
            case .close: update(to: .invisible)
            case .tooFar:
                setMessage("Move closer")
                update(to: .visible)
            }
        }
    }
    
    private func update(to state: VisibleState) {
        guard visibleState != state else { return }
        self.removeAllActions()
        
        switch state {
        case .invisible:
            let fadeOut = SKAction.fadeOut(withDuration: 0.25)
            fadeOut.timingMode = .easeOut
            self.run(fadeOut)
        case .visible:
            let fadeIn = SKAction.fadeIn(withDuration: 0.25)
            fadeIn.timingMode = .easeIn
            self.run(fadeIn)
        }
        
        visibleState = state
    }
    
    // MARK: - Helpers
    
    /// Sets message and updates background.
    private func setMessage(_ message: String) {
        text.text = message
        path = CGPath.init(roundedRect: text.frame.inset(by: Guidance.outsets),
                           cornerWidth: Guidance.radius,
                           cornerHeight: Guidance.radius,
                           transform: nil)
    }
    
    /// Centered half way between the vision square and drawer.
    private func nodeCenter(visionSquare: CGRect, viewSize: CGSize) -> CGPoint {
        let topMargin = viewSize.height - visionSquare.origin.y - visionSquare.height
        return CGPoint(x: visionSquare.origin.x + (visionSquare.size.width / 2),
                       y: visionSquare.origin.y - (topMargin / 2))
    }
}

/// User facing guidance messages
extension ARCamera.TrackingState {
    var presentationString: String {
        switch self {
        case .notAvailable:
            return "Move iPhone to start"
        case .normal:
            return ""
        case .limited(.excessiveMotion):
            return "Slow down"
        case .limited(.insufficientFeatures):
            return "Find nearby berries to track"
        case .limited(.initializing):
            return "Move iPhone to start"
        case .limited(.relocalizing):
            return "Move iPhone to resume"
        }
    }
}
