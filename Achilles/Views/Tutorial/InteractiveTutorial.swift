// InteractiveTutorial.swift
//
// Tutorial system extracted from ContentView.swift.
// Contains the tutorial state manager, overlay view, and hint view.

import SwiftUI

// MARK: - Enhanced Tutorial Manager
@MainActor
class InteractiveTutorialManager: ObservableObject {
    @Published var currentStep: TutorialStep = .welcome
    @Published var isActive = false
    @Published var showOverlay = false
    @AppStorage("tutorialCurrentStep") private var persistedStep: String = "welcome"
    @AppStorage("hasCompletedInteractiveTutorial") var hasCompleted = false

    // Animation states
    @Published var isPulsing = false
    @Published var showArrows = false

    enum TutorialStep: String, CaseIterable {
        case welcome
        case swipeYears
        case tapFeatured
        case viewDetails
        case useLocation
        case completed

        var title: String {
            switch self {
            case .welcome: return "Welcome to Throwbaks!"
            case .swipeYears: return "Swipe Between Years"
            case .tapFeatured: return "Tap a Memory"
            case .viewDetails: return "Zoom, Live Photos, & Share"
            case .useLocation: return "View Photo Locations"
            case .completed: return "Get Ready To Explore!"
            }
        }

        var instruction: String {
            switch self {
            case .welcome:
                return "ThrowBaks highlights photos from today's date from previous years"
            case .swipeYears:
                return "Swipe Left to see older years, Swipe Right to see newer years"
            case .tapFeatured:
                return "Tap any photo to open that memory in full view"
            case .viewDetails:
                return "Zoom in, View Live Photos, & Share to your favorite apps"
            case .useLocation:
                return "When you see a map button, tap to see where the photo was taken"
            case .completed:
                return "ThrowBaks is Easy to Use"
            }
        }

        var requiresUserAction: Bool {
            switch self {
            case .welcome, .completed: return false
            default: return true
            }
        }

        var hasNext: Bool {
            self != .completed
        }
    }

    init() {
        if !hasCompleted, let step = TutorialStep(rawValue: persistedStep) {
            currentStep = step
        }
    }

    func startTutorial() {
        isActive = true
        showOverlay = true
        currentStep = .welcome
        persistedStep = currentStep.rawValue
        startAnimationsForStep()
    }

    func nextStep() {
        guard currentStep.hasNext else {
            completeTutorial()
            return
        }

        let allSteps = TutorialStep.allCases
        if let currentIndex = allSteps.firstIndex(of: currentStep),
           currentIndex < allSteps.count - 1 {
            withAnimation(.spring()) {
                currentStep = allSteps[currentIndex + 1]
                persistedStep = currentStep.rawValue
                startAnimationsForStep()
            }
        }
    }

    func actionPerformed(for step: TutorialStep) {
        guard currentStep == step && isActive else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.nextStep()
        }
    }

    func skipTutorial() {
        completeTutorial()
    }

    func skipToNextStep() {
        nextStep()
    }

    private func completeTutorial() {
        withAnimation(.easeOut) {
            isActive = false
            showOverlay = false
            hasCompleted = true
            persistedStep = TutorialStep.completed.rawValue
        }
    }

    private func startAnimationsForStep() {
        isPulsing = false
        showArrows = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch self.currentStep {
            case .swipeYears:
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    self.showArrows = true
                }
            case .tapFeatured:
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    self.isPulsing = true
                }
            default:
                break
            }
        }
    }

    func shouldShowStepGuidance(for step: TutorialStep) -> Bool {
        return isActive && currentStep == step
    }
}

// MARK: - Tutorial Overlay View

struct TutorialOverlayView: View {
    @ObservedObject var tutorialManager: InteractiveTutorialManager
    let geometryProxy: GeometryProxy
    let hasPhotosWithLocation: Bool

