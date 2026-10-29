import Foundation

enum CameraMediaDetector {
    // Check only established root-level media structures. Do not enumerate or
    // record filenames, subdirectories, or file contents.
    private static let rootDirectoryMarkers = [
        "DCIM",
        "PRIVATE",
        "CONTENTS",
        "AVCHD",
        "XDROOT",
    ]

    static func detect(at mountPoint: String, fileManager: FileManager = .default) -> Bool {
        rootDirectoryMarkers.contains { marker in
            var isDirectory: ObjCBool = false
            let url = URL(fileURLWithPath: mountPoint, isDirectory: true)
                .appendingPathComponent(marker, isDirectory: true)
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }
}
