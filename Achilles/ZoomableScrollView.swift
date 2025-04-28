import SwiftUI
import UIKit

// MARK: - Constants (Defined at File Level)
// Moved outside the generic struct context and made fileprivate
fileprivate struct Constants {
    // Zooming
    static let maximumZoomScale: CGFloat = 8.0
    static let minimumZoomScale: CGFloat = 1.0
    static let zoomSlightlyAboveMinimum: CGFloat = 1.01 // Threshold to consider zoomed
    static let doubleTapZoomScale: CGFloat = 3.0
    static let zoomRectCalculationFactor: CGFloat = 2.0

    // Pan Gesture (Swipe Down Dismiss)
    static let panMinVerticalDistanceStartFeedback: CGFloat = 50.0
    static let panHorizontalDominanceFactor: CGFloat = 0.8 // horizontal < vertical * factor
    static let panDismissProgressMax: CGFloat = 1.0
    static let panDismissProgressDistanceDivider: CGFloat = 300.0
    static let panFeedbackAnimationDuration: Double = 0.1
    static let panFeedbackMinAlpha: CGFloat = 0.7
    static let panFeedbackAlphaFactor: CGFloat = 0.3
    static let panFeedbackScaleFactor: CGFloat = 0.05
    static let panResetAnimationDuration: Double = 0.3
    static let panMinVerticalDistanceForDismiss: CGFloat = 100.0
    static let panDismissHorizontalDominanceFactor: CGFloat = 0.5

    // Taps
    static let doubleTapRequiredTaps: Int = 2

    // Centering
    static let centerContentDivisionFactor: CGFloat = 2.0
    static let minContentInset: CGFloat = 0.0
}


