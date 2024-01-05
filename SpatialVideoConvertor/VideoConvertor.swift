//
//  VideoReader.swift
//  SpatialVideoConvertor2
//
//  Created by Andy Qua on 05/01/2024.
//

#if os(macOS)
import Cocoa
#endif

import Foundation
import AVKit
import VideoToolbox

enum VideoReaderError : Error {
    case invalidVideo
    case notSpacialVideo
}

class VideoConvertor {
    func convertVideo( inputFile : URL, outputFile: URL, progress: ((Float)->())? = nil ) async throws {

        // Load the AVAsset
        let asset = AVAsset(url: inputFile)
        let assetReader = try AVAssetReader(asset: asset)
        
        // Check if its a spatial video
        let userDataItems = try await asset.loadMetadata(for:.quickTimeMetadata)
        let spacialCharacteristics = userDataItems.filter { $0.identifier?.rawValue == "mdta/com.apple.quicktime.spatial.format-version" }
        if spacialCharacteristics.count == 0 {
            throw VideoReaderError.notSpacialVideo
        }

        // Grab the orientation and size of the input video (used to set the output orientation)
        let (orientation, videoSize) = try await getOrientationAndResolutionSizeForVideo(asset: asset)
        
        // Output size is the full width but half the height
        // we have 2 side-by-side videos and we keep the aspect ratio
        let vw = VideoWriter(url: outputFile, width: Int(videoSize.width), height: Int(videoSize.height/2), orientation: orientation, sessionStartTime: CMTime(value: 1,  timescale: 30 ), isRealTime: false, queue: .main)!
        
        // Load out tracks
        let output = try await AVAssetReaderTrackOutput(
            track: asset.loadTracks(withMediaType: .video).first!,
            outputSettings: [
                AVVideoDecompressionPropertiesKey: [
                    kVTDecompressionPropertyKey_RequestedMVHEVCVideoLayerIDs: [0, 1] as CFArray,
                ],
            ]
        )
        assetReader.add(output)
        
        assetReader.startReading()
        
        let duration = try await asset.load(.duration)

        // Based on code from https://www.finnvoorhees.com/words/reading-and-writing-spatial-video-with-avfoundation
        while let nextSampleBuffer = output.copyNextSampleBuffer() {
            guard let taggedBuffers = nextSampleBuffer.taggedBuffers else { return }
            
            let leftEyeBuffer = taggedBuffers.first(where: {
                $0.tags.first(matchingCategory: .stereoView) == .stereoView(.leftEye)
            })?.buffer
            let rightEyeBuffer = taggedBuffers.first(where: {
                $0.tags.first(matchingCategory: .stereoView) == .stereoView(.rightEye)
            })?.buffer
            
            if let leftEyeBuffer,
               let rightEyeBuffer,
               case let .pixelBuffer(leftEyePixelBuffer) = leftEyeBuffer,
               case let .pixelBuffer(rightEyePixelBuffer) = rightEyeBuffer {
                
                let lciImage = CIImage(cvPixelBuffer: leftEyePixelBuffer)
                let rciImage = CIImage(cvPixelBuffer: rightEyePixelBuffer)
                
                let newpb = joinImages( leftImage: lciImage, rightImage: rciImage )
                
                let time = CMSampleBufferGetOutputPresentationTimeStamp(nextSampleBuffer)
                
                _ = vw.add(image: newpb, presentationTime: time)
                print( "Added frame at \(time)")
                
                // callback with progress
                progress?( Float(time.value)/Float(duration.value))

                // This sleep is needed to stop memory blooming - keeps around 280Mb rather than spiraling up to 8+Gig!
                try await Task.sleep(nanoseconds: 3_000_000)
            }
        }
        
        _ = try await vw.finish()
        
        print( "status - \(assetReader.status)")
        print( "status - \(assetReader.error?.localizedDescription ?? "None")")
        print( "Finished")
        
    }
    
    func getOrientationAndResolutionSizeForVideo(asset:AVAsset) async throws -> (CGAffineTransform, CGSize) {
        guard let track = try await asset.loadTracks(withMediaType: AVMediaType.video).first else { throw VideoReaderError.invalidVideo }
        let naturalSize = try await track.load(.naturalSize)
        let naturalTransform = try await track.load(.preferredTransform)
        let size = naturalSize.applying(naturalTransform)
        return (naturalTransform, CGSize(width: abs(size.width), height: abs(size.height)) )
    }
    
    
#if os(iOS)
    
    func joinImages( leftImage:CIImage, rightImage:CIImage) -> CIImage {
        let left =  UIImage(ciImage: leftImage )
        let right =  UIImage(ciImage: rightImage )
        
        let imageWidth = left.size.width/2 + right.size.width/2
        let imageHeight = left.size.height/2
        
        let newImageSize = CGSize(width:imageWidth, height: imageHeight);
        UIGraphicsBeginImageContextWithOptions(newImageSize, false, 1);
        left.draw(in: CGRect(x:0, y:0, width:imageWidth/2, height:imageHeight))
        right.draw(in: CGRect(x:imageWidth/2, y:0, width:imageWidth/2, height:imageHeight))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext();
        
        let ci = CIImage(cgImage: image.cgImage!)
        return ci
    }
    
#elseif os(macOS)
    
    func joinImages( leftImage:CIImage, rightImage:CIImage) -> CIImage {
        let left = leftImage.asNSImage()!
        let right =  rightImage.asNSImage()!
        
        // Note we knock the width down by 4 and the height by 2 because of retina
        // For some reason, converting from CGImage to CIImage uses the number of screen pixels
        // which is double (and not doing this uses loads of memory)
        
        let imageWidth = left.size.width/4 + right.size.width/4
        let imageHeight = left.size.height/4
        let imageSize = CGSize(width: imageWidth, height: imageHeight )
        let im = NSImage.init(size: imageSize)
        let rep = NSBitmapImageRep.init(bitmapDataPlanes: nil,
                                        pixelsWide: Int(imageSize.width),
                                        pixelsHigh: Int(imageSize.height),
                                        bitsPerSample: 8,
                                        samplesPerPixel: 4,
                                        hasAlpha: true,
                                        isPlanar: false,
                                        colorSpaceName: NSColorSpaceName.calibratedRGB,
                                        bytesPerRow: 0,
                                        bitsPerPixel: 0)
        
        im.addRepresentation(rep!)
        
        im.lockFocus()
        
        left.draw(in: CGRect(x:0, y:0, width:imageWidth/2, height:imageHeight))
        right.draw(in: CGRect(x:imageWidth/2, y:0, width:imageWidth/2, height:imageHeight))
        im.unlockFocus()
        
        let ci = im.asCIImage()
        return ci!
    }
    
#endif
}
