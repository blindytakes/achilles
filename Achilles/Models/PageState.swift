// PageState.swift
//
// This enum defines the possible states of a page or view that loads and displays
// media content, providing a state machine approach to content presentation.
//
// Key features:
// - Represents all possible content loading states:
//   - idle: Initial state before loading begins
//   - loading: Active loading operation in progress
//   - loaded: Successfully retrieved content with optional featured item and grid items
//   - empty: Successfully completed loading but no content was found
//   - error: Loading failed with a specific error message
//
// The enum enables views to react appropriately to different loading states,
// showing loading indicators, content, empty states, or error messages based
// on the current state value. The associated values in the loaded and error
// cases provide the necessary data for rendering the appropriate UI.


import Foundation


enum PageState {
    case idle
    case loading
    case loaded(featured: MediaItem?, grid: [MediaItem]) // Holds prepared data
    case empty
    case error(message: String)
}
