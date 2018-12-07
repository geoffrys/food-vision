import UIKit
import Vision

/// Foods (berries) that FoodModel can recognize, including a background category.
enum Food: String, CaseIterable {
    case background = "background"
    case cherry = "cherry"
    case raspberry = "raspberry"
    case strawberry = "strawberry"
}

/// Separated region marked as a particular type of food.
///
/// Frame is in the coordinate space of the original image
struct PixelObservation: Equatable {
    let food: Food
    let frame: CGRect
    let pixels: Int
}

/// Per-pixel semantic segmentation labels from the result of FoodModel.mlmodel.
///
/// MLMultiArray is converted into a 2D array of Food (labels) and an overlay image
struct Labels {
    let width: Int
    let height: Int
    let multi: MLMultiArray
    let labels: [[Food]]
    let overlay: CIImage?
    
    /// - Parameter multi: the output of FoodModel.mlmodel
    init(_ multi: MLMultiArray) {
        var pointer: UnsafeMutablePointer<Float32>
        pointer = UnsafeMutablePointer(OpaquePointer(multi.dataPointer))
        
        // Shape is [_, batch, channel, height, width]
        let height = multi.shape[3].intValue
        let width = multi.shape[4].intValue
        let strides = multi.strides.map { $0.intValue }
        let getIndex = { (channel: Int, height: Int, width: Int) in
            return channel*strides[2] + height*strides[3] + width*strides[4]
        }
        
        // Convert MLMultiArray into something more user friendly
        var labels = [[Food]](repeating: [Food](repeating: Food.background,
                                                count:width),
                              count: height)
        var overlay = [UInt8](repeating: 0, count: width * height)
        
        for h in 0..<height {
            for w in 0..<width {
                let r = pointer[getIndex(0, h, w)]
                let g = pointer[getIndex(1, h, w)]
                let b = pointer[getIndex(2, h, w)]
                let a = pointer[getIndex(3, h, w)]
                
                // This argmax equivalent should just be in the model
                let isCherry = g > r && g > b && g > a
                let isRaspberry = b > r && b > g && b > a
                let isStrawberry = a > r && a > g && a > b
                
                if isCherry {
                    labels[h][w] = .cherry
                    overlay[h*width + w] = 63
                } else if isRaspberry {
                    labels[h][w] = .raspberry
                    overlay[h*width + w] = 127
                } else if isStrawberry {
                    labels[h][w] = .strawberry
                    overlay[h*width + w] = 190
                }
            }
        }
        
        self.width = width
        self.height = height
        self.multi = multi
        self.labels = labels
        
        self.overlay = CIImage(bytes: overlay, width: width, height: height)
        
    }
    
    /// Given a point, returns 4-connected pixels (left, right, top, bottom).
    func neighbors(of point: CGPoint, width: Int, height: Int) -> [CGPoint] {
        var points = [CGPoint]()
        let offsets = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for (offsetX, offsetY) in offsets {
            let x = Int(point.x) + offsetX
            let y = Int(point.y) + offsetY
            if x >= 0 && x < width && y >= 0 && y < height {
                points.append(CGPoint(x: x, y: y))
            }
        }
        return points
    }
    
    /// Returns a list of clusters of connected pixels of the same food.
    ///
    /// An implementation of connected-component labeling.
    ///
    /// - Warning: This is *terribly* slow compared to running the vision model,
    /// the model should do instance segmentation instead.
    ///
    /// - Complexity: O(N), linear to pixel count. However, a scene with no food
    /// is roughly twice as fast as a scene full of food.
    func connectedComponents(of food: Food) -> [PixelObservation] {
        var observations = [PixelObservation]()
        var visited = [[Bool]](repeating: [Bool](repeating: false,
                                                 count:width),
                               count: height)
        
        for h in 0..<height {
            for w in 0..<width {
                var frame = CGRect(x: w, y: h, width: 0, height: 0)
                var connectedPixels = 0
                var queue = [CGPoint]()
                let label = labels[h][w]
                if !visited[h][w] && label == food {
                    queue.append(CGPoint(x: w, y: h))
                }
                
                // BFS of unvisted neighbors via a queue
                while let point = queue.popLast() {
                    let x = Int(point.x)
                    let y = Int(point.y)
                    
                    if !visited[y][x] && labels[y][x] == food {
                        queue.append(contentsOf: neighbors(of: point,
                                                           width: width,
                                                           height: height))
                        connectedPixels += 1
                        frame = frame.expanded(toCover: point)
                        visited[y][x] = true
                    }
                }
                
                if connectedPixels > 10 {
                    observations.append(PixelObservation(food: food,
                                                         frame: frame,
                                                         pixels: connectedPixels))
                }
            }
        }
        
        return observations
    }
}
