import Foundation
import Photos
import UIKit 

protocol PhotoLibraryServiceProtocol {
    /// Fetch all media items for a specific day.
    func fetchItems(
        for date: Date,
        completion: @escaping (Result<[MediaItem], Error>) -> Void
    )

    /// Request a UIImage for the given item at a target size.
    /// Returns the PHImageRequestID if you need to cancel.
    @discardableResult
    func requestImage(
        for item: MediaItem,
        targetSize: CGSize,
        contentMode: PHImageContentMode,
        options: PHImageRequestOptions?,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) -> PHImageRequestID
}
