import UIKit
import SceneKit
import ARKit
import Vision

class ViewController: UIViewController, UIGestureRecognizerDelegate, ARSessionDelegate {
    @IBOutlet weak var sceneView: ARSKView!
    @IBOutlet weak var drawerView: DrawerView!
    @IBOutlet weak var drawerHeight: NSLayoutConstraint!
    @IBOutlet weak var berrySpinner: BerrySpinner!
    @IBOutlet weak var resetButton: UIButton!
    
    private var resetTimer: Timer?
    private var guidance: Guidance?
    private var visionRegion: VisionRegion?
    private var imageOverlay: SKSpriteNode?
    private var markers: Markers?
    
    private var segmentationRequest: VNCoreMLRequest?
    private let visionQueue = DispatchQueue(label: "com.demo.FoodVision.serialVisionQueue")
    private var anchorMap = [UUID: Marker]()
    private var snapshot: ARFrame?
    private var sceneFrame: CGRect?
    private var deviceOrientation: UIDeviceOrientation?
    private var statusOrientation: UIInterfaceOrientation?
    
    override var preferredStatusBarStyle: UIStatusBarStyle {
        get {
            return .lightContent
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        get {
            return .portrait
        }
    }
    
    @IBAction func didPressReset(_ sender: UIButton) {
        restartSession()
    }
    
    // MARK: - View controller lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Speed up first image segmentation by loading the model as soon as we can
        //
        // Initializing a model and getting to a normal AR tracking state appears
        // to block on the same base resource. I haven't looked into this much.
        // This delays AR initialization for ~3 seconds on an iPhone XS.
        //
        // Loading it here will /look/ best in a demo gif but feel pretty slow.
        visionQueue.async {
            self.segmentationRequest = self.makeSegmentationRequest()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        resetButton.layer.cornerRadius = 4
        
        guard ARWorldTrackingConfiguration.isSupported else { fatalError("ARKit is not available.") }
        restartSession()
        
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        berrySpinner.startSpinner()
        setupSceneView()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        sceneView.session.pause()
    }
    
    override func viewDidLayoutSubviews() {
        self.sceneFrame = sceneView.frame
        self.deviceOrientation = UIDevice.current.orientation
        self.statusOrientation = UIApplication.shared.statusBarOrientation
    }
    
    private func setupSceneView() {
        let viewFrame = sceneView.frame
        let sceneFrame = viewFrame.converted(toScene: sceneView)
        let overlayScene = SKScene(size: viewFrame.size)
        let viewSquare = visionSquare(fromView: viewFrame)
        let sceneSquare = viewSquare.converted(toScene: sceneView)
        
        // Guides to show where vision square is
        let visionRegion = VisionRegion(visionSquare: sceneSquare)
        overlayScene.addChild(visionRegion)
        self.visionRegion = visionRegion
        
        // Badge to guide user actions
        let guidance = Guidance(visionSquare: sceneSquare, viewSize: viewFrame.size)
        overlayScene.addChild(guidance)
        self.guidance = guidance
        
        // Image overlay showing live labels
        let imageOverlay = SKSpriteNode(color: UIColor.clear, size: sceneSquare.size)
        imageOverlay.anchorPoint = CGPoint.zero
        imageOverlay.position = sceneSquare.origin
        imageOverlay.size = sceneSquare.size
        imageOverlay.zPosition = 100
        overlayScene.addChild(imageOverlay)
        self.imageOverlay = imageOverlay
        
        // Marker pins for each recognized cluster
        let markers = Markers(frame: sceneFrame)
        markers.position = sceneFrame.origin
        markers.zPosition = 200
        overlayScene.addChild(markers)
        self.markers = markers
        
        sceneView.presentScene(overlayScene)
        sceneView.session.delegate = self
    }
    
    // MARK: - ARSessionDelegate
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        updateScene(with: frame)
        segmentIfNeeded(frame)
    }
    
    // MARK: - Vision segmentation
    
    /// Segment current camera frame when not already processing one.
    private func segmentIfNeeded(_ frame: ARFrame) {
        // Do not enqueue other buffers while another vision task is still running.
        // The camera stream has only a finite amount of buffers available;
        // holding too many buffers for analysis would starve the camera.
        guard snapshot == nil, case .normal = frame.camera.trackingState else {
            return
        }
        
        // Retain a snapshot for vision processing and drift correction
        self.snapshot = frame
        
        // The model is more predictable at distances it was trained on.
        if self.visionUnstable() {
            DispatchQueue.main.async {
                self.imageOverlay?.alpha = 0
            }
            self.snapshot = nil
            return
        }
        
        segmentCurrentFrame()
    }
    
