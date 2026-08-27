import AppKit

// Render a 1024x1024 app icon: rounded-rect gradient background + clock face.
let size = CGFloat(1024)
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext

// macOS-style rounded rect with margin
let margin = size * 0.09
let rect = CGRect(x: margin, y: margin, width: size - 2*margin, height: size - 2*margin)
let path = CGPath(roundedRect: rect, cornerWidth: size * 0.18, cornerHeight: size * 0.18, transform: nil)
ctx.addPath(path)
ctx.clip()

// Blue gradient background
let colors = [NSColor(calibratedRed: 0.14, green: 0.42, blue: 0.95, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.60, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: size/2, y: size), end: CGPoint(x: size/2, y: 0), options: [])

// Clock face
let center = CGPoint(x: size/2, y: size/2)
let radius = size * 0.30
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius*2, height: radius*2))

// Tick marks
ctx.setStrokeColor(NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.60, alpha: 1).cgColor)
for i in 0..<12 {
    let angle = CGFloat(i) * .pi / 6
    let outer = CGPoint(x: center.x + cos(angle) * radius * 0.88, y: center.y + sin(angle) * radius * 0.88)
    let inner = CGPoint(x: center.x + cos(angle) * radius * (i % 3 == 0 ? 0.72 : 0.80),
                        y: center.y + sin(angle) * radius * (i % 3 == 0 ? 0.72 : 0.80))
    ctx.setLineWidth(size * (i % 3 == 0 ? 0.018 : 0.010))
    ctx.setLineCap(.round)
    ctx.move(to: inner); ctx.addLine(to: outer); ctx.strokePath()
}

// Hands: 10:09 classic watch pose
ctx.setLineCap(.round)
ctx.setLineWidth(size * 0.028)
let hourAngle = CGFloat.pi * (0.5 + 2.0/3.0 * 0.55)
ctx.move(to: center)
ctx.addLine(to: CGPoint(x: center.x + cos(hourAngle) * radius * 0.45, y: center.y + sin(hourAngle) * radius * 0.45))
ctx.strokePath()
ctx.setLineWidth(size * 0.020)
let minAngle = CGFloat.pi * 0.20
ctx.move(to: center)
ctx.addLine(to: CGPoint(x: center.x + cos(minAngle) * radius * 0.68, y: center.y + sin(minAngle) * radius * 0.68))
ctx.strokePath()

// Center dot
ctx.setFillColor(NSColor(calibratedRed: 0.05, green: 0.22, blue: 0.60, alpha: 1).cgColor)
ctx.fillEllipse(in: CGRect(x: center.x - size*0.022, y: center.y - size*0.022, width: size*0.044, height: size*0.044))

image.unlockFocus()

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
