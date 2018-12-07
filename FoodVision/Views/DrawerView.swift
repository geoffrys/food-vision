import UIKit

/// Shows any currently found food, including count, mass, and calories.
class DrawerView: UIView {
    @IBOutlet weak var waitingView: UIStackView!
    @IBOutlet weak var nutritionView: UIStackView!
    @IBOutlet weak var totalValues: UILabel!
    @IBOutlet weak var raspberryLabel: UILabel!
    @IBOutlet weak var raspberryValues: UILabel!
    @IBOutlet weak var strawberryLabel: UILabel!
    @IBOutlet weak var strawberryValues: UILabel!
    
    static let nutritionFormat = "%i g      %i cal"
    
    private var foundFood = false

    override func layoutSubviews() {
        super.layoutSubviews()
        
        roundCorners(corners: [.topLeft, .topRight], radius: 14)
        waitingView.alpha = 1
        nutritionView.alpha = 0
    }
    
    // MARK: - Stateful updates
    
    func update(_ estimates: [FoodEstimate]) {
        let groupedFood = Dictionary(grouping: estimates, by: { $0.observation.food })
        let raspberries = groupedFood[.raspberry] ?? []
        let strawberries = groupedFood[.strawberry] ?? []
        
        let raspberryMass = raspberries.reduce(0, { $0 + ($1.mass() ?? 0) })
        let raspberryCalories = raspberries.reduce(0, { $0 + ($1.calories() ?? 0) })
        let raspberryCount = raspberries.reduce(0, { $0 + ($1.count() ?? 0) })
        let strawberryMass = strawberries.reduce(0, { $0 + ($1.mass() ?? 0) })
        let strawberryCalories = strawberries.reduce(0, { $0 + ($1.calories() ?? 0) })
        let strawberryCount = strawberries.reduce(0, { $0 + ($1.count() ?? 0) })
        
        let totalMass = raspberryMass + strawberryMass
        let totalCalories = raspberryCalories + strawberryCalories

        // State changes synchronized by main thread
        DispatchQueue.main.async {
            // Transition to looking state
            if self.foundFood && estimates.count <= 0 {
                self.foundFood = false
                self.waitingView.alpha = 1
                self.nutritionView.alpha = 0
                return
            }
            
            guard estimates.count > 0 else { return }
            
            // Update display if needed
            self.totalValues.text = self.formatted(mass: totalMass,
                                                   calories: totalCalories)
            self.raspberryLabel.text = self.formatted(food: .raspberry,
                                                      count: raspberryCount)
            self.raspberryValues.text = self.formatted(mass: raspberryMass,
                                                       calories: raspberryCalories)
            self.strawberryLabel.text = self.formatted(food: .strawberry,
                                                       count: strawberryCount)
            self.strawberryValues.text = self.formatted(mass: strawberryMass,
                                                        calories: strawberryCalories)
            
            // Transition to found state
            if !self.foundFood {
                self.foundFood = true
                self.waitingView.alpha = 0
                self.nutritionView.alpha = 1
            }
        }
    }
    
    // MARK: - Display string formatting
    
    /// Returns a rounded string suitable for display.
    func formatted(mass: Float, calories: Float) -> String {
        return String(format: DrawerView.nutritionFormat,
                      Int(round(mass)),
                      Int(round(calories)))
    }
    
    /// Returns a rounded string suitable for display.
    ///
    /// - Warning: Manually specifying plural grammer changes isn't scalable,
    /// use Localizable stringsdict or similar
    func formatted(food: Food, count: Int) -> String {
        var name = ""
        switch (food, count) {
        case (.raspberry, ...1): name = "raspberry"
        case (.raspberry, 2...): name = "raspberries"
        case (.strawberry, ...1): name = "strawberry"
        case (.strawberry, 2...): name = "strawberries"
        default: name = ""
        }
        
        return "\(count) \(name)"
    }
}
