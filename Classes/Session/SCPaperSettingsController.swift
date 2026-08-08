//
//  SCPaperSettingsController.swift
//  Simple Comic
//
//  A small floating panel that lets the user tune the paper effect live: a preview of the
//  effect on a sample page, sliders for show-through / grain / warmth / black-lift, and a few
//  presets. Everything is stored in NSUserDefaults (see SCPaperFilter) and a change posts
//  SCPaperFilter.settingsChangedNotification so open sessions redraw.
//
//  Kept in step with the iOS app's Paper Effect screen: the same four parameters over the
//  same ranges, the same presets, sliders that step in 5-percentage-point notches, readouts
//  in percent, and a live preview that is debounced so a drag doesn't stack renders.
//

import AppKit

@MainActor
@objc(SCPaperSettingsController)
final class SCPaperSettingsController: NSObject {

	@objc(sharedController)
	static let shared = SCPaperSettingsController()

	private struct Knob {
		let key: String
		let title: String
		let min: Double
		let max: Double
	}

	private let knobs: [Knob] = [
		Knob(key: SCPaperFilter.showThroughKey, title: "Paper show-through", min: 0.0, max: 0.8),
		Knob(key: SCPaperFilter.grainKey,       title: "Grain",             min: 0.0, max: 0.4),
		Knob(key: SCPaperFilter.warmthKey,      title: "Warmth",            min: 0.0, max: 1.0),
		Knob(key: SCPaperFilter.blackLiftKey,   title: "Black lift",        min: 0.0, max: 1.0),
	]

	/// Preset name + the parameter bundle it sets.
	private let presets: [(name: String, values: [String: Double])] = [
		("Cream paper", [SCPaperFilter.showThroughKey: 0.38, SCPaperFilter.grainKey: 0.14,
						 SCPaperFilter.warmthKey: 1.0, SCPaperFilter.blackLiftKey: 1.0]),
		("Newsprint",   [SCPaperFilter.showThroughKey: 0.52, SCPaperFilter.grainKey: 0.22,
						 SCPaperFilter.warmthKey: 0.55, SCPaperFilter.blackLiftKey: 1.0]),
		("Manga",       [SCPaperFilter.showThroughKey: 0.20, SCPaperFilter.grainKey: 0.09,
						 SCPaperFilter.warmthKey: 0.25, SCPaperFilter.blackLiftKey: 0.85]),
		("E-Ink",       [SCPaperFilter.showThroughKey: 0.30, SCPaperFilter.grainKey: 0.12,
						 SCPaperFilter.warmthKey: 0.0, SCPaperFilter.blackLiftKey: 1.0]),
	]

	/// Slider notches, matching the iOS app: 21 stops means one notch is five percent of the
	/// range. Programmatic values (the presets) stay exact; only dragging snaps.
	private static let notches = 21

	private var panel: NSPanel?
	private var sliders: [String: NSSlider] = [:]
	private var valueLabels: [String: NSTextField] = [:]
	private var presetPopup: NSPopUpButton?
	private var previewView: NSImageView?
	private var previewWork: DispatchWorkItem?

	@objc func showPanel(_ sender: Any?) {
		if panel == nil { panel = buildPanel() }
		syncControls()
		refreshPreview()
		panel?.center()
		panel?.makeKeyAndOrderFront(sender)
	}

	// MARK: - Building

	private func buildPanel() -> NSPanel {
		let grid = NSGridView()
		grid.translatesAutoresizingMaskIntoConstraints = false
		grid.rowSpacing = 10
		grid.columnSpacing = 10

		let preview = NSImageView()
		preview.imageScaling = .scaleProportionallyUpOrDown
		preview.wantsLayer = true
		preview.layer?.cornerRadius = 6
		preview.layer?.masksToBounds = true
		preview.image = SCSamplePage.preview
		preview.widthAnchor.constraint(equalToConstant: 200).isActive = true
		preview.heightAnchor.constraint(equalToConstant: 290).isActive = true
		previewView = preview
		let previewRow = grid.addRow(with: [preview])
		previewRow.mergeCells(in: NSRange(location: 0, length: 3))
		previewRow.cell(at: 0).xPlacement = .center

		let popup = NSPopUpButton(frame: .zero, pullsDown: false)
		popup.addItems(withTitles: presets.map { NSLocalizedString($0.name, comment: "Paper effect preset name") }
					   + [NSLocalizedString("Custom", comment: "Paper effect preset: user-adjusted values")])
		popup.target = self
		popup.action = #selector(presetChanged(_:))
		presetPopup = popup
		grid.addRow(with: [label(NSLocalizedString("Preset", comment: "Paper effect preset picker label")),
						   popup, NSGridCell.emptyContentView])

		for knob in knobs {
			let slider = NSSlider(value: knob.min, minValue: knob.min, maxValue: knob.max,
								  target: self, action: #selector(sliderChanged(_:)))
			slider.identifier = NSUserInterfaceItemIdentifier(knob.key)
			slider.isContinuous = true
			slider.numberOfTickMarks = Self.notches
			slider.allowsTickMarkValuesOnly = true
			slider.tickMarkPosition = .below
			slider.widthAnchor.constraint(equalToConstant: 170).isActive = true
			let value = label("")
			value.alignment = .right
			value.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
			value.widthAnchor.constraint(equalToConstant: 44).isActive = true
			sliders[knob.key] = slider
			valueLabels[knob.key] = value
			grid.addRow(with: [label(NSLocalizedString(knob.title, comment: "Paper effect parameter name")), slider, value])
		}

		let reset = NSButton(title: NSLocalizedString("Reset to Cream", comment: "Paper effect: reset to the default preset"),
							 target: self, action: #selector(resetToDefault(_:)))
		reset.bezelStyle = .rounded
		grid.addRow(with: [NSGridCell.emptyContentView, reset, NSGridCell.emptyContentView])
		grid.column(at: 0).xPlacement = .trailing

		let content = NSView()
		content.addSubview(grid)
		NSLayoutConstraint.activate([
			grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
			grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
			grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
			grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
		])

		let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 260),
						styleMask: [.titled, .closable, .utilityWindow],
						backing: .buffered, defer: false)
		p.title = NSLocalizedString("Paper Effect", comment: "Paper effect settings window title")
		p.isFloatingPanel = true
		p.hidesOnDeactivate = false
		p.isReleasedWhenClosed = false
		p.contentView = content
		return p
	}

