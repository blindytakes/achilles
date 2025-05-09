import SwiftUI
import UIKit

// MARK: - Content Type

/// Differentiates between static images and Live Photos for gesture handling.
enum ZoomableContentType {
    case image
    case livePhoto
}

// MARK: - Constants

/// Centralized constants for zoom, pan, and gesture configuration.
fileprivate struct ZoomableScrollViewConstants {
    static let maxZoom: CGFloat               = 8.0
    static let minZoom: CGFloat               = 1.0
    static let doubleTapZoom: CGFloat         = 3.0
    static let zoomRectFactor: CGFloat        = 2.0

    static let panResetDuration: Double       = 0.3
    static let panFeedbackDuration: Double    = 0.1
    static let panFeedbackMinAlpha: CGFloat   = 0.7
    static let panFeedbackAlphaFactor: CGFloat = 0.3
    static let panFeedbackScaleFactor: CGFloat = 0.05
    static let panDismissThreshold: CGFloat   = 100
    static let panDismissHorzFactor: CGFloat  = 0.5
    static let panDistanceDivider: CGFloat    = 300
    static let directionTolerance: CGFloat    = 45.0

    static let doubleTapCount: Int            = 2
    static let centerDivision: CGFloat        = 2.0
    static let minInset: CGFloat              = 0.0
}

// MARK: - ZoomableScrollView

