import SwiftUI
import UIKit

// MARK: - Content Type Enum
enum ZoomableContentType {
    case image
    case livePhoto
}

// MARK: - Constants
fileprivate struct Constants {
    // Zooming
    static let maximumZoomScale: CGFloat = 8.0
    static let minimumZoomScale: CGFloat = 1.0
    static let zoomSlightlyAboveMinimum: CGFloat = 1.01 // Threshold to consider zoomed
    static let doubleTapZoomScale: CGFloat = 3.0
    static let zoomRectCalculationFactor: CGFloat = 2.0

    // Pan Gesture (Swipe Down Dismiss)
    static let panMinVerticalDistanceStartFeedback: CGFloat = 50
    static let panHorizontalDominanceFactor: CGFloat = 0.8 // horizontal < vertical * factor
    static let panDismissProgressMax: CGFloat = 1.0
    static let panDismissProgressDistanceDivider: CGFloat = 300
    static let panFeedbackAnimationDuration: Double = 0.1
    static let panFeedbackMinAlpha: CGFloat = 0.7
    static let panFeedbackAlphaFactor: CGFloat = 0.3
    static let panFeedbackScaleFactor: CGFloat = 0.05
    static let panResetAnimationDuration: Double = 0.3
    static let panMinVerticalDistanceForDismiss: CGFloat = 100
    static let panDismissHorizontalDominanceFactor: CGFloat = 0.5

    // Taps
    static let doubleTapRequiredTaps: Int = 2

    // Centering
    static let centerContentDivisionFactor: CGFloat = 2.0
    static let minContentInset: CGFloat = 0.0
    
    // NEW: Directional tolerance for cleaner gesture separation
    static let directionTolerance: CGFloat = 45.0 // degrees
}


// MARK: - Zoomable ScrollView Representable
struct ZoomableScrollView<Content: View>: UIViewRepresentable {

    // MARK: Properties
    let content: Content
    @Binding var showInfoPanel: Bool
    @Binding var controlsHidden: Bool
    @Binding var zoomScale: CGFloat
    let dismissAction: () -> Void
    let contentType: ZoomableContentType

    // MARK: Init
    init(
        contentType: ZoomableContentType = .image,
        showInfoPanel: Binding<Bool>,
        controlsHidden: Binding<Bool>,
        zoomScale: Binding<CGFloat>,
        dismissAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.contentType = contentType
        self._showInfoPanel = showInfoPanel
        self._controlsHidden = controlsHidden
        self._zoomScale = zoomScale
        self.dismissAction = dismissAction
        self.content = content()
        print("ZoomableScrollView initialized with contentType: \(contentType)")
    }

    // MARK: UIViewRepresentable Methods

