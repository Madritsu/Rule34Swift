import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: SetDMGApplicationsIcon.swift <alias-path>\n", stderr)
    exit(2)
}

let iconSize = NSSize(width: 512, height: 512)
let icon = NSImage(size: iconSize)
icon.lockFocus()

let folderTab = NSBezierPath(
    roundedRect: NSRect(x: 70, y: 315, width: 230, height: 100),
    xRadius: 30,
    yRadius: 30
)
NSColor(calibratedRed: 0.37, green: 0.78, blue: 0.49, alpha: 1).setFill()
folderTab.fill()

let folderBody = NSBezierPath(
    roundedRect: NSRect(x: 42, y: 88, width: 428, height: 300),
    xRadius: 48,
    yRadius: 48
)
NSColor(calibratedRed: 0.12, green: 0.53, blue: 0.30, alpha: 1).setFill()
folderBody.fill()

NSColor(calibratedWhite: 1, alpha: 0.24).setStroke()
folderBody.lineWidth = 8
folderBody.stroke()

let gridOrigin = NSPoint(x: 193, y: 190)
let squareSize: CGFloat = 46
let gap: CGFloat = 20
for row in 0..<2 {
    for column in 0..<2 {
        let square = NSBezierPath(
            roundedRect: NSRect(
                x: gridOrigin.x + CGFloat(column) * (squareSize + gap),
                y: gridOrigin.y + CGFloat(row) * (squareSize + gap),
                width: squareSize,
                height: squareSize
            ),
            xRadius: 11,
            yRadius: 11
        )
        NSColor(calibratedWhite: 1, alpha: 0.92).setFill()
        square.fill()
    }
}

icon.unlockFocus()

let aliasPath = CommandLine.arguments[1]
guard NSWorkspace.shared.setIcon(icon, forFile: aliasPath, options: []) else {
    fputs("Could not set custom Applications alias icon at \(aliasPath)\n", stderr)
    exit(1)
}
