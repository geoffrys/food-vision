import Foundation
import ARKit

// MARK: - View extensions

extension UIView {
    func roundCorners(corners: UIRectCorner, radius: CGFloat) {
        let mask = CAShapeLayer()
        let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        mask.path = path.cgPath
        layer.mask = mask
    }
}

extension SKAction {
    /// Performs linear interpolation between from and to, using the setter to
    /// modify the node.
    ///
    /// Regardless of the distance between from and to, the animation runs for
    /// duration.
    static func transition(to: Float, from: Float, duration: Double, setter: @escaping (SKNode, Float) -> ()) -> SKAction {
        let action = SKAction.customAction(withDuration: Double(duration),
                                           actionBlock: { node, elapsedTime in
                                            let progress = (to - from) * (Float(elapsedTime) / Float(duration))
                                            setter(node, from + progress)
        })
        return action
    }
}

// https://medium.com/ios-os-x-development/demystifying-uikit-spring-animations-2bb868446773
extension UISpringTimingParameters {
    convenience init(damping: CGFloat, response: CGFloat) {
        let mass: CGFloat = 1
        let stiffness = pow(2 * .pi / response, 2) * mass
        let damping = 4 * .pi * damping * mass / response
        
        self.init(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: .zero)
    }
}

// MARK: - Orientation extensions

extension UIDeviceOrientation {
    init(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        // Direction the device moves vs direction content moves
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: self = .unknown
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIDeviceOrientation) {
        // Sensor native orientation is landscape, so when in portrait mode we rotate right
        switch orientation {
        case .portraitUpsideDown: self = .left
        case .landscapeLeft: self = .up
        case .landscapeRight: self = .down
        default: self = .right
        }
    }
}

extension UIImage.Orientation {
    init(_ orientation: CGImagePropertyOrientation) {
        switch orientation {
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        default: self = .up
        }
    }
}

// MARK: - Image extensions

extension CIImage {
    convenience init?(bytes: [UInt8], width: Int, height: Int) {
        var cgImage: CGImage?
        
        bytes.withUnsafeBytes { pointer in
            if let baseAddress = pointer.baseAddress {
                let context = CGContext(
                    data: UnsafeMutableRawPointer(mutating: baseAddress),
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
                )
                cgImage = context?.makeImage()
            }
        }
        
        guard let image = cgImage else { return nil }
        self.init(cgImage: image)
    }
    
    /// Return CIImage that has been cropped, and centered on the cropped region.
    func croppedAlign(to cropRect: CGRect) -> CIImage {
        let cropped = self.cropped(to: cropRect)
        // Translate so the cropped section is in view
        let center = CGAffineTransform(translationX: -cropped.extent.origin.x,
                                       y: -cropped.extent.origin.y)
        return cropped.transformed(by: center)
    }
}

// MARK: - Matrix, vector, point, and numeric extensions

extension float4x4 {
    init(translation vector: float3) {
        self.init(float4(1, 0, 0, 0),
                  float4(0, 1, 0, 0),
                  float4(0, 0, 1, 0),
                  float4(vector.x, vector.y, vector.z, 1))
    }
}

extension matrix_float4x4 {
    func position() -> float3 {
        return float3(columns.3.x, columns.3.y, columns.3.z)
    }
}

extension float3 {
    func distance(to point: float3) -> Float {
        return (self - point).length()
    }
    
    func length() -> Float {
        return sqrtf(x*x + y*y + z*z)
    }
}

extension CGRect {
    func expanded(toCover point: CGPoint) -> CGRect {
        let minX = min(point.x, self.minX)
        let minY = min(point.y, self.minY)
        let maxX = max(point.x, self.maxX)
        let maxY = max(point.y, self.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
    
    /// Converts a UIView's coordinate system to an SKView's coordinate system
    /// by flipping Y-direction.
    func converted(toScene target: SKView) -> CGRect {
        return CGRect(x: self.minX,
                      y: target.frame.height - self.maxY,
                      width: self.width,
                      height: self.height)
    }
}

extension CGPoint {
    func visible(`in` rect: CGRect) -> Bool {
        return (rect.minX...rect.maxX).contains(self.x) &&
               (rect.minY...rect.maxY).contains(self.y)
    }
    
    func distance(to point: CGPoint) -> CGFloat {
        return (self - point).length()
    }
    
    func normed() -> CGPoint {
        return self / self.length()
    }
    
    func length() -> CGFloat {
        return (x*x + y*y).squareRoot()
    }
}

extension CGFloat {
    /// Linear interpolation between two numbers. Assumes self is 0-1.
    func lerp(_ from: CGFloat, _ to: CGFloat) -> CGFloat {
        return from + (self * (to - from))
    }
}

// MARK: - Math overloads

func - (left: SCNVector3, right: SCNVector3) -> SCNVector3 {
    return SCNVector3Make(left.x - right.x, left.y - right.y, left.z - right.z)
}

func - (left: CGPoint, right: CGPoint) -> CGPoint {
    return CGPoint(x: left.x - right.x, y: left.y - right.y)
}

func + (left: CGPoint, right: CGPoint) -> CGPoint {
    return CGPoint(x: left.x + right.x, y: left.y + right.y)
}

func / (point: CGPoint, value: CGFloat) -> CGPoint {
    return CGPoint(x: point.x / value, y: point.y / value)
}
