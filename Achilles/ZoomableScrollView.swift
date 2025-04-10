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
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true

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

        // Used for basic zoom tracking
        private var isZoomed: Bool = false
        // For swipe down detection
        private var startTouchPoint: CGPoint = .zero

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
            // Double tap for zoom
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            scrollView.addGestureRecognizer(doubleTap)

            // Single tap for controls
            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            singleTap.require(toFail: doubleTap)
            scrollView.addGestureRecognizer(singleTap)
            
            // Add a pan gesture recognizer for swipe down to dismiss
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            panGesture.delegate = self
            scrollView.addGestureRecognizer(panGesture)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
            zoomScale = scrollView.zoomScale
            isZoomed = scrollView.zoomScale > 1.01
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
        
        // Handle pan gesture for swipe down to dismiss
        @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            
            // Don't interfere if the scroll view is zoomed in
            if scrollView.zoomScale > 1.01 {
                return
            }
            
            // Don't handle gestures when info panel is showing
            if showInfoPanel {
                return
            }
            
            switch gesture.state {
            case .began:
                startTouchPoint = gesture.location(in: scrollView)
                
            case .changed:
                let currentPoint = gesture.location(in: scrollView)
                let verticalDistance = currentPoint.y - startTouchPoint.y
                let horizontalDistance = currentPoint.x - startTouchPoint.x
                
                // Only provide feedback if this is primarily a vertical swipe down
                if verticalDistance > 50 && abs(horizontalDistance) < abs(verticalDistance) * 0.8 {
                    // Calculate an opacity value based on how far they've swiped
                    let dismissProgress = min(1.0, verticalDistance / 300)
                    
                    // Apply a subtle dimming effect to indicate progress
                    UIView.animate(withDuration: 0.1) {
                        scrollView.alpha = max(0.7, 1.0 - dismissProgress * 0.3)
                        
                        // Apply a subtle scale effect
                        scrollView.transform = CGAffineTransform(scaleX: 1.0 - dismissProgress * 0.05,
                                                                y: 1.0 - dismissProgress * 0.05)
                    }
                }
                
            case .ended, .cancelled:
                // Reset any visual effects first
                UIView.animate(withDuration: 0.3) {
                    scrollView.alpha = 1.0
                    scrollView.transform = .identity
                }
                
                let currentPoint = gesture.location(in: scrollView)
                let verticalDistance = currentPoint.y - startTouchPoint.y
                let horizontalDistance = currentPoint.x - startTouchPoint.x
                
                // Only process if this is primarily a vertical swipe down
                if verticalDistance > 100 && abs(horizontalDistance) < abs(verticalDistance) * 0.5 {
                    dismissAction()
                }
                
            default:
                // Reset any visual effects
                UIView.animate(withDuration: 0.3) {
                    scrollView.alpha = 1.0
                    scrollView.transform = .identity
                }
                break
            }
        }
        
        // MARK: - UIGestureRecognizerDelegate
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow the scroll view to handle its gestures normally
            return true
        }
    }
}


