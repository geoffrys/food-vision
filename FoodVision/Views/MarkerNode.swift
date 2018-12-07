import SpriteKit
import ARKit

enum TouchState {
    case touchIn
    case touchOut
}

enum HeightState {
    case tall
    case short
}

enum DetailState {
    case expanded
    case collapsed
}

/// Parent node for markers which handles touch events.
class Markers: SKShapeNode {
    private static let maxDistance: CGFloat = 50
    
    private var touchedNode: Marker?
    private var expandedNode: Marker?
    
    init(frame: CGRect) {
        super.init()
        
        // Expand our touch receiving area to cover view
        self.path = CGPath.init(rect: frame, transform: nil)
        self.strokeColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func addChild(_ node: SKNode) {
        super.addChild(node)
        
        guard let marker = node as? Marker else { return }
        // If another node is showing details, we need to start minimized
        if expandedNode != nil {
            marker.update(to: .short, animate: false)
            marker.update(to: .collapsed, animate: false)
        }
    }
    
    override func removeChildren(in nodes: [SKNode]) {
        super.removeChildren(in: nodes)
        
        for node in nodes {
            guard let marker = node as? Marker else { return }
            if marker == touchedNode {
                touchedNode = nil
            }
            if marker == expandedNode {
                expandedNode = nil
            }
        }
    }
    
    override func removeAllChildren() {
        super.removeAllChildren()
        touchedNode = nil
        expandedNode = nil
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touching(touch)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        touching(touch)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        
        touchedNode?.update(to: .touchOut)
        touchedNode = nil
        
        if let marker = closestMarker(to: point) {
            // Touch up inside a node
            expand(marker)
            return
        }
        
        // Touch up outside
        expand(nil)
    }
    
    /// Visualizes when a touch hits a node.
    private func touching(_ touch: UITouch) {
        let point = touch.location(in: self)
        
        // Touching a node at all
        if let marker = closestMarker(to: point) {
            // Already animating this node
            if marker == touchedNode {
                return
            }
            
            // Start animating this node
            touchedNode?.update(to: .touchOut)
            marker.update(to: .touchIn)
            touchedNode = marker
        } else {
            // Touching nothing
            touchedNode?.update(to: .touchOut)
            touchedNode = nil
        }
    }
    
    /// Expands a node to show its details, emphasizing the node by minimizing others.
    private func expand(_ marker: Marker?) {
        let markers = (children as? [Marker]) ?? []
        
        guard let target = marker, target != expandedNode else {
            // Not highlighting any particular pin
            expandedNode = nil
            for child in markers {
                child.update(to: .tall)
                child.update(to: .collapsed)
            }
            return
        }
        
        // Highlight a single pin
        expandedNode = target
        for child in markers.filter({ $0 != target }) {
            child.update(to: .short)
            child.update(to: .collapsed)
        }
        target.update(to: .tall)
        target.update(to: .expanded)
    }
    
    /// Returns the closest marker, measured from center, with a max distance
    /// (Markers.maxDistance).
    private func closestMarker(`to` point: CGPoint) -> Marker? {
        var bestDistance: CGFloat?
        var bestMarker: Marker?
        for child in (children as? [Marker]) ?? [] {
            // The origins are center points in parent's coord
            let circleCenter = child.topGroup.frame.origin
            let distance = point.distance(to: circleCenter)
            
            guard distance < Markers.maxDistance else { continue }
            guard let lastDistance = bestDistance else {
                bestDistance = distance
                bestMarker = child
                continue
            }

            if distance < lastDistance {
                bestDistance = distance
                bestMarker = child
            }
        }
        return bestMarker
    }
}

/// Marks where in a scene food clusters were detected.
///
/// Can expand to show mass and calories in addition to the always visible count.
class Marker: SKNode {
    static private let duration: Double = 0.200
    static private let diameter: CGFloat = 30
    static private let expandedWidth: CGFloat = 118
    static private let expandedRadius: CGFloat = 3
    static private let padding: CGFloat = 6
    static private let hoverUp: Float = 0.025
    static private let shadowColor = UIColor.black.withAlphaComponent(0.50)
    static private let shadowBlur: CGFloat = 13
    static private let lineColor = UIColor.white.withAlphaComponent(0.70)
    static private let fontSize: CGFloat = 12
    static private let countColor = UIColor.white
    static private let detailColor = UIColor.black.withAlphaComponent(0.54)
    static private let font = UIFont.systemFont(ofSize: Marker.fontSize,
                                                weight: UIFont.Weight.medium)
    
