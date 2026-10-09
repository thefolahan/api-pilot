import AppKit

let window = NSImage(contentsOfFile: CommandLine.arguments[1])!
let output = CommandLine.arguments[2]
let width: CGFloat = 1600
let height: CGFloat = 873

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

let background = CGGradient(colorsSpace: space, colors: [
    NSColor(red: 0.20, green: 0.17, blue: 0.55, alpha: 1).cgColor,
    NSColor(red: 0.06, green: 0.05, blue: 0.16, alpha: 1).cgColor
] as CFArray, locations: [0, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 0, y: height), end: CGPoint(x: 0, y: 0), options: [])

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat, tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .kern: tracking
    ]
    let string = NSAttributedString(string: text, attributes: attributes)
    let bounds = string.size()
    string.draw(at: CGPoint(x: (width - bounds.width) / 2, y: y))
}

draw("API Pilot", size: 92, weight: .bold, color: .white, y: height - 140, tracking: -3)
draw("Docs, requests, tests and a mock server, straight from your OpenAPI spec.", size: 30, weight: .regular,
     color: NSColor(white: 1, alpha: 0.68), y: height - 196)

let shotWidth: CGFloat = 1180
let shotHeight = shotWidth * window.size.height / window.size.width
window.draw(in: CGRect(x: (width - shotWidth) / 2, y: height - 238 - shotHeight, width: shotWidth, height: shotHeight))

let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.88])!
try! data.write(to: URL(fileURLWithPath: output))