    /// Runs FoodModel on the frame stored in the snapshot.
    ///
    /// - Warning: Hardcoded crop assuming an iPhone X/XS, other devices may result in
    /// image resolutions not suitable for the model.
    private func segmentCurrentFrame() {
        guard let frame = snapshot,
              let sceneFrame = self.sceneFrame,
              let request = self.segmentationRequest else {
                self.snapshot = nil
                return
        }
        let image = CIImage(cvPixelBuffer: frame.capturedImage)
        
        // The crop is defined in view space and transformed to frame space
        let viewToFrame = frame.displayTransform(for: orientations().status,
                                                 viewportSize: sceneFrame.size).inverted()
        let viewCrop = visionSquare(fromView: sceneFrame)
        let normViewCrop = VNNormalizedRectForImageRect(viewCrop,
                                                        Int(sceneFrame.width),
                                                        Int(sceneFrame.height))
        let normFrameCrop = normViewCrop.applying(viewToFrame)
        let frameCrop = VNImageRectForNormalizedRect(normFrameCrop,
                                                     Int(image.extent.width),
                                                     Int(image.extent.height))
        let cropped = image.croppedAlign(to: frameCrop)
        
        // We orient the image relative to the device's orientation.
        // This isn't strictly necessary for this food subset as the model was
        // evenly trained on all possible orientations.
        let orientation = CGImagePropertyOrientation(orientations().device)
        let requestHandler = VNImageRequestHandler(ciImage: cropped, orientation: orientation)
        visionQueue.async {
            do {
                // Release the frame when done, allowing the next frame to be processed.
                defer { self.snapshot = nil }
                try requestHandler.perform([request])
            } catch {
                print("Error: Vision request failed with error \"\(error)\"")
            }
        }
    }
    
    private func makeSegmentationRequest() -> VNCoreMLRequest {
        do {
            // Instantiate the model from its generated Swift class.
            let model = try VNCoreMLModel(for: FoodModel().model)
            
            let request = VNCoreMLRequest(model: model, completionHandler: { [weak self] request, error in
                guard let labels = self?.labeledResults(from: request, error: error) else { return }
                self?.update(with: labels)
            })
            request.imageCropAndScaleOption = .scaleFit
            return request
        } catch {
            fatalError("Failed to load Vision ML model: \(error)")
        }
    }
    
    /// Extracts the resulting MLMultiArray and processes it with Labels struct.
    private func labeledResults(from request: VNRequest, error: Error?) -> Labels? {
        guard let results = request.results as? [VNCoreMLFeatureValueObservation],
            let multiResult = results.first?.featureValue.multiArrayValue else {
                print("Unable to segment image.\n\(error!.localizedDescription)")
                return nil
        }
        
        return Labels(multiResult)
    }
    
    // MARK: - Display vision segmentation results
    
    /// Updates drawer and marker positions.
    private func updateScene(with frame: ARFrame) {
        let estimates = anchorMap.map { $1.foodEstimate }
        drawerView.update(estimates)
        
        guard let sceneFrame = self.sceneFrame else { return }
        for marker in (markers?.children as? [Marker]) ?? [] {
            marker.update(with: frame, viewFrame: sceneFrame)
        }
    }
    
    /// Updates image overlay and markers in scene.
    private func update(with labels: Labels) {
        if let image = labels.overlay?.cgImage {
            DispatchQueue.main.async {
                let texture = SKTexture(cgImage: image)
                self.imageOverlay?.run(SKAction.setTexture(texture))
                self.imageOverlay?.alpha = 1
            }
        }
        // Label fruit switches to the main thread for SpriteKit modification
        // after further processing.
        labelFruit(labels)
    }
    
    /// The square subset of the view we perform vision processing to.
    private func visionSquare(fromView rect: CGRect) -> CGRect {
        let width = rect.width
        let height = rect.height
        return CGRect(x: max(0, (width - height) / 2),
                      y: max(0, (height - width - drawerHeight.constant) / 2),
                      width: min(width, height),
                      height: min(width, height))
    }
    
    private let maxDistance: CGFloat = 0.18
    
