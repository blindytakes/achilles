import SwiftUI
import AVKit
import AVFoundation

// Custom UIView to host the AVPlayerLayer and manage its frame
class PlayerLayerView: UIView { // Renamed from PlayerUIView for clarity within this context
    private var playerLayer: AVPlayerLayer?

    init(player: AVPlayer) {
        super.init(frame: .zero)
        self.playerLayer = AVPlayerLayer(player: player)
        if let playerLayer = self.playerLayer {
            playerLayer.videoGravity = .resizeAspectFill // Or .resizeAspect
            layer.addSublayer(playerLayer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds // Ensure playerLayer always fills the bounds of this UIView
    }

    // Allow changing the player if needed, though for this use case it's set on init
    func updatePlayer(player: AVPlayer) {
        if self.playerLayer?.player != player {
            self.playerLayer?.player = player
        }
    }
}

struct CustomVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        // Return an instance of our custom PlayerLayerView
        return PlayerLayerView(player: player)
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        // If the player instance itself could change, update it here
        // For this specific DailyWelcomeView, the player is created once.
        // uiView.updatePlayer(player: player) // Usually not needed if player doesn't change after init
    }

    // No Coordinator needed if PlayerLayerView handles its own layout
}

// ... rest of your DailyWelcomeView code remains the same ...

struct DailyWelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var player: AVPlayer?
    @State private var isVideoFinished = false
    @State private var playerObserver: Any?

    private let videoFileName = "startingvideo"
    private let videoFileExtension = "mp4"

    private func setupPlayer() {
        guard let videoURL = Bundle.main.url(forResource: videoFileName, withExtension: videoFileExtension) else {
            print("Error: Video file '\(videoFileName).\(videoFileExtension)' not found in bundle.")
            proceedAfterVideo()
            return
        }
        let newPlayer = AVPlayer(url: videoURL)
        // newPlayer.isMuted = true // Uncomment if you want it silent
        self.player = newPlayer
    }

    private func proceedAfterVideo() {
        if !isVideoFinished {
            isVideoFinished = true
            authVM.navigateToMainApp()
        }
    }

    var body: some View {
        Group {
            if let player = player {
                CustomVideoPlayerView(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        player.play()
                        if let existingObserver = playerObserver {
                            NotificationCenter.default.removeObserver(existingObserver)
                        }
                        playerObserver = NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: player.currentItem,
                            queue: .main
                        ) { _ in
                            print("Video (animation) finished playing.")
                            proceedAfterVideo()
                        }
                    }
                    .onDisappear {
                        player.pause()
                        if let observer = playerObserver {
                            NotificationCenter.default.removeObserver(observer)
                            playerObserver = nil
                        }
                    }
            } else {
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
                             proceedAfterVideo()
                        }
                        .padding(.top)
                    }
                }
            }
        }
        .onAppear {
            if self.player == nil {
                setupPlayer()
            } else {
                if !isVideoFinished {
                    self.player?.seek(to: .zero)
                    self.player?.play()
                }
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
