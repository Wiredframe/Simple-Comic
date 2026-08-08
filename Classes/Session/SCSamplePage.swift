//
//  SCSamplePage.swift
//  Simple Comic
//
//  A synthetic "comic page" — line art, greys, a gradient and a few colour swatches on
//  white — so the paper effect can be previewed while tuning it, without a file open.
//
//  Ported from the iOS app (PaperEffect/SamplePage.swift). Everything is drawn in fractions
//  of the canvas, so any size renders sensibly, and the content is chosen to exercise the
//  parts of the filter that are easy to get wrong: deep blacks for the show-through,
//  midtones and a gradient for the tonal remap, thin strokes for the grain, saturated ink
//  for the colour handling.
//

import AppKit

enum SCSamplePage {

	/// A cached preview-sized page. Redrawing it on every slider tick would be wasteful; the
	/// paper effect is applied to this bitmap, not to a fresh drawing.
	static let preview: NSImage = make()

	static func make(size: NSSize = NSSize(width: 620, height: 900)) -> NSImage {
		let image = NSImage(size: size)
		// Flipped, so the fractions below read top-down like the iOS original.
		image.lockFocusFlipped(true)
		defer { image.unlockFocus() }

		let w = size.width, h = size.height
		func rect(_ x: CGFloat, _ y: CGFloat, _ rw: CGFloat, _ rh: CGFloat) -> NSRect {
			NSRect(x: x * w, y: y * h, width: rw * w, height: rh * h)
		}

		NSColor.white.setFill()
		NSRect(origin: .zero, size: size).fill()

		// Solid black title panel: deep blacks and the paper peeking through them.
		NSColor.black.setFill()
		rect(0.07, 0.08, 0.86, 0.17).fill()
		("SIMPLE COMIC" as NSString).draw(
			in: rect(0.10, 0.12, 0.80, 0.09),
			withAttributes: [.font: NSFont.boldSystemFont(ofSize: h * 0.045),
							 .foregroundColor: NSColor.white])

		// A midtone block.
		NSColor(white: 0.5, alpha: 1).setFill()
		rect(0.07, 0.30, 0.38, 0.24).fill()

		// Black to white, for the tonal remap.
		let gradient = NSGradient(starting: .black, ending: .white)
		gradient?.draw(in: rect(0.50, 0.30, 0.43, 0.24), angle: 0)

		// Thin strokes, where grain shows up first.
		NSColor.black.setFill()
		let lineHeight = max(1, h * 0.002)
		for i in 0..<8 {
			let y = (0.60 + CGFloat(i) * 0.018) * h
			NSRect(x: 0.07 * w, y: y, width: 0.86 * w, height: lineHeight).fill()
		}

		// Saturated ink.
		let colours: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow]
		for (i, colour) in colours.enumerated() {
			colour.setFill()
			rect(0.07 + CGFloat(i) * 0.22, 0.80, 0.18, 0.13).fill()
		}

		return image
	}
}
