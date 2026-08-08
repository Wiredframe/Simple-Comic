//
//  SCTranslate.swift
//  Simple Comic
//
//  Hands recognised text to the system translator, so the Live Text menu can offer Translate
//  next to Copy, Look Up and Speak.
//
//  macOS has no AppKit call for this. The public entry point is SwiftUI's
//  `.translationPresentation(isPresented:text:)` from the Translation framework, which shows
//  Apple's own translation popover — the same one Safari and Preview put up. So a one-pixel
//  hosting view is parked at the click location purely to give that popover something to
//  anchor to, and is torn down again when the popover closes.
//
//  The framework is macOS 15 and later. On anything older `isAvailable` is false and the menu
//  item is left out rather than shown disabled.
//

import AppKit
import SwiftUI
#if canImport(Translation)
import Translation
#endif

@objc(SCTranslate)
final class SCTranslate: NSObject {

	/// Whether this system can translate at all. The Live Text menu asks before adding the item.
	@objc static var isAvailable: Bool {
		if #available(macOS 15.0, *) {
			return true
		}
		return false
	}

	/// Shows the system translation popover for `text`, anchored inside `view` at `point`
	/// (in `view`'s coordinates).
	@objc(translateText:inView:atPoint:)
	static func translate(text: String, in view: NSView, at point: NSPoint) {
		guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
		#if canImport(Translation)
		guard #available(macOS 15.0, *) else { return }

		// Anything still on screen from a previous invocation goes first, so repeated
		// translations don't stack anchors inside the page view.
		removeAnchors(from: view)

		let anchor = NSView(frame: NSRect(x: point.x, y: point.y, width: 1, height: 1))
		anchor.identifier = anchorIdentifier
		view.addSubview(anchor)

		let host = NSHostingView(rootView: TranslationAnchor(text: text) { [weak anchor] in
			anchor?.removeFromSuperview()
		})
		host.frame = anchor.bounds
		anchor.addSubview(host)
		#endif
	}

	private static let anchorIdentifier = NSUserInterfaceItemIdentifier("SCTranslationAnchor")

	private static func removeAnchors(from view: NSView) {
		for subview in view.subviews where subview.identifier == anchorIdentifier {
			subview.removeFromSuperview()
		}
	}
}

#if canImport(Translation)
@available(macOS 15.0, *)
private struct TranslationAnchor: View {

	let text: String
	let onDismiss: () -> Void

	@State private var isPresented = true

	var body: some View {
		Color.clear
			.frame(width: 1, height: 1)
			.translationPresentation(isPresented: $isPresented, text: text)
			.onChange(of: isPresented) { _, presented in
				if !presented { onDismiss() }
			}
	}
}
#endif