// MARK: - Zoomable ScrollView Representable
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    // MARK: Properties
    let content: Content
    @Binding var showInfoPanel: Bool
    @Binding var controlsHidden: Bool
    @Binding var zoomScale: CGFloat
    let dismissAction: () -> Void

    // MARK: Init
    init(
        showInfoPanel: Binding<Bool>,
        controlsHidden: Binding<Bool>,
        zoomScale: Binding<CGFloat>,
        dismissAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._showInfoPanel = showInfoPanel
        self._controlsHidden = controlsHidden
        self._zoomScale = zoomScale
        self.dismissAction = dismissAction
        self.content = content()
    }

    // MARK: UIViewRepresentable Methods
    func makeCoordinator() -> Coordinator {
        Coordinator(
            hostingController: UIHostingController(rootView: content),
            showInfoPanel: $showInfoPanel,
            controlsHidden: $controlsHidden,
            zoomScale: $zoomScale,
            dismissAction: dismissAction
        )
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        // Access constants directly via the struct name now
        scrollView.maximumZoomScale = Constants.maximumZoomScale
        scrollView.minimumZoomScale = Constants.minimumZoomScale
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true

        // Layer enhancements
        scrollView.layer.allowsEdgeAntialiasing = true
        scrollView.layer.minificationFilter = .trilinear
        scrollView.layer.magnificationFilter = .trilinear
        scrollView.layer.shouldRasterize = true
        scrollView.layer.rasterizationScale = UIScreen.main.scale
        scrollView.layer.drawsAsynchronously = true

        // Setup hosting controller view
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        hostedView.isUserInteractionEnabled = true

        // Layer enhancements for hosted view
        hostedView.layer.allowsEdgeAntialiasing = true
        hostedView.layer.minificationFilter = .trilinear
        hostedView.layer.magnificationFilter = .trilinear
        hostedView.layer.shouldRasterize = true
        hostedView.layer.rasterizationScale = UIScreen.main.scale
        hostedView.layer.contentsScale = UIScreen.main.scale
        hostedView.layer.drawsAsynchronously = true

        scrollView.addSubview(hostedView)

        // Constraints
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        // Setup gestures via coordinator
        context.coordinator.setupGestureRecognizers(for: scrollView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // Update the root view if content changes
        context.coordinator.hostingController.rootView = content
        context.coordinator.hostingController.view.setNeedsLayout()
    }


    // MARK: - Coordinator Class
    // Constants struct is NO LONGER nested here
    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {

        // MARK: Properties
        var hostingController: UIHostingController<Content>
        @Binding var showInfoPanel: Bool
        @Binding var controlsHidden: Bool
        @Binding var zoomScale: CGFloat
        let dismissAction: () -> Void

        private var isZoomed: Bool = false
        private var startTouchPoint: CGPoint = .zero

        // MARK: Init
        init(
            hostingController: UIHostingController<Content>,
            showInfoPanel: Binding<Bool>,
            controlsHidden: Binding<Bool>,
            zoomScale: Binding<CGFloat>,
            dismissAction: @escaping () -> Void
        ) {
            self.hostingController = hostingController
            self._showInfoPanel = showInfoPanel
            self._controlsHidden = controlsHidden
            self._zoomScale = zoomScale
            self.dismissAction = dismissAction
        }

        // MARK: Gesture Setup
        func setupGestureRecognizers(for scrollView: UIScrollView) {
            // Double tap for zoom
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = Constants.doubleTapRequiredTaps // Use constant
            scrollView.addGestureRecognizer(doubleTap)

            // Single tap for controls
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            singleTap.require(toFail: doubleTap)
            scrollView.addGestureRecognizer(singleTap)

            // Pan gesture for swipe down to dismiss
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            panGesture.delegate = self
            scrollView.addGestureRecognizer(panGesture)
        }

        // MARK: UIScrollViewDelegate Methods
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
            zoomScale = scrollView.zoomScale
            // Access constants directly
            isZoomed = scrollView.zoomScale > Constants.zoomSlightlyAboveMinimum
        }

        // MARK: Helper Methods
        func centerContent(_ scrollView: UIScrollView) {
            guard let hostedView = hostingController.view else { return }
            let scrollBoundsSize = scrollView.bounds.size
            let hostedContentSize = hostedView.frame.size

            // Access constants directly
            let verticalInset = max(Constants.minContentInset, (scrollBoundsSize.height - hostedContentSize.height) / Constants.centerContentDivisionFactor)
            let horizontalInset = max(Constants.minContentInset, (scrollBoundsSize.width - hostedContentSize.width) / Constants.centerContentDivisionFactor)

            scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
        }

        // MARK: Gesture Handlers
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
             guard let scrollView = gesture.view as? UIScrollView else { return }
             // Access constants directly
             let targetScale = scrollView.zoomScale > Constants.zoomSlightlyAboveMinimum ? Constants.minimumZoomScale : Constants.doubleTapZoomScale // Use Constants.minimumZoomScale
             let zoomPoint = gesture.location(in: scrollView)

             let zoomRectWidth = scrollView.bounds.size.width / targetScale
             let zoomRectHeight = scrollView.bounds.size.height / targetScale
             // Access constants directly
             let zoomRectX = zoomPoint.x - zoomRectWidth / Constants.zoomRectCalculationFactor
             let zoomRectY = zoomPoint.y - zoomRectHeight / Constants.zoomRectCalculationFactor

             let zoomRect = CGRect(x: zoomRectX, y: zoomRectY, width: zoomRectWidth, height: zoomRectHeight)
             scrollView.zoom(to: zoomRect, animated: true)
         }

         @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
             withAnimation { controlsHidden.toggle() }
             if !controlsHidden && showInfoPanel {
                  withAnimation { showInfoPanel = false }
              }
         }

         @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
             guard let scrollView = gesture.view as? UIScrollView else { return }

             // Access constants directly
             if scrollView.zoomScale > Constants.zoomSlightlyAboveMinimum || showInfoPanel {
                 if gesture.state == .changed || gesture.state == .began {
                     UIView.animate(withDuration: Constants.panResetAnimationDuration) { // Use constant
                          scrollView.alpha = 1.0
                          scrollView.transform = .identity
                      }
                 }
                 return
             }

             switch gesture.state {
             case .began:
                 startTouchPoint = gesture.location(in: scrollView)

             case .changed:
                 let currentPoint = gesture.location(in: scrollView)
                 let verticalDistance = currentPoint.y - startTouchPoint.y
                 let horizontalDistance = currentPoint.x - startTouchPoint.x

                 // Access constants directly
                 if verticalDistance > Constants.panMinVerticalDistanceStartFeedback &&
                    abs(horizontalDistance) < abs(verticalDistance) * Constants.panHorizontalDominanceFactor {

                     // Access constants directly
                     let dismissProgress = min(Constants.panDismissProgressMax, verticalDistance / Constants.panDismissProgressDistanceDivider)

                     UIView.animate(withDuration: Constants.panFeedbackAnimationDuration) { // Use constant
                         scrollView.alpha = max(Constants.panFeedbackMinAlpha, 1.0 - dismissProgress * Constants.panFeedbackAlphaFactor) // Use constants
                         let scaleValue = 1.0 - dismissProgress * Constants.panFeedbackScaleFactor // Use constant
                         scrollView.transform = CGAffineTransform(scaleX: scaleValue, y: scaleValue)
                     }
                 } else {
                      UIView.animate(withDuration: Constants.panFeedbackAnimationDuration) { // Use constant
                          scrollView.alpha = 1.0
                          scrollView.transform = .identity
                      }
                  }

             case .ended, .cancelled:
                 UIView.animate(withDuration: Constants.panResetAnimationDuration) { // Use constant
                     scrollView.alpha = 1.0
                     scrollView.transform = .identity
                 }

                 let currentPoint = gesture.location(in: scrollView)
                 let verticalDistance = currentPoint.y - startTouchPoint.y
                 let horizontalDistance = currentPoint.x - startTouchPoint.x

                 // Access constants directly
                 if verticalDistance > Constants.panMinVerticalDistanceForDismiss &&
                    abs(horizontalDistance) < abs(verticalDistance) * Constants.panDismissHorizontalDominanceFactor {
                     dismissAction()
                 }

             default:
                 UIView.animate(withDuration: Constants.panResetAnimationDuration) { // Use constant
                      scrollView.alpha = 1.0
                      scrollView.transform = .identity
                  }
                 break
             }
         }

         // MARK: UIGestureRecognizerDelegate
         func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
             return true
         }
    }
}
