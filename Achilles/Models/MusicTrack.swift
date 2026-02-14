// MusicTrack.swift
//
// Enum representing bundled background music tracks for video export.
//
// To add a new track:
//   1. Drop the .mp3 file into Resources/Music/
//   2. Add a new case here with matching filename (without extension)
//   3. Give it a displayName and iconName — that's it.
//
// The `.none` case means no background music (silent video).

import Foundation


enum MusicTrack: String, CaseIterable, Equatable, Identifiable {

    case none
    case atmospheric
    case dreamy

    var id: String { rawValue }

    /// Human-readable name shown in the music picker.
    var displayName: String {
        switch self {
        case .none:         return "No Music"
        case .atmospheric:  return "Atmospheric"
        case .dreamy:       return "Dreamy"
        }
    }

    /// SF Symbol for the picker chip.
    var iconName: String {
        switch self {
        case .none:         return "speaker.slash"
        case .atmospheric:  return "wind"
        case .dreamy:       return "moon.stars"
        }
    }

    /// The bundle URL for this track's audio file, or nil for `.none`.
    var url: URL? {
        switch self {
        case .none: return nil
        default:
            return Bundle.main.url(forResource: rawValue, withExtension: "mp3")
        }
    }

    /// All tracks that actually have audio (excludes `.none`).
    static var musicTracks: [MusicTrack] {
        allCases.filter { $0 != .none }
    }

    /// Pick a random default: 50% chance of a music track, 50% no music.
    static func randomDefault() -> MusicTrack {
        if Bool.random() {
            return musicTracks.randomElement() ?? .none
        } else {
            return .none
        }
    }

    /// Analytics label for telemetry.
    var analyticsLabel: String { rawValue }
}
