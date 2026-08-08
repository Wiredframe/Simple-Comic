//
//  SCLibraryStorage.swift
//  Simple Comic
//
//  On-disk locations for the library. The index holds metadata and file names only;
//  the bytes live here. Everything sits under the app's existing Application Support
//  folder (the same one that holds SimpleComic.sql), in a "Library" subfolder, so the
//  library is trivially inspectable and trivially deletable without touching Core Data.
//
//  Covers are permanent: they are the library. Archives under Comics/ are copies made
//  on demand when a comic is opened and may be thrown away at any time (see
//  SCLibraryImporter.evict) — the entry survives with its cover and metadata intact.
//

import Foundation

enum SCLibraryStorage {

	static let fm = FileManager.default

	/// `~/Library/Application Support/Simple Comic/Library` (inside the sandbox container).
	/// Mirrors `-[SimpleComicAppDelegate applicationSupportFolder]` so everything the app
	/// writes stays in one place.
	static var root: URL {
		ensured(appSupport.appendingPathComponent("Library", isDirectory: true))
	}

	/// The index itself. Written atomically by `SCLibraryStore`.
	static var indexURL: URL { root.appendingPathComponent("library.json") }

	/// Cover JPEGs, one per entry, named `<uuid>.jpg`. Permanent.
	static var covers: URL { ensured(root.appendingPathComponent("Covers", isDirectory: true)) }

	/// On-demand copies of the archives, each under `<uuid>/` and keeping its own file name so
	/// the reader window is titled with the comic. Disposable.
	static var comics: URL { ensured(root.appendingPathComponent("Comics", isDirectory: true)) }

	static func coverURL(_ fileName: String) -> URL { covers.appendingPathComponent(fileName) }
	static func archiveURL(_ fileName: String) -> URL { comics.appendingPathComponent(fileName) }

	/// Removes an entry's on-demand copy, folder and all. Safe to call when there is none.
	static func removeLocalArchive(of entry: SCLibraryEntry) {
		if let container = entry.archiveContainerURL {
			try? fm.removeItem(at: container)
		} else {
			try? fm.removeItem(at: entry.archiveURL)
		}
	}

	// MARK: Helpers

	private static var appSupport: URL {
		let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
			?? URL(fileURLWithPath: NSTemporaryDirectory())
		return ensured(base.appendingPathComponent("Simple Comic", isDirectory: true))
	}

	@discardableResult
	private static func ensured(_ url: URL) -> URL {
		if !fm.fileExists(atPath: url.path) {
			try? fm.createDirectory(at: url, withIntermediateDirectories: true)
		}
		return url
	}
}
