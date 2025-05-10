// Achilles/Views/Media/ZoomableScrollView.swift

import SwiftUI
import UIKit

// MARK: - Content Type Enum
enum ZoomableContentType {
    case image
    case livePhoto
}

// MARK: Constants
fileprivate struct Constants {
    static let maximumZoomScale: CGFloat = 8.0
    static let minimumZoomScale: CGFloat = 1.0
    static let zoomSlightlyAboveMinimum: CGFloat = 1.01
    static let doubleTapZoomScale: CGFloat = 3.0
    static let zoomRectCalculationFactor: CGFloat = 2.0
    static let panMinVerticalDistanceStartFeedback: CGFloat = 50
    static let panHorizontalDominanceFactor: CGFloat = 0.8
    static let panDismissProgressMax: CGFloat = 1.0
    static let panDismissProgressDistanceDivider: CGFloat = 300
    static let panFeedbackAnimationDuration: Double = 0.1
    static let panFeedbackMinAlpha: CGFloat = 0.7
    static let panFeedbackAlphaFactor: CGFloat = 0.3
    static let panFeedbackScaleFactor: CGFloat = 0.05
    static let panResetAnimationDuration: Double = 0.3
    static let panMinVerticalDistanceForDismiss: CGFloat = 100
    static let panDismissHorizontalDominanceFactor: CGFloat = 0.5
    static let doubleTapRequiredTaps: Int = 2
    static let centerContentDivisionFactor: CGFloat = 2.0
    static let minContentInset: CGFloat = 0.0
    static let directionTolerance: CGFloat = 45.0
}

// MARK: - Zoomable ScrollView Representable
struct ZoomableScrollView<Content: View>: UIViewRepresentable {



    // MARK: Properties
    let content: Content
    let contentId: String
    @Binding var showInfoPanel: Bool
    @Binding var controlsHidden: Bool
    @Binding var zoomScale: CGFloat
    let dismissAction: () -> Void
    let contentType: ZoomableContentType

    // MARK: Init
    init(
        contentId: String,
        contentType: ZoomableContentType = .image,
        showInfoPanel: Binding<Bool>,
        controlsHidden: Binding<Bool>,
        zoomScale: Binding<CGFloat>,
        dismissAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.contentId = contentId
        self.contentType = contentType
        self._showInfoPanel = showInfoPanel
        self._controlsHidden = controlsHidden
        self._zoomScale = zoomScale
        self.dismissAction = dismissAction
        self.content = content()
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

        let hostedView = context.coordinator.hostingController.view!
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        hostedView.backgroundColor = .clear
        hostedView.isUserInteractionEnabled = true
        hostedView.layer.allowsEdgeAntialiasing = true
        hostedView.layer.minificationFilter = .trilinear
        hostedView.layer.magnificationFilter = .trilinear

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
        context.coordinator.initialZoomScale = scrollView.minimumZoomScale
        context.coordinator.lastContentId = self.contentId
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.hostingController.rootView = content
        
        if context.coordinator.lastContentId != self.contentId {
            scrollView.setZoomScale(Constants.minimumZoomScale, animated: false)
            scrollView.contentOffset = .zero
            DispatchQueue.main.async {
                if abs(self.zoomScale - scrollView.zoomScale) > 0.001 {
                     self.zoomScale = scrollView.zoomScale
                }
            }
            context.coordinator.isZoomed = false
            context.coordinator.lastContentId = self.contentId
        }
        
        DispatchQueue.main.async {
            context.coordinator.centerContent(scrollView)
            if abs(scrollView.zoomScale - self.zoomScale) > 0.001 && context.coordinator.lastContentId == self.contentId {
                 scrollView.setZoomScale(self.zoomScale, animated: true)
            }
        }
        context.coordinator.hostingController.view.setNeedsLayout()
    }

    // MARK: - Coordinator Class
    class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ZoomableScrollView
        var hostingController: UIHostingController<Content>
        var isZoomed: Bool = false
        var startTouchPoint: CGPoint = .zero
        var initialPanDirection: CGPoint = .zero
        var initialZoomScale: CGFloat = 1.0
        var lastContentId: String?
        
        weak var customPanGesture: UIPanGestureRecognizer?

        init(parent: ZoomableScrollView, hostingController: UIHostingController<Content>) {
            self.parent = parent
            self.hostingController = hostingController
            self.lastContentId = parent.contentId
        }

        func setupGestureRecognizers(for scrollView: UIScrollView) {
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = Constants.doubleTapRequiredTaps
            scrollView.addGestureRecognizer(doubleTap)

            if parent.contentType == .image {
                let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
                singleTap.require(toFail: doubleTap)
                scrollView.addGestureRecognizer(singleTap)
            }

            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
            panGesture.delegate = self
            scrollView.addGestureRecognizer(panGesture)
            self.customPanGesture = panGesture
        }

