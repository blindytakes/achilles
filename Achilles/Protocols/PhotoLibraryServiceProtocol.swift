// PhotoLibraryServiceProtocol.swift
//
// This protocol defines the interface for accessing and retrieving photos from the device's
// photo library, providing a consistent API for the app's photo-related functionality.
//
// Key features:
// - Defines core photo library access methods:
//   - Fetching media items from a specific date
//   - Requesting images with specific size and content mode options
// - Uses completion handler pattern with Result types for error handling
// - Supports cancellation through PHImageRequestID return values
//
// By abstracting photo library access through this protocol, the app can:
// - Mock photo library interactions for testing
// - Swap implementations without affecting dependent components
// - Provide consistent error handling patterns

import Foundation
import Photos
import UIKit 

protocol PhotoLibraryServiceProtocol {
    /// Fetch all media items for a specific day.
    func fetchItems(
        for date: Date,
        completion: @escaping (Result<[MediaItem], Error>) -> Void
    )

    @discardableResult
    func requestImage(
        for item: MediaItem,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) -> PHImageRequestID
}
