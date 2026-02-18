// VideoPreviewView.swift
//
// Inline video preview shown after a collage video export completes.
// Plays the exported video in a seamless loop with action buttons
// for Save to Photos, Share, and Regenerate.
//
// Visual personality:
//   - Celebratory header ("Your video is ready!")
//   - Gradient-filled primary button matching brand greens.
//   - Bouncy entrance with scale + opacity spring.
//   - Subtle green glow behind the video player.
//   - AVQueuePlayer + AVPlayerLooper for gapless looping.

import SwiftUI
import AVKit
import AVFoundation


// MARK: - Palette (mirrors CollageView)

private struct PreviewPalette {
    static let darkGreen  = Color(red: 0.13, green: 0.55, blue: 0.13)
    static let medGreen   = Color(red: 0.30, green: 0.70, blue: 0.30)
    static let lightGreen = Color(red: 0.40, green: 0.80, blue: 0.40)

    static let primaryGradient = LinearGradient(
        colors: [medGreen, darkGreen],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let secondaryGradient = LinearGradient(
        colors: [Color(.systemGray4), Color(.systemGray3)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}


struct VideoPreviewView: View {

    let videoURL: URL
    let onSaveToPhotos: () -> Void
    let onShare: () -> Void
    let onRegenerate: () -> Void
    let onDismiss: () -> Void

    /// Whether save-to-photos is in progress (passed from ViewModel).
    let isSaving: Bool

    // MARK: - Player state

    @State private var queuePlayer: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?

    // MARK: - Appearance animation

    @State private var appeared = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Full-screen dark background
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Close button ──
                HStack {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // ── Celebratory header ──
                Text("Your video is ready! 🎬")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.15), value: appeared)

                Spacer()

                // ── Video player ──
                if let player = queuePlayer {
                    VideoPlayer(player: player)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: PreviewPalette.darkGreen.opacity(0.25), radius: 20, x: 0, y: 0)
                        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
                        .padding(.horizontal, 24)
                        .scaleEffect(appeared ? 1.0 : 0.9)
                        .opacity(appeared ? 1.0 : 0.0)
                        .animation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.05), value: appeared)
                }

                Spacer()

                // ── Action buttons ──
                actionButtons
                    .padding(.bottom, 40)
                    .opacity(appeared ? 1.0 : 0.0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.2), value: appeared)
            }
        }
        .onAppear {
            setupLoopingPlayer()
            // Slight delay so the view is laid out before animating in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appeared = true
            }
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Save to Photos (primary – brand gradient)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSaveToPhotos()
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                        Text(isSaving ? "Saving..." : "Save")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(PreviewPalette.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: PreviewPalette.darkGreen.opacity(0.4), radius: 8, x: 0, y: 4)
                }
                .disabled(isSaving)

                // Share (secondary)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onShare()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(PreviewPalette.secondaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                }
            }

            // Regenerate (tertiary – green text link)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onRegenerate()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.subheadline.weight(.medium))
                    Text("Regenerate Video")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(PreviewPalette.lightGreen)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Player Lifecycle

    private func setupLoopingPlayer() {
        let playerItem = AVPlayerItem(url: videoURL)
        let queue = AVQueuePlayer(playerItem: playerItem)
        let looper = AVPlayerLooper(player: queue, templateItem: playerItem)

        self.queuePlayer  = queue
        self.playerLooper = looper

        queue.play()
    }

    private func tearDownPlayer() {
        queuePlayer?.pause()
        queuePlayer  = nil
        playerLooper = nil
    }
}
