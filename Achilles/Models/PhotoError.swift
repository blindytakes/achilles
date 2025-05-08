// PhotoError.swift
//
// This enum defines a comprehensive set of error types that can occur during
// photo library operations, providing structured error handling throughout the app.
//
// Key features:
// - Categorizes photo-related errors into specific types:
//   - Authorization errors (denied, restricted, limited)
//   - Data retrieval errors (missing items, invalid URLs, corrupted data)
//   - Calculation errors for date-based operations
//   - Wrapper for underlying Photos framework errors
// - Implements LocalizedError protocol for user-friendly error messages
// - Supports optional detail parameters for improved debugging
//
// The enum enables consistent error handling across the app's photo operations,
// with proper localization support for user-facing error messages and
// sufficient detail for debugging and error reporting.
import Foundation

/// Errors that can occur during photo library operations within the Achilles app.
enum PhotoError: Error, LocalizedError {
    case authorizationDenied
    case authorizationRestricted
    case authorizationLimited // Maybe needed if limited is insufficient
    case dateCalculationError(details: String? = nil)
    case underlyingPhotoLibraryError(Error) // Wrap errors from Photos framework
    case itemNotFound(identifier: String? = nil)
    case videoURLError(details: String? = nil)
    case imageDataError(details: String? = nil)
    case unknown // Catch-all for unexpected issues

    // User-friendly descriptions
    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return NSLocalizedString("Photo library access was denied. Please grant access in Settings.", comment: "Error message")
        case .authorizationRestricted:
            return NSLocalizedString("Photo library access is restricted (e.g., by parental controls).", comment: "Error message")
        case .authorizationLimited:
             return NSLocalizedString("Limited photo library access is selected. Full access might be required.", comment: "Error message")
        case .dateCalculationError(let details):
            let base = NSLocalizedString("Internal error calculating a target date.", comment: "Error message")
            return details != nil ? "\(base) Details: \(details!)" : base
        case .underlyingPhotoLibraryError(let error):
            // Provide more context if possible, maybe check specific PHPhotoLibrary error codes
            return String(format: NSLocalizedString("An error occurred while accessing the photo library: %@", comment: "Error message wrapper"), error.localizedDescription)
        case .itemNotFound(let identifier):
             let base = NSLocalizedString("The requested photo item could not be found.", comment: "Error message")
             return identifier != nil ? "\(base) ID: \(identifier!)" : base
        case .videoURLError(let details):
             let base = NSLocalizedString("Could not retrieve the video URL.", comment: "Error message")
             return details != nil ? "\(base) Details: \(details!)" : base
        case .imageDataError(let details):
             let base = NSLocalizedString("Could not retrieve the image data.", comment: "Error message")
             return details != nil ? "\(base) Details: \(details!)" : base
        case .unknown:
            return NSLocalizedString("An unknown error occurred.", comment: "Error message")
        }
    }
}

