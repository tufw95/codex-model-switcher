import AppKit

@MainActor
enum BrandAssets {
    static let appIcon: NSImage = {
        load(name: "AppIcon", extension: "icns")
            ?? NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: "Codex Switch")
            ?? NSImage()
    }()

    static let menuBarIcon: NSImage = {
        let image = load(name: "MenuBarIcon", extension: "png")
            ?? NSImage(systemSymbolName: "arrow.triangle.swap", accessibilityDescription: "Codex Switch")
            ?? NSImage()
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()

    private static func load(name: String, extension fileExtension: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
