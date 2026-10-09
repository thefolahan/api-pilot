import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    NSColor(red: r, green: g, blue: b, alpha: a).cgColor
}

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0, 0, 0, 0.3))
context.addPath(tilePath)
context.setFillColor(rgb(0.2, 0.2, 0.3))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tilePath)
context.clip()
let background = CGGradient(colorsSpace: space, colors: [rgb(0.36, 0.33, 0.95), rgb(0.16, 0.12, 0.45)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
let glow = CGGradient(colorsSpace: space, colors: [rgb(1, 1, 1, 0.22), rgb(1, 1, 1, 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 860), startRadius: 0, endCenter: CGPoint(x: 330, y: 860), endRadius: 620, options: [])
context.restoreGState()

let page = CGRect(x: 250, y: 215, width: 524, height: 600)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0.05, 0.02, 0.2, 0.45))
context.addPath(CGPath(roundedRect: page, cornerWidth: 54, cornerHeight: 54, transform: nil))
context.setFillColor(rgb(0.99, 0.99, 1))
context.fillPath()
context.restoreGState()

let rows: [(CGColor, CGFloat)] = [
    (rgb(0.13, 0.66, 0.38), 250),
    (rgb(0.93, 0.52, 0.10), 300),
    (rgb(0.18, 0.45, 0.95), 210),
    (rgb(0.89, 0.22, 0.22), 270)
]
for (index, row) in rows.enumerated() {
    let y = page.maxY - 128 - CGFloat(index) * 112
    context.addPath(CGPath(roundedRect: CGRect(x: page.minX + 62, y: y, width: 92, height: 50), cornerWidth: 16, cornerHeight: 16, transform: nil))
    context.setFillColor(row.0)
    context.fillPath()
    context.addPath(CGPath(roundedRect: CGRect(x: page.minX + 182, y: y + 8, width: row.1, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil))
    context.setFillColor(rgb(0.80, 0.81, 0.90))
    context.fillPath()
}

let seal = CGPoint(x: 726, y: 262)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0.05, 0.02, 0.2, 0.4))
context.addEllipse(in: CGRect(x: seal.x - 118, y: seal.y - 118, width: 236, height: 236))
context.setFillColor(rgb(0.13, 0.70, 0.42))
context.fillPath()
context.restoreGState()
context.setStrokeColor(rgb(1, 1, 1))
context.setLineWidth(30)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: seal.x - 54, y: seal.y + 2))
context.addLine(to: CGPoint(x: seal.x - 14, y: seal.y - 40))
context.addLine(to: CGPoint(x: seal.x + 58, y: seal.y + 44))
context.strokePath()

let data = bitmap.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: output))
