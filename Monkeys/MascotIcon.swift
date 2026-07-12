// MascotIcon.swift
// MonKeys
//
// The MonKeys accessory glyph: a line-art monkey face holding a small
// keyring of keycaps (monkey + keys — the name, drawn). Rendered in code as
// a template image so it adapts to light/dark menus at any size.
// Rules: never animated, never colored inside menus, details drop out
// gracefully at small sizes instead of getting bolder.

import Cocoa

enum MascotIcon {

    static func glyph(size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let s = rect.width
            let line = max(s * 0.075, 1.0)

            func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath {
                NSBezierPath(ovalIn: NSRect(x: (cx - r) * s, y: (cy - r) * s,
                                            width: r * 2 * s, height: r * 2 * s))
            }
            func stroke(_ path: NSBezierPath, width: CGFloat) {
                path.lineWidth = width
                path.lineCapStyle = .round
                path.stroke()
            }

            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Ears, then head
            stroke(circle(0.14, 0.68, 0.085), width: line)
            stroke(circle(0.66, 0.68, 0.085), width: line)
            stroke(circle(0.40, 0.62, 0.24), width: line)

            // Eyes + muzzle
            circle(0.325, 0.68, 0.032).fill()
            circle(0.475, 0.68, 0.032).fill()
            stroke(NSBezierPath(ovalIn: NSRect(x: 0.29 * s, y: 0.455 * s,
                                               width: 0.22 * s, height: 0.13 * s)),
                   width: line * 0.9)

            // Keyring with two keycaps, slightly quieter than the face
            NSColor.black.withAlphaComponent(0.72).setStroke()
            stroke(circle(0.76, 0.30, 0.07), width: line)

            let link1 = NSBezierPath()
            link1.move(to: NSPoint(x: 0.72 * s, y: 0.245 * s))
            link1.line(to: NSPoint(x: 0.685 * s, y: 0.185 * s))
            stroke(link1, width: line * 0.8)
            let link2 = NSBezierPath()
            link2.move(to: NSPoint(x: 0.80 * s, y: 0.245 * s))
            link2.line(to: NSPoint(x: 0.865 * s, y: 0.195 * s))
            stroke(link2, width: line * 0.8)

            for frame in [NSRect(x: 0.60 * s, y: 0.04 * s, width: 0.15 * s, height: 0.14 * s),
                          NSRect(x: 0.82 * s, y: 0.055 * s, width: 0.14 * s, height: 0.135 * s)] {
                stroke(NSBezierPath(roundedRect: frame, xRadius: 0.03 * s, yRadius: 0.03 * s),
                       width: line * 0.9)
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
