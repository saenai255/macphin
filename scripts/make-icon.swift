import AppKit
import UniformTypeIdentifiers

enum IconError: Error {
    case contextUnavailable
    case gradientUnavailable
    case pngUnavailable
}

func makeIcon(pixelSize: Int) throws -> CGImage {
    let size = CGFloat(pixelSize)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: pixelSize, height: pixelSize, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw IconError.contextUnavailable
    }
    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    let inset = size * 0.1
    let square = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = square.width * 0.22
    let squarePath = CGPath(roundedRect: square, cornerWidth: corner, cornerHeight: corner, transform: nil)

    guard let gradient = CGGradient(colorsSpace: colorSpace,
                                    colors: [CGColor(srgbRed: 0.04, green: 0.15, blue: 0.42, alpha: 1),
                                             CGColor(srgbRed: 0.0, green: 0.58, blue: 0.61, alpha: 1)] as CFArray,
                                    locations: [0, 1]) else {
        throw IconError.gradientUnavailable
    }

    context.saveGState()
    context.addPath(squarePath)
    context.clip()
    context.drawLinearGradient(gradient,
                               start: CGPoint(x: square.midX, y: square.maxY),
                               end: CGPoint(x: square.midX, y: square.minY),
                               options: [])
    context.restoreGState()

    let folderWidth = size * 0.56
    let folderLeft = (size - folderWidth) / 2
    let bodyHeight = size * 0.34
    let bodyBottom = size * 0.3
    let bodyTop = bodyBottom + bodyHeight
    let bodyRadius = size * 0.025
    let tabHeight = size * 0.075
    let tabWidth = folderWidth * 0.42
    let tabRadius = size * 0.014

    let body = CGRect(x: folderLeft, y: bodyBottom, width: folderWidth, height: bodyHeight)
    let tab = CGRect(x: folderLeft, y: bodyTop - bodyRadius, width: tabWidth, height: tabHeight + bodyRadius)
    let folderPath = CGMutablePath()
    folderPath.addRoundedRect(in: tab, cornerWidth: tabRadius, cornerHeight: tabRadius)
    folderPath.addRoundedRect(in: body, cornerWidth: bodyRadius, cornerHeight: bodyRadius)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.04,
                      color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(folderPath)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()

    guard let image = context.makeImage() else { throw IconError.contextUnavailable }
    return image
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw IconError.pngUnavailable
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.pngUnavailable }
}

func bigEndianData(_ value: UInt32) -> Data {
    var bytes = value.bigEndian
    return Data(bytes: &bytes, count: 4)
}

func writeICNS(iconset: URL, to destination: URL) throws {
    let entries: [(type: String, file: String)] = [
        ("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"), ("ic12", "icon_32x32@2x.png"),
        ("ic13", "icon_128x128@2x.png"), ("ic14", "icon_256x256@2x.png"),
    ]
    var body = Data()
    for entry in entries {
        let png = try Data(contentsOf: iconset.appendingPathComponent(entry.file))
        body.append(Data(entry.type.utf8))
        body.append(bigEndianData(UInt32(png.count + 8)))
        body.append(png)
    }
    var file = Data("icns".utf8)
    file.append(bigEndianData(UInt32(body.count + 8)))
    file.append(body)
    try file.write(to: destination, options: .atomic)
}

func main() throws {
    let manager = FileManager.default
    let root = URL(fileURLWithPath: manager.currentDirectoryPath, isDirectory: true)
    let resources = root.appendingPathComponent("Resources", isDirectory: true)
    try manager.createDirectory(at: resources, withIntermediateDirectories: true)

    let iconset = manager.temporaryDirectory.appendingPathComponent("Macphin-\(UUID().uuidString).iconset",
                                                                     isDirectory: true)
    try manager.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: iconset) }

    let variants: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]

    for variant in variants {
        let image = try makeIcon(pixelSize: variant.pixels)
        try writePNG(image, to: iconset.appendingPathComponent(variant.name))
    }

    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    let output = resources.appendingPathComponent("AppIcon.icns")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    if iconutil.terminationStatus != 0 {
        try? manager.removeItem(at: output)
        try writeICNS(iconset: iconset, to: output)
    }
    print("Wrote Resources/AppIcon.icns")
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("make-icon failed: \(error)\n".utf8))
    exit(1)
}