/// Wraps SwiftUI content in a UIScrollView to provide pinch‑to‑zoom,
/// double‑tap zoom, and swipe‑down dismissal gestures.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    // MARK: Properties
    let contentType: ZoomableContentType
    @Binding var showInfoPanel: Bool    // Controls info panel visibility
    @Binding var controlsHidden: Bool   // Toggles overlay controls
    @Binding var zoomScale: CGFloat     // Reports current zoom scale
    let dismissAction: () -> Void       // Called on swipe‑down dismissal
    let content: Content                // SwiftUI view to host

    // MARK: Initializer
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
        #if DEBUG
        print("ZoomableScrollView initialized (type: \(contentType))")
        #endif
    }

    // MARK: UIViewRepresentable
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self,
                    hostingController: UIHostingController(rootView: content))
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = ZoomableScrollViewConstants.maxZoom
        scrollView.minimumZoomScale = ZoomableScrollViewConstants.minZoom
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true

        // Host the SwiftUI content
        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostedView)

        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.setupGestures(on: scrollView)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        context.coordinator.hostingController.view.setNeedsLayout()
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let parent: ZoomableScrollView
        let hostingController: UIHostingController<Content>
        private var isZoomed = false
        private var startPoint = CGPoint.zero
        private var initialPan = CGPoint.zero

        init(parent: ZoomableScrollView, hostingController: UIHostingController<Content>) {
            self.parent = parent
            self.hostingController = hostingController
            super.init()
            #if DEBUG
            print("Coordinator initialized for \(parent.contentType)")
            #endif
        }

        /// Attach gestures to the scroll view
        func setupGestures(on scrollView: UIScrollView) {
            // Double‑tap to zoom
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = ZoomableScrollViewConstants.doubleTapCount
            scrollView.addGestureRecognizer(doubleTap)

            // Single‑tap to toggle controls (only for images)
            if parent.contentType == .image {
                let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
                singleTap.require(toFail: doubleTap)
                scrollView.addGestureRecognizer(singleTap)
            }

            // Pan‑down to dismiss
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            scrollView.addGestureRecognizer(pan)
        }

        // MARK: Gesture Handlers

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            let targetScale = isZoomed ? ZoomableScrollViewConstants.minZoom
                                       : ZoomableScrollViewConstants.doubleTapZoom
            let location = gesture.location(in: hostingController.view)
            let width = scroll.bounds.width / targetScale
            let height = scroll.bounds.height / targetScale
            let rect = CGRect(
                x: location.x - width/ZoomableScrollViewConstants.zoomRectFactor,
                y: location.y - height/ZoomableScrollViewConstants.zoomRectFactor,
                width: width,
                height: height
            )
            scroll.zoom(to: rect, animated: true)
        }

        @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            withAnimation { parent.controlsHidden.toggle() }
            if !parent.controlsHidden && parent.showInfoPanel {
                withAnimation { parent.showInfoPanel = false }
            }
        }

        @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scroll = gesture.view as? UIScrollView else { return }
            // Prevent pan if zoomed or infoPanel is visible
            if isZoomed || parent.showInfoPanel {
                if gesture.state == .ended || gesture.state == .cancelled {
                    reset(scroll)
                }
                return
            }

            let translation = gesture.translation(in: scroll.superview)
            switch gesture.state {
            case .began:
                startPoint = gesture.location(in: scroll.superview)
                initialPan = .zero

            case .changed:
                if initialPan == .zero { initialPan = translation }
                let vertical = abs(initialPan.y) > abs(initialPan.x)
                guard vertical && translation.y > 0 else { reset(scroll); return }
                let progress = min(1, translation.y / ZoomableScrollViewConstants.panDistanceDivider)
                scroll.alpha = max(
                    ZoomableScrollViewConstants.panFeedbackMinAlpha,
                    1 - progress * ZoomableScrollViewConstants.panFeedbackAlphaFactor
                )
                scroll.transform = CGAffineTransform(
                    translationX: translation.x, y: translation.y
                ).scaledBy(
                    x: 1 - progress*ZoomableScrollViewConstants.panFeedbackScaleFactor,
                    y: 1 - progress*ZoomableScrollViewConstants.panFeedbackScaleFactor
                )

            case .ended, .cancelled:
                let vertical = abs(initialPan.y) > abs(initialPan.x)
                let shouldDismiss = vertical
                    && translation.y > ZoomableScrollViewConstants.panDismissThreshold
                    && abs(translation.x) < abs(translation.y) * ZoomableScrollViewConstants.panDismissHorzFactor
                if shouldDismiss {
                    parent.dismissAction()
                } else {
                    reset(scroll)
                }

            default:
                reset(scroll)
            }
        }

        /// Animate scroll view back to identity
        private func reset(_ scrollView: UIScrollView) {
            UIView.animate(withDuration: ZoomableScrollViewConstants.panResetDuration) {
                scrollView.alpha = 1.0
                scrollView.transform = .identity
            }
        }

        // MARK: UIScrollViewDelegate

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollView.centerContent(
                hostingController.view,
                division: ZoomableScrollViewConstants.centerDivision
            )
            parent.zoomScale = scrollView.zoomScale
            isZoomed = scrollView.zoomScale > ZoomableScrollViewConstants.minZoom * 1.01
        }

        // MARK: UIGestureRecognizerDelegate

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }
            let velocity = pan.velocity(in: view)
            let angle = atan2(abs(velocity.y), abs(velocity.x)) * 180 / .pi
            return angle > ZoomableScrollViewConstants.directionTolerance
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - UIScrollView Centering

private extension UIScrollView {
    /// Centers the hosted view if smaller than scroll bounds
    func centerContent(_ view: UIView, division: CGFloat) {
        let boundsSize = bounds.size
        let contentSize = view.frame.size
        let insetY = max(
            ZoomableScrollViewConstants.minInset,
            (boundsSize.height - contentSize.height) / division
        )
        let insetX = max(
            ZoomableScrollViewConstants.minInset,
            (boundsSize.width - contentSize.width) / division
        )
        contentInset = UIEdgeInsets(top: insetY, left: insetX,
                                    bottom: insetY, right: insetX)
    }
}

// MARK: - SwiftUI View Modifier

extension View {
    /// Wrap a view in ZoomableScrollView for pinch, double‑tap, and swipe‑down gestures.
    func zoomable(
        contentType: ZoomableContentType = .image,
        showInfoPanel: Binding<Bool>,
        controlsHidden: Binding<Bool>,
        zoomScale: Binding<CGFloat>,
        dismissAction: @escaping () -> Void
    ) -> some View {
        ZoomableScrollView(
            contentType: contentType,
            showInfoPanel: showInfoPanel,
            controlsHidden: controlsHidden,
            zoomScale: zoomScale,
            dismissAction: dismissAction
        ) { self }
    }
}
