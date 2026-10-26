// Genera el icono de la app: un libro abierto dorado con un destello, sobre fondo verde tinta.
// Uso: swift Tools/make_icon.swift <carpeta AppIcon.appiconset>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "."
let size: CGFloat = 1024

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.scaleBy(x: CGFloat(pixels) / size, y: CGFloat(pixels) / size)

    // Fondo
    let space = CGColorSpaceCreateDeviceRGB()
    let background = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.13, green: 0.25, blue: 0.24, alpha: 1),
        CGColor(red: 0.04, green: 0.09, blue: 0.09, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(background, startCenter: CGPoint(x: size / 2, y: size * 0.62), startRadius: 0,
                          endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size * 0.75, options: [.drawsAfterEndLocation])

    let gold = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.98, green: 0.84, blue: 0.52, alpha: 1),
        CGColor(red: 0.80, green: 0.56, blue: 0.22, alpha: 1),
    ] as CFArray, locations: [0, 1])!

    // Páginas del libro abierto
    func page(mirrored: Bool) -> CGPath {
        let path = CGMutablePath()
        let spine = CGPoint(x: size / 2, y: size * 0.30)
        let sign: CGFloat = mirrored ? -1 : 1
        path.move(to: spine)
        path.addCurve(to: CGPoint(x: size / 2 + sign * size * 0.34, y: size * 0.36),
                      control1: CGPoint(x: size / 2 + sign * size * 0.10, y: size * 0.25),
                      control2: CGPoint(x: size / 2 + sign * size * 0.24, y: size * 0.30))
        path.addLine(to: CGPoint(x: size / 2 + sign * size * 0.34, y: size * 0.62))
        path.addCurve(to: CGPoint(x: size / 2, y: size * 0.58),
                      control1: CGPoint(x: size / 2 + sign * size * 0.24, y: size * 0.57),
                      control2: CGPoint(x: size / 2 + sign * size * 0.10, y: size * 0.53))
        path.closeSubpath()
        return path
    }
    for mirrored in [false, true] {
        cg.saveGState()
        cg.addPath(page(mirrored: mirrored))
        cg.clip()
        cg.drawLinearGradient(gold, start: CGPoint(x: 0, y: size * 0.65), end: CGPoint(x: 0, y: size * 0.25), options: [])
        cg.restoreGState()
    }
    // Líneas de texto
    cg.setStrokeColor(CGColor(red: 0.45, green: 0.29, blue: 0.10, alpha: 0.55))
    cg.setLineWidth(size * 0.012)
    cg.setLineCap(.round)
    for row in 0..<4 {
        let y = size * (0.50 - CGFloat(row) * 0.045)
        for sign: CGFloat in [-1, 1] {
            cg.move(to: CGPoint(x: size / 2 + sign * size * 0.07, y: y - size * 0.012))
            cg.addCurve(to: CGPoint(x: size / 2 + sign * size * 0.27, y: y + size * 0.012),
                        control1: CGPoint(x: size / 2 + sign * size * 0.14, y: y - size * 0.03),
                        control2: CGPoint(x: size / 2 + sign * size * 0.21, y: y))
        }
    }
    cg.strokePath()

    // Destello de guía sobre el libro
    let star = CGMutablePath()
    let center = CGPoint(x: size / 2, y: size * 0.76)
    let long = size * 0.12, short = size * 0.028
    star.move(to: CGPoint(x: center.x, y: center.y + long))
    star.addQuadCurve(to: CGPoint(x: center.x + long, y: center.y), control: CGPoint(x: center.x + short, y: center.y + short))
    star.addQuadCurve(to: CGPoint(x: center.x, y: center.y - long), control: CGPoint(x: center.x + short, y: center.y - short))
    star.addQuadCurve(to: CGPoint(x: center.x - long, y: center.y), control: CGPoint(x: center.x - short, y: center.y - short))
    star.addQuadCurve(to: CGPoint(x: center.x, y: center.y + long), control: CGPoint(x: center.x - short, y: center.y + short))
    cg.setShadow(offset: .zero, blur: size * 0.05, color: CGColor(red: 1, green: 0.85, blue: 0.5, alpha: 0.8))
    cg.addPath(star)
    cg.setFillColor(CGColor(red: 1, green: 0.93, blue: 0.75, alpha: 1))
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
try render(1024).write(to: URL(fileURLWithPath: "\(output)/icon-ios-1024.png"))
images.append(["idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "icon-ios-1024.png"])
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon-mac-\(base)@\(scale)x.png"
        try render(base * scale).write(to: URL(fileURLWithPath: "\(output)/\(name)"))
        images.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: "\(output)/Contents.json"))
print("Icono generado en \(output)")
