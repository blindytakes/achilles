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
