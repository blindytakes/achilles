import SwiftUI
import UIKit

// MARK: - Zoomable ScrollView (Clean Start)
// Wraps UIScrollView for zooming, panning, and handling gestures.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: Content // The SwiftUI view to display (e.g., Image)
    @Binding var showInfoPanel: Bool // Controls parent's info panel
    @Binding var controlsHidden: Bool // Controls parent's UI overlays
    let dismissAction: () -> Void // Action to dismiss the parent view

    // Initializer
    init(
        showInfoPanel: Binding<Bool>,
        controlsHidden: Binding<Bool>,
        dismissAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self._showInfoPanel = showInfoPanel
        self._controlsHidden = controlsHidden
        self.dismissAction = dismissAction
        self.content = content()
        print("✅ ZoomableScrollView: Initialized")
    }

    // Creates the UIScrollView
    func makeUIView(context: Context) -> UIScrollView {
        print("✅ ZoomableScrollView: makeUIView")
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 4.0 // Max zoom
        scrollView.minimumZoomScale = 1.0 // Min zoom (fit)
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear // Transparent background
        scrollView.isScrollEnabled = true // Enable panning when zoomed

        // Setup hosting controller for SwiftUI content
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        hostedView.isUserInteractionEnabled = true
        scrollView.addSubview(hostedView)

        // Auto Layout constraints
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
        print("✅ ZoomableScrollView: Auto Layout constraints activated.")

        // Setup gestures via Coordinator
        context.coordinator.setupGestureRecognizers(for: scrollView)

        print("✅ ZoomableScrollView: makeUIView - Delegate set? \(scrollView.delegate != nil), minZoom=\(scrollView.minimumZoomScale), maxZoom=\(scrollView.maximumZoomScale)")
        return scrollView
    }

    // Creates the Coordinator instance
    func makeCoordinator() -> Coordinator {
        print("✅ ZoomableScrollView: makeCoordinator")
        return Coordinator(
            hostingController: UIHostingController(rootView: content),
            showInfoPanel: $showInfoPanel,
            controlsHidden: $controlsHidden,
            dismissAction: dismissAction
        )
    }

    // Updates the view
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        print("✅ ZoomableScrollView: updateUIView")
        // Update content view
        context.coordinator.hostingController.rootView = content
        // *** NO ZOOM RESET HERE ***
        context.coordinator.hostingController.view.setNeedsLayout()
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var hostingController: UIHostingController<Content>
        @Binding var showInfoPanel: Bool
        @Binding var controlsHidden: Bool
        let dismissAction: () -> Void

        // Pan gesture state
        private var isTrackingPanForSwipeAction = false
        private var dragInitialPoint: CGPoint = .zero

        init(
            hostingController: UIHostingController<Content>,
            showInfoPanel: Binding<Bool>,
            controlsHidden: Binding<Bool>,
            dismissAction: @escaping () -> Void
        ) {
            print("✅ Coordinator: Initialized. HostingController view valid? \(hostingController.view != nil)")
            self.hostingController = hostingController
            self._showInfoPanel = showInfoPanel
            self._controlsHidden = controlsHidden
            self.dismissAction = dismissAction
        }

        // Add all gestures
        func setupGestureRecognizers(for scrollView: UIScrollView) {
            print("✅ Coordinator: Setting up gesture recognizers")
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTap)

            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            singleTap.numberOfTapsRequired = 1
            singleTap.require(toFail: doubleTap) // Crucial dependency
            scrollView.addGestureRecognizer(singleTap)

            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            panGesture.delegate = self // For simultaneous recognition
            scrollView.addGestureRecognizer(panGesture)
            print("✅ Coordinator: Gestures added (Single Tap, Double Tap, Pan)")
        }

        // --- UIScrollViewDelegate ---
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            print("✅ Coordinator: viewForZooming called. Returning hostedView: \(hostingController.view != nil)")
            return hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
             print("✅ Coordinator: scrollViewDidZoom - Current Scale: \(scrollView.zoomScale)")
             centerContent(scrollView)
        }

        // Keep content centered
        func centerContent(_ scrollView: UIScrollView) {
            guard let hostedView = hostingController.view else { return }
            let scrollBoundsSize = scrollView.bounds.size
            let hostedViewFrameSize = hostedView.frame.size
            let verticalInset = max(0, (scrollBoundsSize.height - hostedViewFrameSize.height) / 2.0)
            let horizontalInset = max(0, (scrollBoundsSize.width - hostedViewFrameSize.width) / 2.0)
            if scrollView.contentInset.top != verticalInset || scrollView.contentInset.left != horizontalInset {
                scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
            }
        }

        // --- Gesture Actions ---
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            print("✅ Coordinator: handleDoubleTap")
            let currentScale = scrollView.zoomScale
            let minScale = scrollView.minimumZoomScale
            let maxScale = scrollView.maximumZoomScale
            let targetScale = (currentScale > minScale * 1.01) ? minScale : min(maxScale, 2.5)

            if targetScale == minScale {
                print("--> Zooming Out to scale \(minScale)")
                scrollView.setZoomScale(minScale, animated: true)
            } else {
                print("--> Zooming In to scale \(targetScale)")
                let centerPoint = gesture.location(in: gesture.view)
                let zoomRect = zoomRectForScale(scale: targetScale, center: centerPoint, in: scrollView)
                if !zoomRect.isEmpty && !zoomRect.isInfinite && !zoomRect.width.isNaN && !zoomRect.height.isNaN {
                    scrollView.zoom(to: zoomRect, animated: true)
                } else {
                    print("--> Invalid zoom rect, zooming center instead")
                    scrollView.setZoomScale(targetScale, animated: true)
                }
            }
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
             print("✅ Coordinator: handleSingleTap")
             withAnimation(.easeInOut(duration: 0.2)) { controlsHidden.toggle() }
             if !controlsHidden && showInfoPanel {
                  print("--> Hiding info panel because controls revealed by tap")
                  withAnimation(.easeInOut(duration: 0.2)) { showInfoPanel = false }
             }
        }

        @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
             guard let scrollView = gesture.view as? UIScrollView else { return }
             switch gesture.state {
             case .began:
                  if scrollView.zoomScale <= scrollView.minimumZoomScale * 1.01 {
                       isTrackingPanForSwipeAction = true
                       dragInitialPoint = gesture.location(in: scrollView.superview)
                       print("✅ Coordinator: Pan gesture began potentially for swipe action (Zoom: \(scrollView.zoomScale))")
                  } else {
                       isTrackingPanForSwipeAction = false
                       print("✅ Coordinator: Pan gesture began while zoomed - ignoring.")
                  }
             case .changed:
                  if !isTrackingPanForSwipeAction { return }
             case .ended:
                  if !isTrackingPanForSwipeAction { return }
                  let endPoint = gesture.location(in: scrollView.superview)
                  let translation = CGPoint(x: endPoint.x - dragInitialPoint.x, y: endPoint.y - dragInitialPoint.y)
                  let velocity = gesture.velocity(in: scrollView.superview)
                  print("✅ Coordinator: Pan ended. Translation: \(translation), Velocity: \(velocity)")

                  // Check SWIPE DOWN (Dismiss)
                  let dismissSwipeDistance: CGFloat = 80
                  let dismissSwipeVelocity: CGFloat = 500
                  if translation.y > dismissSwipeDistance || velocity.y > dismissSwipeVelocity {
                       print("--> Dismiss action triggered via swipe down")
                       dismissAction()
                       isTrackingPanForSwipeAction = false
                       return
                  }
                  // Check SWIPE UP (Info Panel)
                  let infoSwipeDistance: CGFloat = -50
                  let infoSwipeVelocity: CGFloat = -400
                  if !showInfoPanel && (translation.y < infoSwipeDistance || velocity.y < infoSwipeVelocity) {
                       print("--> Showing info panel via swipe up")
                       withAnimation(.easeInOut(duration: 0.2)) { showInfoPanel = true }
                       if !controlsHidden { withAnimation(.easeInOut(duration: 0.2)) { controlsHidden = true } }
                  }
                  isTrackingPanForSwipeAction = false
             case .cancelled, .failed:
                  if isTrackingPanForSwipeAction { print("✅ Coordinator: Pan gesture cancelled/failed") }
                  isTrackingPanForSwipeAction = false
             default: break
             }
        }

        // --- UIGestureRecognizerDelegate ---
        func gestureRecognizer(
             _ gestureRecognizer: UIGestureRecognizer,
             shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
             // Allow our pan gesture to work alongside the scroll view's internal pan
             if gestureRecognizer is UIPanGestureRecognizer { return true }
             return false
        }

        // --- Zoom Rect Helper ---
        private func zoomRectForScale(scale: CGFloat, center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            guard let zoomView = viewForZooming(in: scrollView) else { return .zero }
            var zoomRect = CGRect.zero
            zoomRect.size.width = zoomView.bounds.size.width / scale
            zoomRect.size.height = zoomView.bounds.size.height / scale
            let centerInZoomView = zoomView.convert(center, from: scrollView)
            zoomRect.origin.x = centerInZoomView.x - (zoomRect.size.width / 2.0)
            zoomRect.origin.y = centerInZoomView.y - (zoomRect.size.height / 2.0)
            print("Calculated zoomRect: \(zoomRect) for scale \(scale) at center \(center)")
            if zoomRect.isInfinite || zoomRect.isNull || zoomRect.width.isNaN || zoomRect.height.isNaN || zoomRect.width <= 0 || zoomRect.height <= 0 {
                 print("⚠️ zoomRectForScale: Calculated invalid rect.")
                 return .zero
            }
            return zoomRect
        }
    }
}
