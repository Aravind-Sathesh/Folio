import SwiftUI

@main
struct FolioApp: App {
    @State private var model: AppModel

    init() {
        let model = AppModel()
        // The unit tests run inside this app. They must never start watching the real Downloads and Documents.
        if !Self.isTestHost { model.start() }
        _model = State(initialValue: model)
    }

    // All windows are AppKit windows owned by AppModel; SwiftUI just needs one scene.
    var body: some Scene {
        SwiftUI.Settings { EmptyView() }
    }

    private static var isTestHost: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }
}
