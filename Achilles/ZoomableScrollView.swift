import SwiftUI
import UIKit

// MARK: - Zoomable ScrollView
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: Content
    @Binding var showInfoPanel: Bool
    @Binding var controlsHidden: Bool
    @Binding var zoomScale: CGFloat
    let dismissAction: () -> Void

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
        scrollView.maximumZoomScale = 4.0
        scrollView.minimumZoomScale = 1.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        hostedView.isUserInteractionEnabled = true
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

    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var hostingController: UIHostingController<Content>
        @Binding var showInfoPanel: Bool
        @Binding var controlsHidden: Bool
        @Binding var zoomScale: CGFloat
        let dismissAction: () -> Void

        private var isTrackingPanForSwipeAction = false
        private var dragInitialPoint: CGPoint = .zero

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

        func setupGestureRecognizers(for scrollView: UIScrollView) {
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTap)

            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            singleTap.require(toFail: doubleTap)
            scrollView.addGestureRecognizer(singleTap)

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            pan.delegate = self
            scrollView.addGestureRecognizer(pan)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
            zoomScale = scrollView.zoomScale
        }

        func centerContent(_ scrollView: UIScrollView) {
            guard let hostedView = hostingController.view else { return }
            let scrollSize = scrollView.bounds.size
            let contentSize = hostedView.frame.size

            let verticalInset = max(0, (scrollSize.height - contentSize.height) / 2)
            let horizontalInset = max(0, (scrollSize.width - contentSize.width) / 2)

            scrollView.contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let scale = scrollView.zoomScale > 1.01 ? scrollView.minimumZoomScale : 2.5
            let point = gesture.location(in: scrollView)
            let zoomRect = CGRect(
                x: point.x - scrollView.bounds.size.width / (2 * scale),
                y: point.y - scrollView.bounds.size.height / (2 * scale),
                width: scrollView.bounds.size.width / scale,
                height: scrollView.bounds.size.height / scale
            )
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

            // Don't handle gestures if we're zoomed in (let regular scrolling work)
            if scrollView.zoomScale > 1.01 {
                isTrackingPanForSwipeAction = false
                return
            }
            
            // Don't handle pans if the scroll view is scrolling horizontally
            if abs(scrollView.contentOffset.x) > 0.1 {
                isTrackingPanForSwipeAction = false
                return
            }

            switch gesture.state {
            case .began:
                let currentZoom = scrollView.zoomScale
                let minZoom = scrollView.minimumZoomScale
                print("✅ Coordinator: Pan gesture began. Zoom scale: \(currentZoom)")
                if currentZoom <= minZoom * 1.01 {
                    isTrackingPanForSwipeAction = true
                    dragInitialPoint = gesture.location(in: scrollView.superview)
                    print("--> Tracking pan for potential swipe action.")
                } else {
                    isTrackingPanForSwipeAction = false
                    print("--> Ignoring pan for swipe action because view is zoomed.")
                }

            case .changed:
                // If we're tracking and it becomes mostly horizontal, abandon tracking
                if isTrackingPanForSwipeAction {
                    let translation = gesture.translation(in: scrollView.superview)
                    if abs(translation.x) > abs(translation.y) * 1.5 {
                        isTrackingPanForSwipeAction = false
                        print("--> Abandoning vertical tracking, gesture is horizontal")
                    }
                }
                
            case .ended:
                if !isTrackingPanForSwipeAction {
                    print("✅ Coordinator: Pan ended, but was not tracking for swipe action.")
                    return
                }

                let translation = gesture.translation(in: scrollView.superview)
                let velocity = gesture.velocity(in: scrollView.superview)

                print("✅ Coordinator: Pan ended while tracking. Translation: \(translation), Velocity: \(velocity)")

                // Only proceed with vertical gestures (ignore diagonal ones)
                if abs(translation.x) > abs(translation.y) * 0.8 {
                    print("--> Ignoring gesture that is not primarily vertical")
                    isTrackingPanForSwipeAction = false
                    return
                }

                // Show location panel on swipe up
                let infoSwipeDistance: CGFloat = -65  // More deliberate swipe
                let infoSwipeVelocity: CGFloat = -600 // Faster velocity required
                if !showInfoPanel && (translation.y < infoSwipeDistance || velocity.y < infoSwipeVelocity) {
                    print("--> Showing info panel via swipe up")
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                        showInfoPanel = true
                    }
                    if !controlsHidden {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            controlsHidden = true
                        }
                    }
                    
                    isTrackingPanForSwipeAction = false
                    return
                }

                // Dismiss on swipe down
                let dismissSwipeDistance: CGFloat = 80
                let dismissSwipeVelocity: CGFloat = 500
                if translation.y > dismissSwipeDistance || velocity.y > dismissSwipeVelocity {
                    print("--> Dismiss action triggered via swipe down")
                    dismissAction()
                    isTrackingPanForSwipeAction = false
                    return
                }

                isTrackingPanForSwipeAction = false

            case .cancelled, .failed:
                if isTrackingPanForSwipeAction {
                    print("✅ Coordinator: Pan gesture cancelled/failed")
                }
                isTrackingPanForSwipeAction = false

            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // If the scroll view is zoomed in, don't recognize our swipe gestures
            // so that regular scrolling can work properly
            if let scrollView = gestureRecognizer.view as? UIScrollView, scrollView.zoomScale > 1.01 {
                return false
            }
            
            if gestureRecognizer is UIPanGestureRecognizer {
                // Only allow simultaneous recognition when unzoomed
                print("✅ Coordinator: shouldRecognizeSimultaneouslyWith called for Pan Gesture")
                return true
            }
            
            print("✅ Coordinator: shouldRecognizeSimultaneouslyWith called for other gesture -> false")
            return false
        }
    }
}

