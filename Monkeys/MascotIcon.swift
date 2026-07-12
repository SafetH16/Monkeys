// MascotIcon.swift
// MonKeys
//
// The MonKeys mark: a solid monkey-face silhouette (same visual language as
// the status bar icon — filled shapes, negative-space face) holding a
// keyring with two keycaps. Drawn in code as a template image: adapts to
// light/dark at any size, never animated, never colored inside menus.
// Fine details (smile, keychain holes) only appear at larger sizes; at menu
// size the mark stays clean solid shapes.

import Cocoa

enum MascotIcon {

    static func glyph(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width
            let detailed = s >= 28

            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: (cx - r) * s, y: (cy - r) * s,
                                            width: r * 2 * s, height: r * 2 * s))
            }
            func knockout(_ path: NSBezierPath) {
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                path.fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            }

            NSColor.black.setFill()
            NSColor.black.setStroke()

            // ── Head: ears, skull, negative-space face ──
            circle(0.09, 0.68, 0.10).fill()
            circle(0.71, 0.68, 0.10).fill()
            circle(0.40, 0.60, 0.27).fill()
            if detailed {
                knockout(circle(0.062, 0.695, 0.036))
                knockout(circle(0.738, 0.695, 0.036))
            }

            let face = NSBezierPath()
            face.append(circle(0.315, 0.665, 0.115))
            face.append(circle(0.485, 0.665, 0.115))
            face.append(NSBezierPath(ovalIn: NSRect(x: 0.23 * s, y: 0.40 * s,
                                                    width: 0.34 * s, height: 0.25 * s)))
            knockout(face)

            circle(0.325, 0.66, 0.032).fill()
            circle(0.475, 0.66, 0.032).fill()
            circle(0.368, 0.535, 0.015).fill()
            circle(0.432, 0.535, 0.015).fill()
            if detailed {
                let smile = NSBezierPath()
                smile.appendArc(withCenter: NSPoint(x: 0.40 * s, y: 0.525 * s),
                                radius: 0.062 * s, startAngle: 200, endAngle: 340)
                smile.lineWidth = 0.024 * s
                smile.lineCapStyle = .round
                smile.stroke()
            }

            // ── Keyring: cord from the head, donut ring, two hanging keycaps ──
            let cord = NSBezierPath()
            cord.move(to: NSPoint(x: 0.575 * s, y: 0.44 * s))
            cord.curve(to: NSPoint(x: 0.72 * s, y: 0.375 * s),
                       controlPoint1: NSPoint(x: 0.64 * s, y: 0.42 * s),
                       controlPoint2: NSPoint(x: 0.685 * s, y: 0.40 * s))
            cord.lineWidth = 0.038 * s
            cord.lineCapStyle = .round
            cord.stroke()

            circle(0.765, 0.315, 0.082).fill()
            knockout(circle(0.765, 0.315, 0.048))

            for (from, to) in [(NSPoint(x: 0.72, y: 0.26), NSPoint(x: 0.665, y: 0.20)),
                               (NSPoint(x: 0.81, y: 0.26), NSPoint(x: 0.862, y: 0.205))] {
                let link = NSBezierPath()
                link.move(to: NSPoint(x: from.x * s, y: from.y * s))
                link.line(to: NSPoint(x: to.x * s, y: to.y * s))
                link.lineWidth = 0.04 * s
                link.lineCapStyle = .round
                link.stroke()
            }

            func keycap(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, angle: CGFloat) {
                let t = NSAffineTransform()
                t.translateX(by: cx * s, yBy: cy * s)
                t.rotate(byDegrees: angle)

                let body = NSBezierPath(
                    roundedRect: NSRect(x: -w / 2 * s, y: -h / 2 * s, width: w * s, height: h * s),
                    xRadius: 0.045 * s, yRadius: 0.045 * s)
                body.transform(using: t as AffineTransform)
                body.fill()

                if detailed {
                    // Knocked-out top face: reads "keycap", not "hole".
                    let innerW = w - 0.075
                    let innerH = h - 0.085
                    let top = NSBezierPath(
                        roundedRect: NSRect(x: -innerW / 2 * s, y: (-innerH / 2 + 0.008) * s,
                                            width: innerW * s, height: innerH * s),
                        xRadius: 0.028 * s, yRadius: 0.028 * s)
                    top.transform(using: t as AffineTransform)
                    knockout(top)
                }
            }
            keycap(cx: 0.635, cy: 0.12, w: 0.21, h: 0.185, angle: -12)
            keycap(cx: 0.865, cy: 0.13, w: 0.19, h: 0.17, angle: 14)

            return true
        }
        img.isTemplate = true
        return img
    }
}
