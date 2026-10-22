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
                                    colors: [CGColor(srgbRed: 0.05, green: 0.2, blue: 0.5, alpha: 1),
                                             CGColor(srgbRed: 0.0, green: 0.62, blue: 0.72, alpha: 1)] as CFArray,
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

    context.saveGState()
    context.addPath(squarePath)
    context.clip()
    drawWaves(in: context, square: square)
    drawFolder(in: context, size: size)
    drawDolphin(in: context, size: size)
    context.restoreGState()

    guard let image = context.makeImage() else { throw IconError.contextUnavailable }
    return image
}

func drawWaves(in context: CGContext, square: CGRect) {
    let size = square.width
    for (index, alpha) in [0.12, 0.2].enumerated() {
        let base = square.minY + size * (0.2 - CGFloat(index) * 0.08)
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: square.minX, y: base))
        let segments = 4
        let step = square.width / CGFloat(segments)
        for segment in 0..<segments {
            let x = square.minX + CGFloat(segment) * step
            let lift = size * (index == 0 ? 0.03 : -0.03)
            wave.addCurve(to: CGPoint(x: x + step, y: base),
                          control1: CGPoint(x: x + step * 0.3, y: base + lift),
                          control2: CGPoint(x: x + step * 0.7, y: base - lift))
        }
        wave.addLine(to: CGPoint(x: square.maxX, y: square.minY))
        wave.addLine(to: CGPoint(x: square.minX, y: square.minY))
        wave.closeSubpath()
        context.addPath(wave)
        context.setFillColor(CGColor(gray: 1, alpha: alpha))
        context.fillPath()
    }
}

func drawFolder(in context: CGContext, size: CGFloat) {
    let width = size * 0.58
    let left = (size - width) / 2
    let bottom = size * 0.2
    let height = size * 0.34
    let radius = size * 0.03

    let back = CGMutablePath()
    let tabWidth = width * 0.4
    let tabHeight = size * 0.06
    let top = bottom + height
    back.move(to: CGPoint(x: left, y: bottom + radius))
    back.addLine(to: CGPoint(x: left, y: top + tabHeight - radius))
    back.addQuadCurve(to: CGPoint(x: left + radius, y: top + tabHeight), control: CGPoint(x: left, y: top + tabHeight))
    back.addLine(to: CGPoint(x: left + tabWidth - radius, y: top + tabHeight))
    back.addQuadCurve(to: CGPoint(x: left + tabWidth + tabHeight * 0.6, y: top), control: CGPoint(x: left + tabWidth, y: top + tabHeight))
    back.addLine(to: CGPoint(x: left + width - radius, y: top))
    back.addQuadCurve(to: CGPoint(x: left + width, y: top - radius), control: CGPoint(x: left + width, y: top))
    back.addLine(to: CGPoint(x: left + width, y: bottom + radius))
    back.addQuadCurve(to: CGPoint(x: left + width - radius, y: bottom), control: CGPoint(x: left + width, y: bottom))
    back.addLine(to: CGPoint(x: left + radius, y: bottom))
    back.addQuadCurve(to: CGPoint(x: left, y: bottom + radius), control: CGPoint(x: left, y: bottom))
    back.closeSubpath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.04, color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(back)
    context.setFillColor(CGColor(srgbRed: 0.62, green: 0.86, blue: 0.98, alpha: 1))
    context.fillPath()
    context.restoreGState()

    let front = CGRect(x: left, y: bottom, width: width, height: height * 0.84)
    let frontPath = CGPath(roundedRect: front, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: size * 0.006), blur: size * 0.02, color: CGColor(gray: 0, alpha: 0.18))
    context.addPath(frontPath)
    context.setFillColor(CGColor(srgbRed: 0.86, green: 0.96, blue: 1, alpha: 1))
    context.fillPath()
    context.restoreGState()
}

func dolphinPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0.5, y: -0.04))
    path.addCurve(to: CGPoint(x: 0.39, y: 0.0), control1: CGPoint(x: 0.47, y: -0.02), control2: CGPoint(x: 0.42, y: -0.01))
    path.addCurve(to: CGPoint(x: 0.28, y: 0.11), control1: CGPoint(x: 0.37, y: 0.07), control2: CGPoint(x: 0.33, y: 0.1))
    path.addCurve(to: CGPoint(x: 0.02, y: 0.16), control1: CGPoint(x: 0.2, y: 0.15), control2: CGPoint(x: 0.1, y: 0.17))
    path.addCurve(to: CGPoint(x: -0.13, y: 0.27), control1: CGPoint(x: -0.03, y: 0.21), control2: CGPoint(x: -0.08, y: 0.26))
    path.addCurve(to: CGPoint(x: -0.1, y: 0.13), control1: CGPoint(x: -0.11, y: 0.22), control2: CGPoint(x: -0.11, y: 0.17))
    path.addCurve(to: CGPoint(x: -0.38, y: -0.03), control1: CGPoint(x: -0.22, y: 0.1), control2: CGPoint(x: -0.32, y: 0.03))
    path.addCurve(to: CGPoint(x: -0.55, y: 0.0), control1: CGPoint(x: -0.44, y: -0.01), control2: CGPoint(x: -0.5, y: 0.01))
    path.addCurve(to: CGPoint(x: -0.45, y: -0.09), control1: CGPoint(x: -0.51, y: -0.03), control2: CGPoint(x: -0.47, y: -0.06))
    path.addCurve(to: CGPoint(x: -0.49, y: -0.24), control1: CGPoint(x: -0.45, y: -0.14), control2: CGPoint(x: -0.47, y: -0.2))
    path.addCurve(to: CGPoint(x: -0.37, y: -0.09), control1: CGPoint(x: -0.43, y: -0.19), control2: CGPoint(x: -0.39, y: -0.13))
    path.addCurve(to: CGPoint(x: 0.06, y: -0.05), control1: CGPoint(x: -0.23, y: -0.03), control2: CGPoint(x: -0.08, y: -0.03))
    path.addCurve(to: CGPoint(x: 0.0, y: -0.17), control1: CGPoint(x: 0.05, y: -0.09), control2: CGPoint(x: 0.03, y: -0.14))
    path.addCurve(to: CGPoint(x: 0.15, y: -0.06), control1: CGPoint(x: 0.07, y: -0.15), control2: CGPoint(x: 0.12, y: -0.1))
    path.addCurve(to: CGPoint(x: 0.39, y: -0.05), control1: CGPoint(x: 0.24, y: -0.07), control2: CGPoint(x: 0.32, y: -0.06))
    path.addCurve(to: CGPoint(x: 0.5, y: -0.04), control1: CGPoint(x: 0.44, y: -0.05), control2: CGPoint(x: 0.47, y: -0.05))
    path.closeSubpath()
    return path
}

func drawDolphin(in context: CGContext, size: CGFloat) {
    let transform = CGAffineTransform(translationX: size * 0.5, y: size * 0.66)
        .rotated(by: .pi * 0.06)
        .scaledBy(x: size * 0.6, y: size * 0.6)
    var pathTransform = transform
    guard let dolphin = dolphinPath().copy(using: &pathTransform),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let shading = CGGradient(colorsSpace: colorSpace,
                                   colors: [CGColor(srgbRed: 0.33, green: 0.47, blue: 0.66, alpha: 1),
                                            CGColor(srgbRed: 0.62, green: 0.75, blue: 0.88, alpha: 1),
                                            CGColor(srgbRed: 0.94, green: 0.97, blue: 1, alpha: 1)] as CFArray,
                                   locations: [0, 0.55, 1]) else { return }
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.035, color: CGColor(gray: 0, alpha: 0.4))
    context.beginTransparencyLayer(auxiliaryInfo: nil)
    context.addPath(dolphin)
    context.clip()
    context.drawLinearGradient(shading,
                               start: CGPoint(x: 0, y: 0.2).applying(transform),
                               end: CGPoint(x: 0, y: -0.12).applying(transform),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.endTransparencyLayer()
    context.restoreGState()

    let eye = CGPoint(x: 0.31, y: 0.04).applying(transform)
    let eyeRadius = size * 0.012
    context.setFillColor(CGColor(srgbRed: 0.05, green: 0.15, blue: 0.3, alpha: 1))
    context.fillEllipse(in: CGRect(x: eye.x - eyeRadius, y: eye.y - eyeRadius, width: eyeRadius * 2, height: eyeRadius * 2))
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
