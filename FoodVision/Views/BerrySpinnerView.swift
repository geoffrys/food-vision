import UIKit

/// Manages a growing and shrinking animation of three berries.
class BerrySpinner: UIStackView {
    @IBOutlet weak var cherry: UIImageView!
    @IBOutlet weak var raspberry: UIImageView!
    @IBOutlet weak var strawberry: UIImageView!
    private var spinning = false
    
    func startSpinner() {
        if !spinning {
            spin()
            spinning = true
        }
    }
    
    private func spin() {
        let cherryGrow = growAnimator(view: cherry)
        let cherryShrink = shrinkAnimator(view: cherry)
        let raspberryGrow = growAnimator(view: raspberry)
        let raspberryShrink = shrinkAnimator(view: raspberry)
        let strawberryGrow = growAnimator(view: strawberry)
        let strawberryShrink = shrinkAnimator(view: strawberry)
        
        // Shrink previous and grow next at the same time
        cherryGrow.addCompletion { _ in
            cherryShrink.startAnimation()
            raspberryGrow.startAnimation()
        }
        raspberryGrow.addCompletion { _ in
            raspberryShrink.startAnimation()
            strawberryGrow.startAnimation()
        }
        strawberryGrow.addCompletion { _ in
            strawberryShrink.startAnimation()
            self.spin()
        }
        
        cherryGrow.startAnimation()
    }
    
    private func shrinkAnimator(view: UIView) -> UIViewPropertyAnimator {
        let animator = UIViewPropertyAnimator(duration: 0.400, curve: .easeOut)
        animator.addAnimations {
            view.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            view.alpha = 0.3
        }
        return animator
    }
    
    private func growAnimator(view: UIView) -> UIViewPropertyAnimator {
        let animator = UIViewPropertyAnimator(duration: 0.600, curve: .easeInOut)
        animator.addAnimations {
            view.transform = CGAffineTransform(scaleX: 1, y: 1)
            view.alpha = 1
        }
        return animator
    }
}
