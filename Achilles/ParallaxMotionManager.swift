import CoreMotion
import Combine

class ParallaxMotionManager: ObservableObject {
    @Published var xOffset: CGFloat = 0
    @Published var yOffset: CGFloat = 0

    private var motionManager = CMMotionManager()

    init() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { motion, error in
            guard let motion = motion else { return }
            DispatchQueue.main.async {
                self.xOffset = CGFloat(motion.attitude.roll) * 10
                self.yOffset = CGFloat(motion.attitude.pitch) * 10
            }
        }
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }
}