    /// Tests if the camera is too far to give our low resolution model enough
    /// detail to not have features scaled away.
    ///
    /// The model was only trained on very close images.
    private func cameraTooFar() -> Bool {
        guard let sceneFrame = self.sceneFrame else {
            guidance?.update(to: .tooFar)
            return true
            
        }
        let visionSquare = self.visionSquare(fromView: sceneFrame)
        let center = CGPoint(x: visionSquare.size.width / 2,
                             y: visionSquare.size.height / 2)

        guard let centerHit = hit(atVision: center,
                                  visionSize: visionSquare.size) else {
            guidance?.update(to: .tooFar)
            return true
        }
        
        if centerHit.distance > maxDistance {
            guidance?.update(to: .tooFar)
            return true
        }
        guidance?.update(to: .close)
        return false
    }
    
    private let maxRotation = (Float.pi / 180 * 15)
    
    /// Tests if the camera has moved a lot since we last ran the vision model.
    ///
    /// The model + processing is slow and our display code doesn't correct for
    /// shifts in view.
    private func visionUnstable() -> Bool {
        guard let frame = snapshot,
              let currentFrame = sceneView.session.currentFrame else { return false }
        
        // Has the camera moved too far since the camera used for vision?
        let previousView = frame.camera.transform.position()
        let currentView = currentFrame.camera.transform.position()
        let cameraShift = previousView.distance(to: currentView)
        
        // Has the camera rotated too much?
        let previousEuler = frame.camera.eulerAngles
        let currentEuler = currentFrame.camera.eulerAngles
        let cameraRotation = previousEuler.distance(to: currentEuler)
        
        // Additionally is the camera too far away from the objects?
        return cameraTooFar() || cameraShift > 0.015 || cameraRotation > maxRotation
    }
    
    private let maxProximity: Float = 0.03
    
    /// Post process the labels to find connected components, then display them
    /// in the scene with markers.
    ///
    /// - Warning: Existing marker positions are not gracefully tracked and updated
    /// over time, instead nearby anchors are replaced.
    ///
    /// - Warning: Should use instance segmentation in the model, making up for
    /// deficiencies in the model here is very slow.
    private func labelFruit(_ labels: Labels) {
        var pixelObservations = [PixelObservation]()
        pixelObservations.append(contentsOf: labels.connectedComponents(of: .raspberry))
        pixelObservations.append(contentsOf: labels.connectedComponents(of: .strawberry))
        
        var foodEstimates = [(centerHit: ARHitTestResult, foodEstimate: FoodEstimate)]()
        for pixelObservation in pixelObservations {
            let center = CGPoint(x: pixelObservation.frame.midX,
                                 y: pixelObservation.frame.midY)
            let left = CGPoint(x: pixelObservation.frame.minX,
                               y: pixelObservation.frame.midY)
            let right = CGPoint(x: pixelObservation.frame.maxX,
                                y: pixelObservation.frame.midY)
            let labelsSize = CGSize(width: labels.width, height: labels.height)
            guard let centerHit = self.hit(atVision: center, visionSize: labelsSize),
                let leftHit = self.hit(atVision: left, visionSize: labelsSize),
                let rightHit = self.hit(atVision: right, visionSize: labelsSize) else { return }
            
            // Make sure there's ~1 berry
            let leftPosition = leftHit.worldTransform.position()
            let rightPosition = rightHit.worldTransform.position()
            let lengthAcross = leftPosition.distance(to: rightPosition)
            let estimatedFood = FoodEstimate(observation: pixelObservation,
                                             physicalWidth: lengthAcross)
            if let count = estimatedFood.count(), count >= 1 {
                foodEstimates.append((centerHit: centerHit, foodEstimate: estimatedFood))
            }
        }

        DispatchQueue.main.async {
            for (centerHit: centerHit, foodEstimate: foodEstimate) in foodEstimates {
                // Remove all nearby fruit anchors
                let centerPosition = centerHit.worldTransform.position()
                for (_, marker) in self.anchorMap {
                    let anchor = marker.anchor
                    let anchorPosition = anchor.transform.position()
                    let distance = anchorPosition.distance(to: centerPosition)
                    if distance < self.maxProximity {
                        self.markers?.removeChildren(in: [marker])
                        self.anchorMap.removeValue(forKey: anchor.identifier)
                        self.sceneView.session.remove(anchor: anchor)
                    }
                }

                let anchor = ARAnchor(transform: centerHit.worldTransform)
                let marker = Marker(for: foodEstimate, anchor: anchor)
                self.markers?.addChild(marker)
                self.anchorMap[anchor.identifier] = marker
                self.sceneView.session.add(anchor: anchor)
            }
        }
    }
    
