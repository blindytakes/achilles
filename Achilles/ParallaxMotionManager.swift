import CoreMotion
import Combine

/// ParallaxMotionManager drives parallax offsets based on device motion (roll & pitch).
///
/// - Publishes `xOffset` and `yOffset` as CGFloat values for SwiftUI views to consume.
/// - Uses CoreMotion's `CMMotionManager` to receive continuous device motion updates.
/// - Target update frequency: 60 Hz (default 1/60 seconds).
///
/// Usage:
/// ```swift
/// @StateObject private var motion = ParallaxMotionManager()
///
/// Text("Hello Parallax")
///   .offset(x: motion.xOffset, y: motion.yOffset)
/// ```
class ParallaxMotionManager: ObservableObject {
    // MARK: - Published Offsets
    /// Horizontal offset derived from device roll (multiplied by sensitivity).
    @Published var xOffset: CGFloat = 0
    /// Vertical offset derived from device pitch (multiplied by sensitivity).
    @Published var yOffset: CGFloat = 0

    // MARK: - Private Properties
    /// CoreMotion manager to access device motion data.
    private let motionManager = CMMotionManager()
    /// Sensitivity multiplier for roll and pitch values.
    private let sensitivity: CGFloat = 10.0

    // MARK: - Initialization
    init() {
        // Set update interval to 60 Hz
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        // Start receiving device motion updates on the main queue
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let attitude = motion?.attitude else { return }
            // Map roll and pitch to x/y offsets with sensitivity
            self.xOffset = CGFloat(attitude.roll) * self.sensitivity
            self.yOffset = CGFloat(attitude.pitch) * self.sensitivity
        }
    }

    deinit {
        // Stop updates when this manager is deallocated
        motionManager.stopDeviceMotionUpdates()
    }
}
