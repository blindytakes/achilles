// Achilles/Views/Onboarding/DailyWelcomeView.swift
import SwiftUI
import AVKit
import AVFoundation

// Custom UIView to host the AVPlayerLayer and manage its frame
class PlayerLayerView: UIView {
    private var playerLayer: AVPlayerLayer?

    init(player: AVPlayer) {
        super.init(frame: .zero)
        self.playerLayer = AVPlayerLayer(player: player)
        if let playerLayer = self.playerLayer {
            playerLayer.videoGravity = .resizeAspectFill
            layer.addSublayer(playerLayer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    func updatePlayer(player: AVPlayer) {
        if self.playerLayer?.player != player {
            self.playerLayer?.player = player
        }
    }
}

// UIViewRepresentable to use PlayerLayerView in SwiftUI
struct CustomVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        return PlayerLayerView(player: player)
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        // No dynamic updates needed
    }
}

struct DailyWelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var photoViewModel: PhotoViewModel

    // MARK: - Video Playback State
    @State private var player: AVPlayer?
    @State private var playerObserver: Any?

    // MARK: - Tutorial Overlay State
    @State private var showingTutorial = false
    @AppStorage("hasSeenTutorialOverlay") private var hasSeenTutorialOverlay: Bool = false
    @AppStorage("lastIntroVideoPlayDate") private var lastIntroVideoPlayDateStorage: Double = 0.0

    // Video resource identifiers
    private let videoFileName = "Opener1"
    private let videoFileExtension = "mp4"

    /// Initialize the AVPlayer with the bundled video
    private func setupPlayer() {
        guard let url = Bundle.main.url(forResource: videoFileName, withExtension: videoFileExtension) else {
            // If missing, skip directly
            finishVideo()
            return
        }
        let newPlayer = AVPlayer(url: url)
        self.player = newPlayer
    }

    /// Finalize intro: record timestamp and navigate to main app
    private func finishVideo() {
        lastIntroVideoPlayDateStorage = Date().timeIntervalSince1970
        authVM.navigateToMainApp()
    }

    var body: some View {
        Group {
            if let player = player {
                CustomVideoPlayerView(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        // Start playback
                        player.seek(to: .zero)
                        player.play()

                        // Remove old observer
                        if let existing = playerObserver {
                            NotificationCenter.default.removeObserver(existing)
                        }

                        // Add new observer for video end
                        playerObserver = NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: player.currentItem,
                            queue: .main
                        ) { _ in
                            if !hasSeenTutorialOverlay {
                                showingTutorial = true
                            } else {
                                finishVideo()
                            }
                        }
                    }
                    .onDisappear {
                        player.pause()
                        if let obs = playerObserver {
                            NotificationCenter.default.removeObserver(obs)
                        }
                    }
            } else {
                // Fallback if player fails
                ZStack {
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    VStack {
                        ProgressView("Loading Animation...")
                        Button("Continue") {
                            finishVideo()
                        }
                        .padding(.top)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        //  MARK: - Tutorial Sheet
        // MARK: - Tutorial Full-Screen Overlay
        .fullScreenCover(isPresented: $showingTutorial, onDismiss: {
            hasSeenTutorialOverlay = true
            finishVideo()
        }) {
            ZStack {
                // 1) Makes the image fill the entire screen
                Image("TutorialOverlay")
                    .resizable()
                    .scaledToFill()
                    .edgesIgnoringSafeArea(.all)

                // 2) Puts your button on top, at the bottom
                VStack {
                    Spacer()
                    Button(action: { showingTutorial = false }) {
                        Text("Ready for my Throwbaks")
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.black.opacity(0.8))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.bottom, 400)
                }
            }
        }
        .onAppear {
            // Setup player when the view appears
            if player == nil {
                setupPlayer()
            }
        }
    }
}

struct DailyWelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        DailyWelcomeView()
            .environmentObject(AuthViewModel())
    }
}

