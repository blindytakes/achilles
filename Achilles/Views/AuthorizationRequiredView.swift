//  A SwiftUI view that presents a user-friendly interface whenever
//  the app lacks sufficient Photo Library permissions. It displays
//  an icon, title, explanatory text, and context-appropriate action
//  buttons for each `PHAuthorizationStatus` case:
//
//    • .notDetermined   — prompts the user to grant access
//    • .denied/.restricted — directs the user to Settings to re-enable access
//    • .limited         — warns of limited access and offers Settings link
//    • .authorized      — (fallback) shows a brief “Checking permissions…” message
//
//  Usage:
//    Pass in the current `PHAuthorizationStatus` and an `onRequest`
//    closure that triggers `PHPhotoLibrary.requestAuthorization` or
//    equivalent logic in your ViewModel.


import SwiftUI
import Photos // Needed for PHAuthorizationStatus

struct AuthorizationRequiredView: View {
    let status: PHAuthorizationStatus
    let onRequest: () -> Void // Action to trigger request/check

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled") // Relevant icon
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)
                .foregroundColor(.secondary)

            Text("Photo Library Access Needed")
                .font(.title2)
                .fontWeight(.semibold)

            switch status {
            case .denied, .restricted:  
                Text("To see your photo memories, please grant access to your Photo Library in the Settings app.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                Button("Open Settings") {
                    // Deeplink to app's settings
                    if let url = URL(string: UIApplication.openSettingsURLString),
                       UIApplication.shared.canOpenURL(url) {
                         UIApplication.shared.open(url)
                     }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)

            case .notDetermined:
                Text("This app needs your permission to show photos and videos from previous years.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                 Button("Grant Access") {
                    onRequest() // Trigger the permission request logic in ViewModel
                 }
                 .buttonStyle(.borderedProminent)
                 .padding(.top)

            case .limited: // Handle limited access if needed
                 Text("Limited library access selected. Full access might be required for all features.")
                     .multilineTextAlignment(.center)
                     .foregroundColor(.secondary)
                 // Optionally add button to request full access again or go to settings
                 Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
                         UIApplication.shared.open(url)
                     }
                 }
                 .buttonStyle(.bordered)
                 .padding(.top)

            default: // .authorized or future cases
                // This view shouldn't technically be shown if status is .authorized
                Text("Checking permissions...")
                    .foregroundColor(.secondary)
            }
        }
        .padding(30) // Add ample padding around the content
    }
}

// You can add a PreviewProvider for easier designing if you like:
#Preview {
    // Example showing the 'denied' state
    AuthorizationRequiredView(status: .denied) {
        print("Request action triggered")
    }
}

#Preview {
    // Example showing the 'notDetermined' state
    AuthorizationRequiredView(status: .notDetermined) {
        print("Request action triggered")
    }
}