    // Light green color scheme
    private let lightGreen = Color(red: 0.565, green: 0.933, blue: 0.565)
    private let forestGreen = Color(red: 0.184, green: 0.310, blue: 0.184)
    private let mediumGreen = Color(red: 0.133, green: 0.545, blue: 0.133)

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    if !tutorialManager.currentStep.requiresUserAction {
                        tutorialManager.nextStep()
                    }
                }

            VStack {
                Spacer()

                VStack(spacing: 20) {
                    HStack {
                        ForEach(Array(InteractiveTutorialManager.TutorialStep.allCases.enumerated()), id: \.offset) { index, step in
                            Circle()
                                .fill(index <= InteractiveTutorialManager.TutorialStep.allCases.firstIndex(of: tutorialManager.currentStep) ?? 0 ?
                                     mediumGreen : mediumGreen.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(tutorialManager.currentStep.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(forestGreen)
                        .multilineTextAlignment(.center)

                    Text(stepInstructionText)
                        .font(.body)
                        .foregroundColor(forestGreen.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    actionButtons
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(lightGreen.opacity(0.95))
                        .shadow(color: .black.opacity(0.3), radius: 20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(lightGreen.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)

                Spacer().frame(height: 100)
            }

            tutorialHighlights
        }
    }

    private var stepInstructionText: String {
        switch tutorialManager.currentStep {
        case .useLocation:
            return hasPhotosWithLocation ?
                tutorialManager.currentStep.instruction :
                "No photos with location data found. Continue exploring to learn more features!"
        default:
            return tutorialManager.currentStep.instruction
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(tutorialManager.currentStep == .completed ? "Take Me to ThrowBaks!" : "Next") {
            tutorialManager.nextStep()
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 12)
        .background(mediumGreen)
        .foregroundColor(.white)
        .cornerRadius(8)
        .fontWeight(.semibold)
        .shadow(color: mediumGreen.opacity(0.3), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var tutorialHighlights: some View {
        switch tutorialManager.currentStep {
        case .swipeYears:
            HStack {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(lightGreen)
                        .opacity(tutorialManager.showArrows ? 1.0 : 0.6)
                        .shadow(color: .black.opacity(0.4), radius: 6)

                    Text("Older")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(lightGreen)
                        .opacity(tutorialManager.showArrows ? 1.0 : 0.6)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }

                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(lightGreen)
                        .opacity(tutorialManager.showArrows ? 1.0 : 0.6)
                        .shadow(color: .black.opacity(0.4), radius: 6)

                    Text("Newer")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(lightGreen)
                        .opacity(tutorialManager.showArrows ? 1.0 : 0.6)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                }
            }
            .padding(.horizontal, 40)
            .position(x: geometryProxy.size.width / 2, y: geometryProxy.size.height * 0.45)

        case .tapFeatured:
            Circle()
                .stroke(lightGreen, lineWidth: 3)
                .frame(width: 170, height: 170)
                .opacity(0.8)
                .scaleEffect(tutorialManager.isPulsing ? 1.2 : 1.0)
                .position(x: geometryProxy.size.width / 2, y: geometryProxy.size.height * 0.4)
                .allowsHitTesting(false)
                .shadow(color: lightGreen.opacity(0.3), radius: 8)

        default:
            EmptyView()
        }
    }
}

// MARK: - Main Experience Hint View

struct MainExperienceHintView: View {
    let text: String
    var showsDirectionalArrows: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if showsDirectionalArrows {
                swipeArrow(systemName: "arrow.left", rotation: 0, xOffset: -2, yOffset: 0)
            }

            Text(text)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)

            if showsDirectionalArrows {
                swipeArrow(systemName: "arrow.right", rotation: 0, xOffset: 2, yOffset: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
        .allowsHitTesting(false)
    }

    private func swipeArrow(systemName: String, rotation: Double, xOffset: CGFloat, yOffset: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.footnote.weight(.black))
            .foregroundColor(.white.opacity(0.9))
            .rotationEffect(.degrees(rotation))
            .offset(x: xOffset, y: yOffset)
            .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 2)
    }
}