    /// Returns first hit test at a point in the vision square.
    ///
    /// - Parameter visionPoint: Point in vision square subset to hit test
    /// - Parameter visionSize: Size of the vision square subset
    private func hit(atVision visionPoint: CGPoint, visionSize: CGSize) -> ARHitTestResult? {
        guard let frame = snapshot,
              let sceneFrame = self.sceneFrame else { return nil }
        
        let viewWidth = sceneFrame.width
        let viewHeight = sceneFrame.height
        
        // Vision space is a centered subset of frame space
        let boxPercentX = visionPoint.x / visionSize.width
        let boxPercentY = visionPoint.y / visionSize.height
        let viewBoxX = boxPercentX * min(viewWidth, viewHeight)
        let viewBoxY = boxPercentY * min(viewWidth, viewHeight)
        let viewTopMargin = max(0, (viewHeight - viewWidth - drawerHeight.constant) / 2)
        let viewSideMargin = max(0, (viewWidth - viewHeight) / 2)
        let viewPoint = CGPoint(x: viewSideMargin + viewBoxX, y: viewTopMargin + viewBoxY)
        let normViewPoint = CGPoint(x: viewPoint.x / viewWidth, y: viewPoint.y / viewHeight)
        
        // Account for differing extents of view and frame
        let orientations = self.orientations()
        var orientation = orientations.status
        if orientations.device == .portraitUpsideDown {
            orientation = .portraitUpsideDown
        }
        let viewToFrame = frame.displayTransform(for: orientation, viewportSize: sceneFrame.size).inverted()
        let framePoint = normViewPoint.applying(viewToFrame)
        
        // Test hits in the same frame objects were detected in
        let hits = frame.hitTest(framePoint, types: [.existingPlaneUsingGeometry,
                                                     .estimatedHorizontalPlane])
        return hits.first
    }
    
    /// Unify UI orientation and device orientation.
    private func orientations() -> (device: UIDeviceOrientation, status: UIInterfaceOrientation) {
        guard var device = self.deviceOrientation,
            let status = self.statusOrientation else {
                return (device: .unknown, status: .unknown)
        }
        
        if [.unknown, .faceUp, .faceDown].contains(device) {
            device = UIDeviceOrientation(status)
        }
        
        return (device: device, status: status)
    }
    
    // MARK: - AR Session Handling
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        guidance?.update(to: camera.trackingState)
        
        switch camera.trackingState {
        case .normal:
            // If we successfully relocalize, stop reset timer and show content
            DispatchQueue.main.async {
                self.setOverlaysHidden(false)
                self.resetTimer?.invalidate()
                self.resetTimer = nil
            }
        default: ()
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        guard error is ARError else { return }
        
        let errorWithInfo = error as NSError
        let messages = [
            errorWithInfo.localizedDescription,
            errorWithInfo.localizedFailureReason,
            errorWithInfo.localizedRecoverySuggestion
        ]
        
        // Filter out optional error messages.
        let errorMessage = messages.compactMap({ $0 }).joined(separator: "\n")
        DispatchQueue.main.async {
            self.displayErrorMessage(title: "The AR session failed.", message: errorMessage)
        }
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.setOverlaysHidden(true)
            // Limit how long we give relocalization before abandoning
            self.resetTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false, block: { [weak self] _ in
                self?.restartSession()
            })
        }
    }
    
    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        return true
    }
    
    /// MARK: - Resetting
    
    /// Hide SceneKit overlays, excluding vision region and guidance.
    private func setOverlaysHidden(_ shouldHide: Bool) {
        var children = sceneView.scene?.children ?? []
        children = children.filter({ $0 != visionRegion && $0 != guidance })
        
        // Don't show the last image overlay just because we got tracking back
        if !shouldHide {
            children = children.filter({ $0 != imageOverlay })
        }
        
        children.forEach { node in
            if shouldHide {
                // Hide overlay content immediately during relocalization.
                node.alpha = 0
            } else {
                // Fade overlay content in after relocalization succeeds.
                node.run(.fadeIn(withDuration: 0.5))
            }
        }
    }
    
    /// Reset state and relaunches world ARKit tracking.
    private func restartSession() {
        resetTimer?.invalidate()
        resetTimer = nil
        
        guidance?.update(to: .notAvailable)
        guidance?.update(to: .tooFar)
        
        anchorMap.removeAll()
        markers?.removeAllChildren()
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Error handling
    
    /// Present an alert informing about the error that has occurred.
    private func displayErrorMessage(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.restartSession()
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }
}
