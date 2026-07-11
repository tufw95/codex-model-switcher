#!/usr/bin/env swift

import AppKit
import Foundation

private let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let assets = root.appendingPathComponent("Assets", isDirectory: true)
private let temporary = FileManager.default.temporaryDirectory

private func savePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

private func withCanvas(
    size: NSSize,
    opaque: Bool = false,
    draw: () -> Void
) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    if !opaque {
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
    }
    draw()
    image.unlockFocus()
    return image
}

private func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw CocoaError(.executableRuntimeMismatch)
    }
}

private func point(_ x: CGFloat, _ y: CGFloat, scale: CGFloat) -> NSPoint {
    NSPoint(x: x * scale, y: y * scale)
}

private func drawSwitchMark(
    in rect: NSRect,
    mint: NSColor,
    coral: NSColor,
    underlay: NSColor? = nil
) {
    let scale = min(rect.width, rect.height) / 1024
    let origin = rect.origin

    func translated(_ p: NSPoint) -> NSPoint {
        NSPoint(x: origin.x + p.x, y: origin.y + p.y)
    }

    func lane(
        start: NSPoint,
        control1: NSPoint,
        control2: NSPoint,
        end: NSPoint,
        color: NSColor,
        width: CGFloat
    ) {
        let path = NSBezierPath()
        path.move(to: translated(start))
        path.curve(
            to: translated(end),
            controlPoint1: translated(control1),
            controlPoint2: translated(control2)
        )
        path.lineWidth = width * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        if let underlay {
            underlay.setStroke()
            path.lineWidth = (width + 34) * scale
            path.stroke()
            path.lineWidth = width * scale
        }

        color.setStroke()
        path.stroke()
    }

    let upperStart = point(232, 668, scale: scale)
    let upperC1 = point(388, 668, scale: scale)
    let upperC2 = point(524, 360, scale: scale)
    let upperEnd = point(730, 360, scale: scale)

    let lowerStart = point(232, 356, scale: scale)
    let lowerC1 = point(414, 356, scale: scale)
    let lowerC2 = point(512, 664, scale: scale)
    let lowerEnd = point(730, 664, scale: scale)

    lane(
        start: upperStart,
        control1: upperC1,
        control2: upperC2,
        end: upperEnd,
        color: mint,
        width: 106
    )
    lane(
        start: lowerStart,
        control1: lowerC1,
        control2: lowerC2,
        end: lowerEnd,
        color: coral,
        width: 106
    )

    func arrowTip(at center: NSPoint, color: NSColor) {
        let x = origin.x + center.x
        let y = origin.y + center.y
        let half = 76 * scale
        let depth = 116 * scale
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x - depth / 2, y: y - half))
        path.line(to: NSPoint(x: x - depth / 2, y: y + half))
        path.line(to: NSPoint(x: x + depth / 2, y: y))
        path.close()
        color.setFill()
        path.fill()
    }

    arrowTip(at: point(790, 360, scale: scale), color: mint)
    arrowTip(at: point(790, 664, scale: scale), color: coral)

    let junctionRect = NSRect(
        x: origin.x + 471 * scale,
        y: origin.y + 471 * scale,
        width: 82 * scale,
        height: 82 * scale
    )
    let junction = NSBezierPath(ovalIn: junctionRect)
    NSColor(calibratedWhite: 0.07, alpha: 0.95).setFill()
    junction.fill()
    NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
    junction.lineWidth = 6 * scale
    junction.stroke()
}

private func makeAppIcon() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    return withCanvas(size: size) {
        let tile = NSRect(x: 42, y: 42, width: 940, height: 940)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 224, yRadius: 224)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.42)
        shadow.shadowBlurRadius = 44
        shadow.shadowOffset = NSSize(width: 0, height: -18)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.black.setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        let background = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.18, alpha: 1), 0.0),
            (NSColor(calibratedRed: 0.055, green: 0.062, blue: 0.075, alpha: 1), 0.72),
            (NSColor(calibratedRed: 0.025, green: 0.028, blue: 0.036, alpha: 1), 1.0)
        )
        background?.draw(in: tile, angle: 90)

        let glow = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.43, green: 1.0, blue: 0.73, alpha: 0.18), 0.0),
            (NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.35, alpha: 0.08), 0.48),
            (NSColor.clear, 1.0)
        )
        glow?.draw(
            fromCenter: NSPoint(x: 380, y: 720),
            radius: 0,
            toCenter: NSPoint(x: 512, y: 512),
            radius: 650,
            options: [.drawsAfterEndingLocation]
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.16).setStroke()
        tilePath.lineWidth = 8
        tilePath.stroke()

        drawSwitchMark(
            in: NSRect(x: 0, y: 0, width: 1024, height: 1024),
            mint: NSColor(calibratedRed: 0.40, green: 0.98, blue: 0.70, alpha: 1),
            coral: NSColor(calibratedRed: 1.0, green: 0.39, blue: 0.37, alpha: 1),
            underlay: NSColor.black.withAlphaComponent(0.30)
        )
    }
}

private func makeMenuBarIcon() -> NSImage {
    let size = NSSize(width: 64, height: 64)
    return withCanvas(size: size) {
        drawSwitchMark(
            in: NSRect(x: 0, y: 0, width: 64, height: 64),
            mint: .black,
            coral: .black
        )
    }
}

try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
let sourceURL = temporary.appendingPathComponent("CodexModelSwitcher-AppIconSource.png")
let iconsetURL = temporary.appendingPathComponent("CodexModelSwitcher.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: sourceURL)
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

try savePNG(makeAppIcon(), to: sourceURL)
try savePNG(makeMenuBarIcon(), to: assets.appendingPathComponent("MenuBarIcon.png"))

let iconSizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (size, name) in iconSizes {
    try run("/usr/bin/sips", [
        "-z", "\(size)", "\(size)",
        sourceURL.path,
        "--out", iconsetURL.appendingPathComponent(name).path
    ])
}

try run("/usr/bin/iconutil", [
    "-c", "icns",
    iconsetURL.path,
    "-o", assets.appendingPathComponent("AppIcon.icns").path
])

try? FileManager.default.removeItem(at: sourceURL)
try? FileManager.default.removeItem(at: iconsetURL)

print("Generated AppIcon.icns and MenuBarIcon.png")
