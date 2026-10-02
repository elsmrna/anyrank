#!/usr/bin/env swift
// Draws the AnyRank app icon ("Head to head": two cards, the front one
// checked) and writes the light, dark, and tinted 1024×1024 PNGs into
// AnyRank/Assets.xcassets/AppIcon.appiconset/.
//
// Usage: swift scripts/app-icon.swift
//
// Artwork is laid out on a 100-unit canvas, y pointing down. Colors come
// from Theme.swift. Icons are full-bleed and opaque; iOS applies the mask.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// How much larger than the 100-unit layout the artwork is drawn, around
/// its own center. Raise it for less empty space around the cards.
let artworkScale: CGFloat = 1.15

struct Palette {
    let background: UInt32
    let backCard: UInt32
    let frontCard: UInt32
    let check: UInt32
    let detailLine: UInt32
}

let variants: [(file: String, palette: Palette)] = [
    ("AppIcon.png", Palette(
        background: 0xA3622C, backCard: 0xD5B89E, frontCard: 0xF6F1E9, check: 0x4D5735, detailLine: 0xE8D8C6)),
    ("AppIcon-Dark.png", Palette(
        background: 0x1E1712, backCard: 0x7A5536, frontCard: 0xCC8249, check: 0xF3ECE2, detailLine: 0xA86E43)),
    ("AppIcon-Tinted.png", Palette(
        background: 0x000000, backCard: 0x757575, frontCard: 0xE8E8E8, check: 0x3A3A3A, detailLine: 0xABABAB)),
]

// Center of the two cards' combined bounds in the 100-unit layout, so
// scaling grows the artwork evenly instead of pushing it off-center.
let artworkCenter = CGPoint(x: 50.5, y: 49.5)

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// Runs `draw` with the context rotated `degrees` around `pivot`.
func rotated(_ ctx: CGContext, _ degrees: CGFloat, around pivot: CGPoint, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: pivot.x, y: pivot.y)
    ctx.rotate(by: degrees * .pi / 180)
    ctx.translateBy(x: -pivot.x, y: -pivot.y)
    draw()
    ctx.restoreGState()
}

func fillRoundedRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, _ fill: UInt32) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(color(fill))
    ctx.fillPath()
}

func drawIcon(_ palette: Palette, size: Int) -> CGImage {
    let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!

    // 100-unit canvas, y down.
    let unit = CGFloat(size) / 100
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: unit, y: -unit)

    ctx.setFillColor(color(palette.background))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))

    ctx.translateBy(x: 50, y: 50)
    ctx.scaleBy(x: artworkScale, y: artworkScale)
    ctx.translateBy(x: -artworkCenter.x, y: -artworkCenter.y)

    // Back card, tipped right.
    rotated(ctx, 12, around: CGPoint(x: 53, y: 48)) {
        fillRoundedRect(ctx, CGRect(x: 33, y: 22, width: 40, height: 52), radius: 8, palette.backCard)
    }

    // Front card, tipped left, with the check and a detail line.
    rotated(ctx, -6, around: CGPoint(x: 45, y: 52)) {
        fillRoundedRect(ctx, CGRect(x: 25, y: 26, width: 40, height: 52), radius: 8, palette.frontCard)

        ctx.move(to: CGPoint(x: 37, y: 44))
        ctx.addLine(to: CGPoint(x: 42.5, y: 49.5))
        ctx.addLine(to: CGPoint(x: 53, y: 38.5))
        ctx.setStrokeColor(color(palette.check))
        ctx.setLineWidth(5)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        fillRoundedRect(ctx, CGRect(x: 35, y: 59, width: 20, height: 5), radius: 2.5, palette.detailLine)
    }

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Couldn't write \(url.path)")
    }
}

let iconSet = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("AnyRank/Assets.xcassets/AppIcon.appiconset")

for variant in variants {
    let url = iconSet.appendingPathComponent(variant.file)
    writePNG(drawIcon(variant.palette, size: 1024), to: url)
    print("  \(url.path)")
}