        // MARK: UIScrollViewDelegate
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController.view
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            centerContent(scrollView)
            Task { @MainActor in
                if abs(parent.zoomScale - scrollView.zoomScale) > 0.001 {
                    parent.zoomScale = scrollView.zoomScale
                }
            }
            isZoomed = scrollView.zoomScale > (scrollView.minimumZoomScale + 0.01)
        }
        
        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            // print("ZoomableScrollView.Coordinator: scrollViewDidEndZooming at scale \(scale)")
        }

        // MARK: Helper Methods
        func centerContent(_ scrollView: UIScrollView) {
            guard let hostedView = hostingController.view else { return }
            let boundsSize = scrollView.bounds.size
            let horizontalInset = max(Constants.minContentInset, (boundsSize.width - hostedView.frame.size.width * scrollView.zoomScale) / 2.0)
            let verticalInset = max(Constants.minContentInset, (boundsSize.height - hostedView.frame.size.height * scrollView.zoomScale) / 2.0)
            let newInsets = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
            if scrollView.contentInset != newInsets {
                scrollView.contentInset = newInsets
            }
        }

        // MARK: Gesture Handlers
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let targetScale: CGFloat = (scrollView.zoomScale > scrollView.minimumZoomScale + 0.01) ? scrollView.minimumZoomScale : Constants.doubleTapZoomScale
            let zoomPointInHostedView = gesture.location(in: hostingController.view)
            let zoomRect = zoomRect(for: targetScale, with: zoomPointInHostedView, in: scrollView)
            scrollView.zoom(to: zoomRect, animated: true)
        }
        
        private func zoomRect(for scale: CGFloat, with center: CGPoint, in scrollView: UIScrollView) -> CGRect {
            var zoomRect = CGRect.zero
            zoomRect.size.width  = scrollView.frame.size.width  / scale
            zoomRect.size.height = scrollView.frame.size.height / scale
            zoomRect.origin.x = center.x - (zoomRect.size.width  / 2.0)
            zoomRect.origin.y = center.y - (zoomRect.size.height / 2.0)
            return zoomRect
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            // print("ZoomableScrollView.Coordinator: handleSingleTap (from UIScrollView's gesture).")
        }

        @objc func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if isZoomed || parent.showInfoPanel {
                if (gesture.state == .changed || gesture.state == .began) && (scrollView.transform != .identity || scrollView.alpha != 1.0) {
                    UIView.animate(withDuration: Constants.panResetAnimationDuration) {
                        scrollView.alpha = 1.0
                        scrollView.transform = .identity
                    }
                }
                if isZoomed { return }
            }
            
            switch gesture.state {
            case .began:
                startTouchPoint = gesture.location(in: scrollView.superview)
                initialPanDirection = .zero
            case .changed:
                let translation = gesture.translation(in: scrollView.superview)
                if initialPanDirection == .zero && (abs(translation.x) > 0 || abs(translation.y) > 0) {
                    initialPanDirection = translation
                }
                let isInitiallyVerticalAndDown = abs(initialPanDirection.y) > abs(initialPanDirection.x) * 1.5 && initialPanDirection.y > 0
                if isInitiallyVerticalAndDown && translation.y > 0 {
                    let progress = min(Constants.panDismissProgressMax, translation.y / Constants.panDismissProgressDistanceDivider)
                    let scaleFactor = 1.0 - (progress * Constants.panFeedbackScaleFactor)
                    let alphaFactor = max(Constants.panFeedbackMinAlpha, 1.0 - (progress * Constants.panFeedbackAlphaFactor))
                    scrollView.alpha = alphaFactor
                    scrollView.transform = CGAffineTransform(translationX: translation.x, y: translation.y).scaledBy(x: scaleFactor, y: scaleFactor)
                } else if scrollView.transform != .identity {
                    UIView.animate(withDuration: Constants.panFeedbackAnimationDuration) {
                        scrollView.alpha = 1.0
                        scrollView.transform = .identity
                    }
                }
            case .ended, .cancelled:
                let translation = gesture.translation(in: scrollView.superview)
                let isInitiallyVerticalAndDownOnEnd = abs(initialPanDirection.y) > abs(initialPanDirection.x) * 1.5 && initialPanDirection.y > 0
                let hasPannedEnough = translation.y > Constants.panMinVerticalDistanceForDismiss
                let isVerticalDominantOnEnd = abs(translation.x) < abs(translation.y) * Constants.panDismissHorizontalDominanceFactor
                let shouldDismiss = isInitiallyVerticalAndDownOnEnd && hasPannedEnough && isVerticalDominantOnEnd && gesture.state == .ended
                if shouldDismiss {
                    UIView.animate(withDuration: Constants.panResetAnimationDuration, animations: {
                        scrollView.alpha = 0.0
                        scrollView.transform = CGAffineTransform(translationX: translation.x, y: scrollView.frame.height)
                    }) { _ in self.parent.dismissAction() }
                } else {
                    UIView.animate(withDuration: Constants.panResetAnimationDuration) {
                        scrollView.alpha = 1.0
                        scrollView.transform = .identity
                    }
                }
                initialPanDirection = .zero
            default:
                if scrollView.transform != .identity || scrollView.alpha != 1.0 {
                     UIView.animate(withDuration: Constants.panResetAnimationDuration) {
                         scrollView.alpha = 1.0
                         scrollView.transform = .identity
                     }
                }
                initialPanDirection = .zero; break
            }
        }

        // MARK: UIGestureRecognizerDelegate
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            if gestureRecognizer == self.customPanGesture {
                if isZoomed { return false }
                return true
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Get the scroll view from the gesture recognizer's view property
            guard let currentScrollView = gestureRecognizer.view as? UIScrollView else {
                return true // Default if view is not UIScrollView (should not happen here)
            }

            if gestureRecognizer == self.customPanGesture {
                if isZoomed && otherGestureRecognizer == currentScrollView.panGestureRecognizer { // Use currentScrollView
                    return false
                }
                return !isZoomed
            }
            if otherGestureRecognizer == self.customPanGesture {
                 if isZoomed && gestureRecognizer == currentScrollView.panGestureRecognizer { // Use currentScrollView
                    return false
                }
                return !isZoomed
            }
            return true
        }
    } // End Coordinator
} // End Struct
