import SwiftData
import SwiftUI

@main
struct PassPhotoApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var jar = TipJar()

    init() {
        // Screen titles in the accent navy, like the headings inside each screen.
        let navy = UIColor(Color.dsTint)
        let appearance = UINavigationBar.appearance()
        appearance.largeTitleTextAttributes = [.foregroundColor: navy]
        appearance.titleTextAttributes = [.foregroundColor: navy]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(.dsTint)
                // Navy ink for all text; views pick the accent or secondary level where they need it.
                .foregroundStyle(Color.dsInk)
                .environment(RequirementsUpdater.shared)
                .environment(jar)
                .task { await jar.store.loadProducts() }
        }
        .modelContainer(for: SavedPhoto.self)
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Requirements are checked at most once a day, when the app comes to the front.
            if phase == .active { Task { await RequirementsUpdater.shared.checkIfDue() } }
        }
    }
}
