//
//  SCArchiveProbe.swift
//  Simple Comic
//
//  Reads just enough out of a comic archive to put it in the library: how many pages it
//  has, its cover, and its ComicInfo.xml. Nothing is extracted to disk and no managed
//  objects are created — the existing TSSTManagedGroup path materialises one Image row per
//  page and unpacks nested archives to /tmp, which is right for reading one comic and
//  wrong for walking a folder of hundreds.
//
//  Two deliberate restrictions, both because a scan runs unattended over many files:
//
//  * The archive is opened with **no delegate**. TSSTManagedArchive passes itself so that
//    XADMaster can raise a modal password or encoding prompt; here a prompt per file would
//    be a wall of dialogs. Without a delegate an encrypted archive simply fails to read and
//    is reported as such.
//  * Only the first page and ComicInfo.xml are extracted. Everything else is read from the
//    archive's directory, not its contents.
//

import AppKit

enum SCArchiveError: Error {
	case unreadable
	case encrypted
	case empty
}

enum SCArchiveProbe {

	struct Result {
		var pageCount: Int
		var coverData: Data?
		var info: SCComicInfoData?
	}

	/// The page extensions the app itself recognises, as a set for cheap lookups.
	/// `TSSTPage.imageExtensions` derives them from `NSImage.imageTypes`, so the library and
	/// the reader always agree on what counts as a page.
	private static let imageExtensions: Set<String> = {
		Set(TSSTPage.imageExtensions.map { $0.lowercased() })
	}()

	/// Opens `url` and reports its page count, cover bytes and metadata.
	///
	/// Call off the main thread: opening an archive parses its directory, which on a large
	/// file or a network volume takes long enough to be felt.
	static func probe(url: URL) throws -> Result {
		let archive: XADArchive
		do {
			archive = try XADArchive(fileURL: url, delegate: nil)
		} catch {
			throw SCArchiveError.unreadable
		}
		if archive.isEncrypted {
			throw SCArchiveError.encrypted
		}

		var pages: [(index: Int, name: String)] = []
		var metadataEntries: [(index: Int, name: String)] = []

		for index in 0..<archive.numberOfEntries {
			guard !archive.entryIsDirectory(index),
				  !archive.entryIsEncrypted(index),
				  let name = archive.name(ofEntry: index),
				  isVisible(name) else { continue }

			let ext = (name as NSString).pathExtension.lowercased()
			if imageExtensions.contains(ext) {
				pages.append((index, name))
			} else if (name as NSString).lastPathComponent.caseInsensitiveCompare("ComicInfo.xml") == .orderedSame {
				metadataEntries.append((index, name))
			}
		}

		guard !pages.isEmpty else { throw SCArchiveError.empty }

		// Same ordering the reader uses (TSSTSortDescriptor): case-insensitive and numeric,
		// so page 2 comes before page 10 and the cover really is the first page on screen.
		pages.sort { naturalCompare($0.name, $1.name) == .orderedAscending }

		var result = Result(pageCount: pages.count, coverData: nil, info: nil)
		result.coverData = try? archive.contents(ofEntry: pages[0].index)
		if let entry = preferredMetadata(among: metadataEntries),
		   let data = try? archive.contents(ofEntry: entry.index) {
			result.info = SCComicInfoParser.parse(data)
		}
		return result
	}

	// MARK: Helpers

	/// Skips the resource-fork sidecar folder ZIPs made on a Mac carry, and dot files.
	private static func isVisible(_ name: String) -> Bool {
		if name.hasPrefix("__MACOSX/") || name.contains("/__MACOSX/") { return false }
		return !(name as NSString).lastPathComponent.hasPrefix(".")
	}

	/// A root-level ComicInfo.xml wins over a nested one; ties are broken by sorting rather
	/// than by whichever entry came first, so the choice is stable across runs.
	private static func preferredMetadata(among entries: [(index: Int, name: String)]) -> (index: Int, name: String)? {
		guard !entries.isEmpty else { return nil }
		let rootLevel = entries.filter { !$0.name.contains("/") }
		let candidates = rootLevel.isEmpty ? entries : rootLevel
		return candidates.sorted { naturalCompare($0.name, $1.name) == .orderedAscending }.first
	}

	/// The comparison `TSSTSortDescriptor` performs, so the library sorts entry names exactly
	/// the way the reader orders pages.
	private static func naturalCompare(_ lhs: String, _ rhs: String) -> ComparisonResult {
		lhs.compare(rhs, options: [.caseInsensitive, .numeric, .widthInsensitive, .forcedOrdering])
	}
}
