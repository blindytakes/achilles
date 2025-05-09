// PhotoLibraryService.swift
//
// This service provides the concrete implementation of the PhotoLibraryServiceProtocol,
// handling interactions with the device's photo library to retrieve media items.
//
// Key features:
// - Fetches media items from a specific date:
//   - Creates date predicates to find items from a given day
//   - Sorts results by creation date
//   - Converts PHAssets to app-specific MediaItem instances
// - Requests images from the photo library:
//   - Supports specific sizing and content mode options
//   - Returns PHImageRequestID for cancellation support
//   - Provides proper error handling through Result type
//
// The service acts as the primary gateway between the app and the system's
// photo library, using PHCachingImageManager for efficient image retrieval
// and caching of requested images.


import Foundation
import Photos
import UIKit

class PhotoLibraryService: PhotoLibraryServiceProtocol {
    private let imageManager = PHCachingImageManager()

    func fetchItems(
        for date: Date,
        completion: @escaping (Result<[MediaItem], Error>) -> Void
    ) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return completion(.success([]))
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            argumentArray: [start, end]
        )
        options.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: true)
        ]

        let result = PHAsset.fetchAssets(with: options)
        var items = [MediaItem]()
        result.enumerateObjects { asset, _, _ in
            items.append(MediaItem(asset: asset))
        }
        completion(.success(items))
    }

        @discardableResult
        func requestImage(
            for item: MediaItem,
            targetSize: CGSize,
            contentMode: PHImageContentMode,
            options: PHImageRequestOptions? = nil,
            completion: @escaping (Result<UIImage, Error>) -> Void
        ) -> PHImageRequestID {
        

        let requestID = imageManager.requestImage(
            for: item.asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, info in
            if let img = image {
                completion(.success(img))
            } else if let error = info?[PHImageErrorKey] as? Error {
                completion(.failure(error))
            } else {
                let err = NSError(
                    domain: "PhotoLibraryService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Unknown image request error"]
                )
                completion(.failure(err))
            }
        }
        return requestID
    }
}

