import SwiftData
import SwiftUI

@main
struct PassPhotoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.dsTint)
        }
        .modelContainer(for: SavedPhoto.self)
    }
}
