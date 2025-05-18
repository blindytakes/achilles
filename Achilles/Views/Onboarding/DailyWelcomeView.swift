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
            playerLayer.videoGravity = .resizeAspectFill // Or .resizeAspect if you prefer
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

// UIViewRepresentable to use PlayerLayerView in SwiftUI
struct CustomVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        return PlayerLayerView(player: player)
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        // If the player instance itself could change dynamically (not in this specific view's case),
        // you would update it here. For DailyWelcomeView, the player is set up once.
        // uiView.updatePlayer(player: player)
    }
}


struct DailyWelcomeView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var player: AVPlayer?
    @State private var isVideoFinished = false // Local state to ensure flag is set once per view instance
    @State private var playerObserver: Any?

    // AppStorage to persist the last time the intro video was played.
    // Uses the same key as in ThrowbacksApp.swift to ensure synchronization.
    @AppStorage("lastIntroVideoPlayDate") private var lastIntroVideoPlayDateStorage: Double = 0.0

    // Video file details (ensure this video is in your app's bundle)
    private let videoFileName = "startingvideo"
    private let videoFileExtension = "mp4"

    // Sets up the AVPlayer
    private func setupPlayer() {
        guard let videoURL = Bundle.main.url(forResource: videoFileName, withExtension: videoFileExtension) else {
            print("DailyWelcomeView Error: Video file '\(videoFileName).\(videoFileExtension)' not found in bundle.")
            // If video is missing, proceed immediately so the app doesn't get stuck.
            // This will also mark the video as "played" for the day.
            proceedAfterVideo()
            return
        }
        let newPlayer = AVPlayer(url: videoURL)
        // newPlayer.isMuted = true // Uncomment if you want the video to be silent by default
        self.player = newPlayer
    }

    // Called when the video finishes or if it's skipped/fails to load
    private func proceedAfterVideo() {
        // Ensure this logic runs only once per instance of the view,
        // or if the video is explicitly replayed.
        if !isVideoFinished {
            isVideoFinished = true
            
            // Record the current time as the last playback time.
            // This timestamp will be checked on the next app launch.
            print("Intro video in DailyWelcomeView finished or was skipped. Updating lastIntroVideoPlayDateStorage.")
            lastIntroVideoPlayDateStorage = Date().timeIntervalSince1970 // Store as TimeInterval since 1970
            
            // Navigate to the main application content.
            authVM.navigateToMainApp()
        }
    }

    var body: some View {
        Group {
            if let player = player {
                CustomVideoPlayerView(player: player)
                    .edgesIgnoringSafeArea(.all) // Make the video player full screen
                    .onAppear {
                        // Start playing the video when the view appears,
                        // but only if it hasn't been marked as finished yet.
                        if !isVideoFinished {
                            player.seek(to: .zero) // Rewind to the beginning
                            player.play()
                        }
                        
                        // Remove any existing observer before adding a new one to prevent duplicates
                        // if the view were to reappear multiple times.
                        if let existingObserver = playerObserver {
                            NotificationCenter.default.removeObserver(existingObserver)
                            playerObserver = nil
                        }
                        
                        // Observe the .AVPlayerItemDidPlayToEndTime notification to detect when the video finishes.
                        playerObserver = NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: player.currentItem, // Observe the current item of this specific player
                            queue: .main // Ensure the block executes on the main thread
                        ) { _ in
                            print("Video (DailyWelcomeView) finished playing via .AVPlayerItemDidPlayToEndTime notification.")
                            proceedAfterVideo() // Call to update timestamp and navigate
                        }
                    }
                    .onDisappear {
                        player.pause() // Pause the video if the view disappears
                        
                        // Clean up the notification observer to prevent memory leaks or unexpected behavior.
                        if let observer = playerObserver {
                            NotificationCenter.default.removeObserver(observer)
                            playerObserver = nil
                        }
                    }
                // The .onTapGesture modifier has been removed as per your request.
            } else {
                // Fallback UI: Shown if the player couldn't be initialized (e.g., video file is missing).
                ZStack {
                    // A simple gradient background for the fallback view.
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                    
                    VStack {
                        // Provide a different message if no video is intended (e.g., filename is empty).
                        if videoFileName.isEmpty && videoFileExtension.isEmpty {
                             Text("Welcome!")
                                .font(.largeTitle)
                                .padding(.bottom)
                        } else {
                            // Standard loading message if a video was expected.
                            ProgressView("Loading Animation...")
                        }
                        
                        // "Continue" button allows the user to bypass this screen if loading is stuck or video fails.
                        Button("Continue") {
                             proceedAfterVideo()
                        }
                        .padding(.top)
                        .buttonStyle(.borderedProminent) // Makes the button more visually distinct.
                    }
                }
            }
        }
        .onAppear {
            // This outer onAppear handles the initial setup of the player
            // or re-initiates playback if the view appears again and the video wasn't finished.
            if self.player == nil && !isVideoFinished {
                setupPlayer()
            } else if let existingPlayer = self.player, !isVideoFinished {
                // If player exists (e.g., view re-appeared quickly) and video hasn't finished,
                // rewind and play again.
                existingPlayer.seek(to: .zero)
                existingPlayer.play()
            }
        }
    }
}

struct DailyWelcomeView_Previews: PreviewProvider {
    static var previews: some View {
        DailyWelcomeView()
            .environmentObject(AuthViewModel()) // Provide AuthViewModel for the preview to work correctly.
    }
}
