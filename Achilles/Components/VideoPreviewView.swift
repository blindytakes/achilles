// VideoPreviewView.swift
//
// Inline video preview shown after a collage video export completes.
// Plays the exported video in a seamless loop with action buttons
// for Save to Photos, Share, and Regenerate.
//
// Uses AVQueuePlayer + AVPlayerLooper for gapless looping (no
// seek-to-start flicker).  Follows the same AVKit pattern as
// ItemDisplayView.swift, and the same visual language as CollageView:
//   - Dark background
//   - Spring animations
//   - Accent color for primary action
//   - Haptic feedback on taps

import SwiftUI
import AVKit
import AVFoundation


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

                Spacer()

                // ── Video player ──
                if let player = queuePlayer {
                    VideoPlayer(player: player)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
                        .padding(.horizontal, 24)
                }

                Spacer()

                // ── Action buttons ──
                actionButtons
                    .padding(.bottom, 40)
            }
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            setupLoopingPlayer()
            withAnimation(.easeOut(duration: 0.3)) {
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
            HStack(spacing: 16) {
                // Save to Photos (primary)
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
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 6, x: 0, y: 3)
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
                    .background(Color(.systemGray4))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 0, y: 3)
                }
            }

            // Regenerate (tertiary text link)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onRegenerate()
            } label: {
                Label("Regenerate Video", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
