import UIKit

/// Nutrients per 1g of food, with all units in grams except energy which is kcal.
struct Nutrients {
    let water: Float
    let energy: Float
    let protein: Float
    let lipid: Float
    let carbohydrate: Float
    let fiber: Float
    let sugars: Float
}

/// Physical food estimates, from pixel segmentation labels and a single length.
struct FoodEstimate {
    /// Mass average in grams of a literal handful of berries from one container
    private static let averageMass: [Food: Float] = [
        .raspberry: 3.2,
        .strawberry: 15
    ]
    
    /// I haven't actually measured the area raspberries and strawberries tend to
    /// visually take up from any view, so I'm estimating with a magic factor.
    private static let averageArea: [Food: Float] = [
        .raspberry: 0.02 * 0.02 * 0.8,
        .strawberry: 0.035 * 0.035 * 0.9
    ]
    
    /// Nutrient measurements for our berries.
    ///
    /// From https://ndb.nal.usda.gov/ndb/ Warning: Their UI rounds values!
    private static let nutrients: [Food: Nutrients] = [
        .raspberry: Nutrients(water: 0.8575,
                              energy: 0.52,
                              protein: 0.012,
                              lipid: 0.0065,
                              carbohydrate: 0.1194,
                              fiber: 0.065,
                              sugars: 0.0442),
        .strawberry: Nutrients(water: 0.9095,
                               energy: 0.32,
                               protein: 0.0067,
                               lipid: 0.0030,
                               carbohydrate: 0.0768,
                               fiber: 0.02,
                               sugars: 0.0489)
    ]
    
    let observation: PixelObservation
    let physicalWidth: Float
    
    init(observation: PixelObservation, physicalWidth side: Float) {
        self.observation = observation
        self.physicalWidth = side
    }
    
    /// Meters squared area that, from our view, is occupied by the food.
    func area() -> Float {
        let pixelWidth = Float(observation.frame.width)
        let pixelHeight = Float(observation.frame.height)
        let physicalHeight = physicalWidth * (pixelHeight / pixelWidth)
        let percentFilled = Float(observation.pixels) / (pixelWidth * pixelHeight)
        return percentFilled * (physicalWidth * physicalHeight)
    }
    
    /// Mass in grams
    func mass() -> Float? {
        guard let baselineMass = FoodEstimate.averageMass[observation.food],
              let baselineArea = FoodEstimate.averageArea[observation.food] else { return nil }
        let mass = area() * (baselineMass / baselineArea)
        guard !mass.isNaN && !mass.isInfinite else { return nil }
        return mass
    }
    
    /// Rounded count of berries in connected pixel cluster.
    func count() -> Int? {
        guard let baselineMass = FoodEstimate.averageMass[observation.food],
              let mass = self.mass() else { return nil }
        let count = mass / baselineMass
        guard !count.isNaN && !count.isInfinite else { return nil }
        return Int(round(count))
    }
    
    /// Calories (energy) in kcal.
    func calories() -> Float? {
        guard let mass = self.mass(),
              let nutrients = FoodEstimate.nutrients[observation.food] else { return nil }
        return mass * nutrients.energy
    }
}
