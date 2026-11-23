import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: SetDMGApplicationsIcon.swift <alias-path>\n", stderr)
    exit(2)
}

let iconSize = NSSize(width: 512, height: 512)
let icon = NSWorkspace.shared.icon(forFile: "/Applications")
icon.size = iconSize
icon.lockFocus()
NSColor(calibratedRed: 0.20, green: 0.76, blue: 0.36, alpha: 0.58).setFill()
NSGraphicsContext.current?.compositingOperation = .sourceAtop
NSBezierPath(rect: NSRect(origin: .zero, size: iconSize)).fill()
NSGraphicsContext.current?.compositingOperation = .sourceOver
icon.unlockFocus()

let aliasPath = CommandLine.arguments[1]
guard NSWorkspace.shared.setIcon(icon, forFile: aliasPath, options: []) else {
    fputs("Could not set custom Applications alias icon at \(aliasPath)\n", stderr)
    exit(1)
}