    let foodEstimate: FoodEstimate
    let anchor: ARAnchor
    let line: SKShapeNode
    var background: SKShapeNode
    var shadow: SKShapeNode
    var foodIcon: SKSpriteNode
    var massLabel: SKLabelNode
    var calorieLabel: SKLabelNode
    let topGroup: SKNode
    var touchState = TouchState.touchOut
    var heightState = HeightState.tall
    var lineFactor: Float = 1.0
    var detailState = DetailState.collapsed
    var expandedFactor: Float = 0.0
    
    init(for foodEstimate: FoodEstimate, anchor: ARAnchor) {
        self.foodEstimate = foodEstimate
        self.anchor = anchor
        self.line = SKShapeNode(rect: CGRect(origin: CGPoint.zero, size: CGSize.zero))
        let size = CGSize(width: Marker.diameter / 2, height: Marker.diameter / 2)
        let origin = CGPoint(x: -size.width / 2, y: -size.height / 2)
        self.shadow = SKShapeNode(rect: CGRect(origin: origin, size: size))
        self.background = SKShapeNode(rect: CGRect(origin: origin, size: size))
        self.foodIcon = SKSpriteNode(texture: nil)
        self.massLabel = SKLabelNode(fontNamed: Marker.font.fontName)
        self.calorieLabel = SKLabelNode(fontNamed: Marker.font.fontName)
        self.topGroup = SKNode()
        super.init()
        
        makeLine()
        self.addChild(line)
        
        makeTopGroup()
        makeDetail()
        topGroup.zPosition = 1
        self.addChild(topGroup)
        self.alpha = 0
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func makeLine() {
        line.fillColor = Marker.lineColor
        line.strokeColor = .clear
        line.zPosition = 0
    }
    
    private func makeTopGroup() {
        let shadowEffect = SKEffectNode()
        shadow.position.y -= Marker.shadowBlur / 2.3
        shadow.fillColor = Marker.shadowColor
        shadow.strokeColor = .clear
        shadow.zPosition = 1
        shadowEffect.filter = CIFilter(name: "CIGaussianBlur",
                                       parameters: ["inputRadius": Marker.shadowBlur])
        shadowEffect.addChild(shadow)
        topGroup.addChild(shadowEffect)
        
        background.fillColor = .white
        background.strokeColor = .clear
        background.zPosition = 2
        topGroup.addChild(background)
        
        let filename = "\(foodEstimate.observation.food.rawValue)_number"
        foodIcon.texture = SKTexture(imageNamed: filename)
        foodIcon.size = CGSize(width: Marker.diameter - Marker.padding,
                               height: Marker.diameter - Marker.padding)
        foodIcon.zPosition = 3
        
        let countLabel = SKLabelNode(fontNamed: Marker.font.fontName)
        countLabel.fontColor = Marker.countColor
        countLabel.fontSize = Marker.fontSize
        if let count = foodEstimate.count() {
            countLabel.text = "\(count)"
        }
        countLabel.horizontalAlignmentMode = .center
        countLabel.verticalAlignmentMode = .center
        countLabel.zPosition = 4
        foodIcon.addChild(countLabel)
        topGroup.addChild(foodIcon)
    }
    
    private func makeDetail() {
        massLabel.fontColor = Marker.detailColor
        massLabel.fontSize = Marker.fontSize
        if let mass = foodEstimate.mass() {
            massLabel.text = "\(Int(mass))g"
        }
        massLabel.horizontalAlignmentMode = .center
        massLabel.verticalAlignmentMode = .center
        massLabel.zPosition = 4
        massLabel.alpha = 0
        topGroup.addChild(massLabel)
        
        calorieLabel.fontColor = Marker.detailColor
        calorieLabel.fontSize = Marker.fontSize
        if let calories = foodEstimate.calories() {
            calorieLabel.text = "\(Int(calories))cal"
        }
        calorieLabel.horizontalAlignmentMode = .center
        calorieLabel.verticalAlignmentMode = .center
        calorieLabel.zPosition = 4
        calorieLabel.alpha = 0
        topGroup.addChild(calorieLabel)
    }
    
    // MARK: - Stateful updates
    
    private let touchKey = "touch"
    private let heightKey = "height"
    private let detailKey = "detail"

    /// Animates in response to user touch.
    func update(to state: TouchState) {
        DispatchQueue.main.async {
            guard self.touchState != state else { return }
            self.topGroup.removeAction(forKey: self.touchKey)
            
            let growth: CGFloat = (self.detailState == .expanded) ? 1.2 : 1.4
            switch state {
            case .touchIn:
                let grow = SKAction.scale(to: growth, duration: Marker.duration)
                grow.timingMode = .easeIn
                self.topGroup.run(grow, withKey: self.touchKey)
            case .touchOut:
                let shrink = SKAction.scale(to: 1, duration: Marker.duration)
                shrink.timingMode = .easeOut
                self.topGroup.run(shrink, withKey: self.touchKey)
            }
            
            self.touchState = state
        }
    }
    
    /// Raises or lowers the pin to emphasize one when expanded.
    func update(to state: HeightState, animate: Bool = true) {
        DispatchQueue.main.async {
            guard self.heightState != state else { return }
            self.removeAction(forKey: self.heightKey)

            let setter: (SKNode, Float) -> () = { node, value in
                (node as? Marker)?.lineFactor = value
            }
            switch state {
            case .tall:
                if animate {
                    let maximizePin = SKAction.transition(to: 1,
                                                          from: self.lineFactor,
                                                          duration: Marker.duration,
                                                          setter: setter)
                    maximizePin.timingMode = .easeIn
                    self.run(maximizePin, withKey: self.heightKey)
                } else {
                    self.lineFactor = 1
                }
            case .short:
                if animate {
                    let minimizePin = SKAction.transition(to: 0,
                                                          from: self.lineFactor,
                                                          duration: Marker.duration,
                                                          setter: setter)
                    minimizePin.timingMode = .easeOut
                    self.run(minimizePin, withKey: self.heightKey)
                } else {
                    self.lineFactor = 0
                }
            }
            
            self.heightState = state
        }
    }
    
    /// Shows either just the count or the count, mass, and calories.
    func update(to state: DetailState, animate: Bool = true) {
        DispatchQueue.main.async {
            guard self.detailState != state else { return }
            self.removeAction(forKey: self.detailKey)
            
            let setter: (SKNode, Float) -> () = { node, value in
                (node as? Marker)?.expandedFactor = value
            }
            
            switch state {
            case .expanded:
                if animate {
                    let expand = SKAction.transition(to: 1,
                                                     from: self.expandedFactor,
                                                     duration: Marker.duration,
                                                     setter: setter)
                    expand.timingMode = .easeIn
                    self.run(expand, withKey: self.detailKey)
                } else {
                    self.expandedFactor = 1
                }
            case .collapsed:
                if animate {
                    let collapse = SKAction.transition(to: 0,
                                                       from: self.expandedFactor,
                                                       duration: Marker.duration,
                                                       setter: setter)
                    collapse.timingMode = .easeOut
                    self.run(collapse, withKey: self.detailKey)
                } else {
                    self.expandedFactor = 0
                }
            }
            
            self.detailState = state
        }
    }
    
    /// Draws pin line: a 2D projection of a line between two 3D points.
    ///
    /// The bottom point is the center of the object while the top is a fixed
    /// (Marker.hoverUp) world sapce height above it.
    func update(with frame: ARFrame, viewFrame: CGRect) {
        let worldBottom = anchor.transform.position()
        let sceneBottom = scenePoint(at: worldBottom, frame: frame, viewSize: viewFrame.size)
        
        let offset = lineFactor * Marker.hoverUp
        let worldTop = float3(x: worldBottom.x, y: worldBottom.y + offset, z: worldBottom.z)
        let sceneTop = scenePoint(at: worldTop, frame: frame, viewSize: viewFrame.size)

        DispatchQueue.main.async {
            self.updateLine(sceneBottom: sceneBottom, sceneTop: sceneTop, viewFrame: viewFrame)
            self.updateTop(sceneTop: sceneTop)
            
            self.alpha = 1
        }
    }
    
    /// - Parameter sceneBottom: The scene-space bottom of the line
    /// - Parameter sceneTop: The scene-space top of the line
    private func updateLine(sceneBottom: CGPoint, sceneTop: CGPoint, viewFrame: CGRect) {
        // Hide line for equal top and bottom points
        self.line.alpha = 0
        if sceneBottom != sceneTop {
            // Get unit vector perpendicular in screen space to vector bottom->top
            let vector = sceneBottom - sceneTop
            let perpendicular = randomPerpendicular(to: vector)
            let perpendicularUnit = perpendicular.normed()
            
            // The line is 2 units wide
            let points: [CGPoint] = [sceneBottom - perpendicularUnit,
                                     sceneTop - perpendicularUnit,
                                     sceneTop + perpendicularUnit,
                                     sceneBottom + perpendicularUnit]
            
            // Check that bottom and top of the pin are visible.
            // Projecting off screen points to screen space can result in coordinates
            // that cross the screen when drawing a line between them, which no longer
            // allows us to rely on SpriteKit visibility culling.
            if points.allSatisfy({ $0.visible(in: viewFrame) }) {
                let path = CGMutablePath()
                path.addLines(between: points)
                path.closeSubpath()
                self.line.path = path
                self.line.alpha = 1
            }
        }
    }
    
    /// - Parameter sceneTop: The scene-space top of the line where content is placed
    private func updateTop(sceneTop: CGPoint) {
        // Calculate top background and shadow shape
        let width = CGFloat(expandedFactor).lerp(Marker.diameter, Marker.expandedWidth)
        let radius = CGFloat(1 - expandedFactor).lerp(Marker.expandedRadius, Marker.diameter / 2)
        let size = CGSize(width: width, height: Marker.diameter)
        let origin = CGPoint(x: -size.width / 2, y: -size.height / 2)
        background.path = SKShapeNode.init(rect: CGRect(origin: origin, size: size),
                                           cornerRadius: radius).path
        shadow.path = background.path
        
        // Update contents with equal spacing
        let iconPadding: CGFloat = 5
        let spacing = width - Marker.diameter + iconPadding - massLabel.frame.width - calorieLabel.frame.width
        let leftEdge = -(width / 2)
        let foodX = leftEdge + (Marker.diameter / 2)
        let visualFoodX = foodX + (Marker.diameter / 2) - iconPadding
        let massX = visualFoodX + (spacing / 3) + (massLabel.frame.width / 2)
        let calorieX = massX + (massLabel.frame.width / 2) + (spacing / 3) + (calorieLabel.frame.width / 2)
        
        foodIcon.position = CGPoint(x: foodX, y: 0)
        massLabel.position = CGPoint(x: massX, y: 0)
        calorieLabel.position = CGPoint(x: calorieX, y: 0)
        
        // Stagger the alpha transitions of mass and calories
        let massStart: Float = 0.5
        let massFactor = (expandedFactor < massStart) ? 0 : (expandedFactor - massStart) / (1 - massStart)
        massLabel.alpha = CGFloat(massFactor)
        let calorieStart: Float = 0.75
        let calorieFactor = (expandedFactor < calorieStart) ? 0 : (expandedFactor - calorieStart) / (1 - calorieStart)
        calorieLabel.alpha = CGFloat(calorieFactor)
        
        // Position top group in space
        topGroup.position = sceneTop
        switch detailState {
        case .expanded: topGroup.zPosition = 100
        case .collapsed: topGroup.zPosition = 1
        }
    }
    
    // MARK: - Helpers
    
    private func scenePoint(at worldPosition: float3, frame: ARFrame, viewSize: CGSize) -> CGPoint {
        let viewPoint = frame.camera.projectPoint(worldPosition,
                                                  orientation: .portrait,
                                                  viewportSize: viewSize)
        return CGPoint(x: viewPoint.x, y: viewSize.height - viewPoint.y)
    }
    
    /// Returns a random perpendicular line.
    private func randomPerpendicular(to vector: CGPoint) -> CGPoint {
        // The dot product of two lines is equal to 0 when perpendicular
        // For original vector A: (xa, ya), and new perpendicular vector: B: (xb, yb)
        // The perpendicular plane is defined as 0 = xa*xb + ya*yb
        // If we pick a non-zero xb, we can solve for a random vector on the plane
        let randomX: CGFloat = 2
        let solvedY = (randomX * vector.x) / vector.y
        return CGPoint(x: randomX, y: solvedY)
    }
}