    func makeCoordinator() -> Coordinator {
        Coordinator(
            parent: self,
            hostingController: UIHostingController(rootView: content)
        )
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = Constants.maximumZoomScale
        scrollView.minimumZoomScale = Constants.minimumZoomScale
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.layer.allowsEdgeAntialiasing = true
        scrollView.layer.minificationFilter = .trilinear
        scrollView.layer.magnificationFilter = .trilinear
        scrollView.layer.shouldRasterize = true
        scrollView.layer.rasterizationScale = UIScreen.main.scale
        scrollView.layer.drawsAsynchronously = true

        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        hostedView.isUserInteractionEnabled = true
        hostedView.layer.allowsEdgeAntialiasing = true
        hostedView.layer.minificationFilter = .trilinear
        hostedView.layer.magnificationFilter = .trilinear
        hostedView.layer.shouldRasterize = true
        hostedView.layer.rasterizationScale = UIScreen.main.scale
        hostedView.layer.contentsScale = UIScreen.main.scale
        hostedView.layer.drawsAsynchronously = true

        scrollView.addSubview(hostedView)

        NSLayoutConstraint.activate([
             hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
             hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
             hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
             hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
             hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
             hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.setupGestureRecognizers(for: scrollView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        context.coordinator.hostingController.view.setNeedsLayout()
    }


    // MARK: - Coordinator Class
    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {

        // MARK: Properties
        var parent: ZoomableScrollView
        var hostingController: UIHostingController<Content>
        private var isZoomed: Bool = false
        private var startTouchPoint: CGPoint = .zero
        private var initialPanDirection: CGPoint = .zero  // NEW: Track initial pan direction


        // MARK: Init
        init(
            parent: ZoomableScrollView,
            hostingController: UIHostingController<Content>
        ) {
            self.parent = parent
            self.hostingController = hostingController
            print("Coordinator initialized for contentType: \(parent.contentType)")
        }

        func setupGestureRecognizers(for scrollView: UIScrollView) {
            // Double-tap for zoom
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = Constants.doubleTapRequiredTaps
            scrollView.addGestureRecognizer(doubleTap)

            // Single-tap to toggle controls (only for static images)
            if parent.contentType == .image {
                let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
                singleTap.require(toFail: doubleTap)
                scrollView.addGestureRecognizer(singleTap)
            }

            // Pan gesture for dismissing
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            panGesture.delegate = self
            scrollView.addGestureRecognizer(panGesture)
        }


        // MARK: UIScrollViewDelegate Methods
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
            parent.zoomScale = scrollView.zoomScale
            isZoomed = scrollView.zoomScale > Constants.zoomSlightlyAboveMinimum
        }

        // MARK: Helper Methods
        func centerContent(_ scrollView: UIScrollView) {
            guard let hostedView = hostingController.view else { return }
            let scrollBoundsSize = scrollView.bounds.size
            let hostedContentSize = hostedView.frame.size
            let verticalInset = max(Constants.minContentInset, (scrollBoundsSize.height - hostedContentSize.height) / Constants.centerContentDivisionFactor)
            let horizontalInset = max(Constants.minContentInset, (scrollBoundsSize.width - hostedContentSize.width) / Constants.centerContentDivisionFactor)
            let newInsets = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
            if scrollView.contentInset != newInsets {
                scrollView.contentInset = newInsets
            }
        }

        // MARK: Gesture Handlers

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
             guard let scrollView = gesture.view as? UIScrollView else { return }
             let targetScale = isZoomed ? Constants.minimumZoomScale : Constants.doubleTapZoomScale
             let zoomPoint = gesture.location(in: hostingController.view)
             let zoomRectWidth = scrollView.bounds.size.width / targetScale
             let zoomRectHeight = scrollView.bounds.size.height / targetScale
             let zoomRectX = zoomPoint.x - zoomRectWidth / Constants.zoomRectCalculationFactor
             let zoomRectY = zoomPoint.y - zoomRectHeight / Constants.zoomRectCalculationFactor
             let zoomRect = CGRect(x: zoomRectX, y: zoomRectY, width: zoomRectWidth, height: zoomRectHeight)
             scrollView.zoom(to: zoomRect, animated: true)
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
             print("Coordinator: handleSingleTap executed.")
             withAnimation { parent.controlsHidden.toggle() }
             if !parent.controlsHidden && parent.showInfoPanel {
                 withAnimation { parent.showInfoPanel = false }
             }
        }

        @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }

            // Prevent dismiss pan if zoomed OR if info panel is showing
            if isZoomed || parent.showInfoPanel {
                 if gesture.state == .changed || gesture.state == .began {
                     if scrollView.transform != .identity || scrollView.alpha != 1.0 {
                         UIView.animate(withDuration: Constants.panResetAnimationDuration) {
                             scrollView.alpha = 1.0
                             scrollView.transform = .identity
                         }
                     }
                 }
                 if isZoomed { return }
            }

             // Handle dismiss pan only if NOT zoomed AND panel is hidden
             if !isZoomed && !parent.showInfoPanel {
                 switch gesture.state {
                 case .began:
                     startTouchPoint = gesture.location(in: scrollView.superview)
                     // Reset initial direction
                     initialPanDirection = .zero

                 case .changed:
                     let totalTranslation = gesture.translation(in: scrollView.superview)
                     
                     // Capture initial direction if not set
                     if initialPanDirection == .zero {
                         initialPanDirection = totalTranslation
                     }
                     
                     // Check if initial direction is more vertical than horizontal
                     let isInitiallyVertical = abs(initialPanDirection.y) > abs(initialPanDirection.x)
                     
                     // Only proceed with dismiss feedback if initially moving vertically
                     if isInitiallyVertical && totalTranslation.y > 0 {
                          let dismissProgress = min(Constants.panDismissProgressMax, totalTranslation.y / Constants.panDismissProgressDistanceDivider)
                          let scaleValue = 1.0 - dismissProgress * Constants.panFeedbackScaleFactor
                          scrollView.alpha = max(Constants.panFeedbackMinAlpha, 1.0 - dismissProgress * Constants.panFeedbackAlphaFactor)
                          scrollView.transform = CGAffineTransform(translationX: totalTranslation.x, y: totalTranslation.y).scaledBy(x: scaleValue, y: scaleValue)
                     } else {
                           // Reset if pan is not initially vertical
                           if scrollView.transform != .identity || scrollView.alpha != 1.0 {
                                UIView.animate(withDuration: Constants.panFeedbackAnimationDuration) {
                                     scrollView.alpha = 1.0
                                     scrollView.transform = .identity
                                }
                           }
                     }

                 case .ended, .cancelled:
                     let totalTranslation = gesture.translation(in: scrollView.superview)
                     
                     // Check if initial direction was vertical and ended with sufficient vertical movement
                     let isInitiallyVertical = abs(initialPanDirection.y) > abs(initialPanDirection.x)
                     let shouldDismiss = isInitiallyVertical &&
                                         totalTranslation.y > Constants.panMinVerticalDistanceForDismiss &&
                                         abs(totalTranslation.x) < abs(totalTranslation.y) * Constants.panDismissHorizontalDominanceFactor

                     if shouldDismiss && gesture.state == .ended {
                          print("Coordinator: Dismiss action triggered.")
                          parent.dismissAction()
                     } else {
                          // Reset animation if not dismissing
                          UIView.animate(withDuration: Constants.panResetAnimationDuration) {
                              scrollView.alpha = 1.0
                              scrollView.transform = .identity
                          }
                     }
                 default:
                     // Reset in other cases like .failed
                     if scrollView.transform != .identity || scrollView.alpha != 1.0 {
                           UIView.animate(withDuration: Constants.panResetAnimationDuration) {
                               scrollView.alpha = 1.0
                               scrollView.transform = .identity
                           }
                     }
                     break
                 }
             } else if gesture.state == .ended || gesture.state == .cancelled {
                 // Ensure reset if pan ends while zoomed or panel was showing
                  if scrollView.transform != .identity || scrollView.alpha != 1.0 {
                      UIView.animate(withDuration: Constants.panResetAnimationDuration) {
                          scrollView.alpha = 1.0
                          scrollView.transform = .identity
                      }
                  }
             }
        }

        // MARK: UIGestureRecognizerDelegate
        
        // NEW: Add this method to improve gesture recognition
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Special handling for pan gesture
            if let panGesture = gestureRecognizer as? UIPanGestureRecognizer {
                let velocity = panGesture.velocity(in: gestureRecognizer.view)
                
                // Calculate angle of the velocity vector
                let angle = atan2(abs(velocity.y), abs(velocity.x)) * 180.0 / .pi
                
                // If zoomed or info panel is showing, only allow internal scrolling
                if isZoomed || parent.showInfoPanel {
                    return false  // Let UIScrollView handle its own gestures
                }
                
                // Only begin pan gesture if it's more vertical than horizontal
                return angle > 45.0  // More than 45 degrees is considered vertical
            }
            
            return true
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow simultaneous recognition for most cases
            // This ensures horizontal swiping for photo navigation works properly
            return true
        }
    } // End Coordinator
} // End Struct
