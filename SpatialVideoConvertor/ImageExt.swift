//
//  ImageExt.swift
//  SpatialVideoConvertor
//
//  Created by Andy Qua on 05/01/2024.
//

#if os(macOS)
import Cocoa
import CoreImage

extension NSImage {
    /// Create a CIImage using the best representation available
    ///
    /// - Returns: Converted image, or nil
    func asCIImage() -> CIImage? {
        if let cgImage = self.asCGImage() {
            return CIImage(cgImage: cgImage)
        }
        return nil
    }
    
    /// Create a CGImage using the best representation of the image available in the NSImage for the image size
    ///
    /// - Returns: Converted image, or nil
    func asCGImage() -> CGImage? {
        var rect = NSRect(origin: CGPoint(x: 0, y: 0), size: self.size)
        return self.cgImage(forProposedRect: &rect, context: NSGraphicsContext.current, hints: nil)
    }
}

extension CIImage {
    /// Create a CGImage version of this image
    ///
    /// - Returns: Converted image, or nil
    func asCGImage(context: CIContext? = nil) -> CGImage? {
        let ctx = context ?? CIContext(options: nil)
        return ctx.createCGImage(self, from: self.extent)
    }
    
    /// Create an NSImage version of this image
    /// - Parameters:
    ///   - pixelSize: The number of pixels in the result image. For a retina image (for example), pixelSize is double repSize
    ///   - repSize: The number of points in the result image
    /// - Returns: Converted image, or nil
    func asNSImage(pixelsSize: CGSize? = nil, repSize: CGSize? = nil) -> NSImage? {
        let rep = NSCIImageRep(ciImage: self)
        if let ps = pixelsSize {
            rep.pixelsWide = Int(ps.width)
            rep.pixelsHigh = Int(ps.height)
        }
        if let rs = repSize {
            rep.size = rs
        }
        let updateImage = NSImage(size: rep.size)
        updateImage.addRepresentation(rep)
        return updateImage
    }
}

extension CGImage {
    /// Create a CIImage version of this image
    ///
    /// - Returns: Converted image, or nil
    func asCIImage() -> CIImage {
        return CIImage(cgImage: self)
    }
    
    /// Create an NSImage version of this image
    ///
    /// - Returns: Converted image, or nil
    func asNSImage() -> NSImage? {
        return NSImage(cgImage: self, size: .zero)
    }
}
#endif
