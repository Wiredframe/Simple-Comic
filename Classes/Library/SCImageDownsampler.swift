//
//  SCImageDownsampler.swift
//  Simple Comic
//
//  Cover decoding via ImageIO: thumbnails are produced without ever materialising the
//  full-size bitmap, which matters when a scan walks a few hundred comic pages and again
//  when a grid scrolls a few hundred covers.
//
//  Ported from the iOS app (Model/ImageDownsampler.swift + Library/ImageCache.swift);
//  the only real change is UIImage → CGImage/NSImage.
//

import AppKit
import ImageIO
import UniformTypeIdentifiers

enum SCImageDownsampler {

	/// Longest side (pixels) for stored covers. Large enough to stay crisp when the grid is
	/// shown at one or two columns on a big display; small enough that a thousand of them
	/// don't fill the container.
	static let coverPixel: CGFloat = 1200

	/// Decodes `data` down to at most `maxPixel` on its longest side.
	static func downsample(_ data: Data, maxPixel: CGFloat) -> CGImage? {
		let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
		guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
		return thumbnail(from: source, maxPixel: maxPixel)
	}

	/// Same, but reads straight from a file so ImageIO streams only the bytes the thumbnail
	/// needs — the full-size image never materialises the way `Data(contentsOf:)` + decode would.
	/// This is the path a scrolling grid takes.
	static func downsample(url: URL, maxPixel: CGFloat) -> CGImage? {
		let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
		guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
		return thumbnail(from: source, maxPixel: maxPixel)
	}

	private static func thumbnail(from source: CGImageSource, maxPixel: CGFloat) -> CGImage? {
		let options: [CFString: Any] = [
			kCGImageSourceCreateThumbnailFromImageAlways: true,
			kCGImageSourceCreateThumbnailWithTransform: true,
			kCGImageSourceShouldCacheImmediately: true,
			kCGImageSourceThumbnailMaxPixelSize: maxPixel,
		]
		return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
	}

	/// Aspect (width / height) of the image at `url`, read from its header only — no bitmap is
	/// decoded, so this is cheap enough to run across a whole library. Stored covers are written
	/// already orientation-normalised (see `kCGImageSourceCreateThumbnailWithTransform`), so the
	/// raw pixel dimensions need no transform.
	static func pixelAspect(ofImageAt url: URL) -> Double? {
		let options = [kCGImageSourceShouldCache: false] as CFDictionary
		guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
			  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
			  let width = props[kCGImagePropertyPixelWidth] as? Double,
			  let height = props[kCGImagePropertyPixelHeight] as? Double,
			  height > 0 else { return nil }
		return width / height
	}

	@discardableResult
	static func writeJPEG(_ image: CGImage, to url: URL, quality: CGFloat = 0.85) -> Bool {
		let type = UTType.jpeg.identifier as CFString
		guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
			return false
		}
		let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
		CGImageDestinationAddImage(destination, image, options)
		return CGImageDestinationFinalize(destination)
	}

	/// Wraps a decoded image for display. The size is taken in pixels at scale 1: covers are
	/// laid out by aspect ratio, never by their point size.
	static func nsImage(_ image: CGImage) -> NSImage {
		NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
	}
}

/// A small in-memory cache of decoded covers so scrolling the grid doesn't re-read and
/// re-decode the same JPEGs each time a cell reappears.
enum SCImageCache {

	private static let cache: NSCache<NSString, NSImage> = {
		let cache = NSCache<NSString, NSImage>()
		// Bounded by decoded bytes rather than count: a count limit alone would pin a lot of
		// memory on a big library. NSCache also evicts under memory pressure, and covers
		// re-decode from disk cheaply via ImageIO.
		let gb = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
		cache.totalCostLimit = (gb >= 8 ? 128 : 64) * 1024 * 1024
		return cache
	}()

	static func image(forKey key: String) -> NSImage? {
		cache.object(forKey: key as NSString)
	}

	static func set(_ image: NSImage, forKey key: String) {
		cache.setObject(image, forKey: key as NSString, cost: cost(of: image))
	}

	static func clear() { cache.removeAllObjects() }

	/// Approximate decoded size in bytes (4 bytes per pixel).
	private static func cost(of image: NSImage) -> Int {
		Int(image.size.width * image.size.height) * 4
	}
}
