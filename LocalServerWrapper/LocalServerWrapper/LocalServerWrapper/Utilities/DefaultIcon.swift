import AppKit
import Foundation

enum DefaultIcon {
    static let resourceName = "DefaultAppIcon"

    static let resourceURL = Bundle.main.url(forResource: resourceName, withExtension: "icns")

    static let image = resourceURL.flatMap(NSImage.init(contentsOf:))
}
