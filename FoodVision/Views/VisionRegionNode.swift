import SpriteKit

/// Marks the four corners of the vision area, as it's a subset of the video stream.
class VisionRegion: SKNode {
    static private let inset = UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    static private let color = UIColor.white
    static private let size: CGFloat = 32
    static private let radius: CGFloat = 12
    static private let lineWidth: CGFloat = 4
    static private let shadowColor = UIColor.black.withAlphaComponent(0.2)
    static private let shadowBlur: CGFloat = 3
    
    /// - Parameter visionSquare: The square area FoodModel is actually given
    init(visionSquare: CGRect) {
        super.init()

        let insetSquare = visionSquare.inset(by: VisionRegion.inset)
        
        self.position = insetSquare.origin
        self.zPosition = 10
        let path = cornerPath(frame: insetSquare,
                              size: VisionRegion.size,
                              radius: VisionRegion.radius)
        
        let shadow = SKShapeNode(path: path)
        shadow.position.y -= 2
        shadow.lineWidth = VisionRegion.lineWidth
        shadow.strokeColor = VisionRegion.shadowColor
        shadow.glowWidth = VisionRegion.shadowBlur
        shadow.lineCap = .round
        self.addChild(shadow)
        
        let guides = SKShapeNode(path: path)
        guides.lineWidth = VisionRegion.lineWidth
        guides.strokeColor = .white
        guides.lineCap = .round
        self.addChild(guides)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// Paths for four corner guides to mark the bounds of the vision area.
    private func cornerPath(frame: CGRect, size: CGFloat, radius: CGFloat) -> CGMutablePath {
        let path = CGMutablePath()
        
        // Make bottom left corner piece
        let a = CGPoint(x: 0, y: size)
        let b = CGPoint(x: 0, y: 0)
        let c = CGPoint(x: size, y: 0)
        path.move(to: a)
        path.addArc(tangent1End: b, tangent2End: c, radius: radius)
        path.addLine(to: c)
        
        // Shift a copy of the corner to the right and flip horizontally
        let shiftRight = CGAffineTransform(translationX: frame.width, y: 0)
        let flipHorizontal = shiftRight.scaledBy(x: -1, y: 1)
        path.addPath(path, transform: flipHorizontal)
        
        // Shift a copy of both bottom corners up and flip vertically
        let shiftUp = CGAffineTransform(translationX: 0, y: frame.height)
        let flipVertical = shiftUp.scaledBy(x: 1, y: -1)
        path.addPath(path, transform: flipVertical)
        
        return path
    }
}