	private func label(_ string: String) -> NSTextField {
		NSTextField(labelWithString: string)
	}

	// MARK: - Sync & actions

	private func syncControls() {
		let d = UserDefaults.standard
		for knob in knobs {
			// Falls back to the shipped default rather than the slider's minimum: an unset
			// value means "never touched", which is cream, not zero.
			let fallback = (SCPaperFilter.registeredDefaults[knob.key] as? Double) ?? knob.min
			let v = d.object(forKey: knob.key) != nil ? d.double(forKey: knob.key) : fallback
			sliders[knob.key]?.doubleValue = v
			valueLabels[knob.key]?.stringValue = Self.percentage(v, of: knob)
		}
		updatePresetSelection()
	}

	/// Slider readouts are percentages of the parameter's own range, the way the iOS app
	/// shows them — "60%" says more about a show-through of 0.48 than "0.48" does.
	private static func percentage(_ value: Double, of knob: Knob) -> String {
		guard knob.max > 0 else { return "0%" }
		return "\(Int((value / knob.max * 100).rounded()))%"
	}

	@objc private func sliderChanged(_ sender: NSSlider) {
		guard let key = sender.identifier?.rawValue,
			  let knob = knobs.first(where: { $0.key == key }) else { return }
		UserDefaults.standard.set(sender.doubleValue, forKey: key)
		valueLabels[key]?.stringValue = Self.percentage(sender.doubleValue, of: knob)
		updatePresetSelection()
		notifyChanged()
		refreshPreview()
	}

	@objc private func presetChanged(_ sender: NSPopUpButton) {
		let idx = sender.indexOfSelectedItem
		guard idx >= 0 && idx < presets.count else { return }  // "Custom" is a no-op
		let d = UserDefaults.standard
		for (k, v) in presets[idx].values { d.set(v, forKey: k) }
		syncControls()
		notifyChanged()
		refreshPreview()
	}

	@objc private func resetToDefault(_ sender: Any?) {
		guard let popup = presetPopup else { return }
		popup.selectItem(at: 0)
		presetChanged(popup)
	}

	private func updatePresetSelection() {
		let d = UserDefaults.standard
		let match = presets.firstIndex { preset in
			preset.values.allSatisfy { abs(d.double(forKey: $0.key) - $0.value) < 0.001 }
		}
		presetPopup?.selectItem(at: match ?? presets.count)  // last item = "Custom"
	}

	private func notifyChanged() {
		NotificationCenter.default.post(name: SCPaperFilter.settingsChangedNotification, object: nil)
	}

	// MARK: - Preview

	/// Re-renders the sample page through the filter, debounced.
	///
	/// A drag emits values continuously, and each one would otherwise start a full Core Image
	/// render that runs to completion even once superseded — the iOS app learned this the
	/// expensive way. Only a value that settles for the interval gets rendered.
	private func refreshPreview() {
		previewWork?.cancel()
		guard UserDefaults.standard.bool(forKey: SCPaperFilter.enabledKey) else {
			// Same as iOS: with the effect off, the preview shows the untouched page.
			previewView?.image = SCSamplePage.preview
			return
		}
		let work = DispatchWorkItem { [weak self] in
			let source = SCSamplePage.preview
			DispatchQueue.global(qos: .userInitiated).async {
				let rendered = SCPaperFilter.shared.paperImage(from: source)
				DispatchQueue.main.async {
					self?.previewView?.image = rendered ?? source
				}
			}
		}
		previewWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
	}
}
