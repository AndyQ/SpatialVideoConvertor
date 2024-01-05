//
//  VideoWriter.swift
//  SpacialVideoConvertor
//
//  Created by Andy Qua on 04/01/2024.
//

// Based on code from xaphod/VideoWriter.swift - https://gist.github.com/xaphod/de83379cc982108a5b38115957a247f9


import Foundation
import AVFoundation
import CoreImage

class VideoWriter {
    fileprivate var writer: AVAssetWriter
    fileprivate var writerInput: AVAssetWriterInput
    fileprivate var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor
    fileprivate let queue: DispatchQueue
    static var ciContext = CIContext.init() // we reuse a single context for performance reasons
    
    let pixelSize: CGSize
    var lastPresentationTime: CMTime?
    
    init?(url: URL, width: Int, height: Int, orientation: CGAffineTransform, sessionStartTime: CMTime, isRealTime: Bool, queue: DispatchQueue) {
        print("VideoWriter init: width=\(width) height=\(height), url=\(url)")
        self.queue = queue
        let outputSettings: [String:Any] = [
            AVVideoCodecKey : AVVideoCodecType.h264, // or .hevc if you like
            AVVideoWidthKey : width,
            AVVideoHeightKey: height,
        ]
        self.pixelSize = CGSize.init(width: width, height: height)
        let input = AVAssetWriterInput.init(mediaType: .video, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = isRealTime
        input.transform = orientation
        
        guard
            let writer = try? AVAssetWriter.init(url: url, fileType: .mp4),
            writer.canAdd(input),
            sessionStartTime != .invalid
        else {
            return nil
        }
        
        let sourceBufferAttributes: [String:Any] = [
            String(kCVPixelBufferPixelFormatTypeKey) : kCVPixelFormatType_32ARGB, // yes, ARGB is right here for images...
            String(kCVPixelBufferWidthKey) : width,
            String(kCVPixelBufferHeightKey) : height,
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor.init(assetWriterInput: input, sourcePixelBufferAttributes: sourceBufferAttributes)
        self.pixelBufferAdaptor = pixelBufferAdaptor
        
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: sessionStartTime)
        
        if let error = writer.error {
            NSLog("VideoWriter init: ERROR - \(error)")
            return nil
        }
        
        self.writer = writer
        self.writerInput = input
    }
    
    func add(image: CIImage, presentationTime: CMTime) -> Bool {
        if self.writerInput.isReadyForMoreMediaData == false {
            return false
        }
        if self.pixelBufferAdaptor.appendPixelBufferForImage(image, presentationTime: presentationTime) {
            self.lastPresentationTime = presentationTime
            return true
        }
        return false
    }

    func add(buffer: CVPixelBuffer, presentationTime: CMTime) -> Bool {
        if self.writerInput.isReadyForMoreMediaData == false {
            return false
        }
        if self.pixelBufferAdaptor.append(buffer, withPresentationTime: presentationTime) {
            self.lastPresentationTime = presentationTime
            return true
        }
        return false
    }
    
    func add(sampleBuffer: CMSampleBuffer) -> Bool {
        if self.writerInput.isReadyForMoreMediaData == false {
            print("VideoWriter: not ready for more data")
            return false
        }
        
        if self.writerInput.append(sampleBuffer) {
            self.lastPresentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            return true
        }
        return false
    }
    
    func finish() async throws -> AVAsset? {
        writerInput.markAsFinished()
        print("VideoWriter: calling writer.finishWriting()")
        await writer.finishWriting()
        if self.writer.status != .completed {
            print("VideoWriter finish: error in finishWriting - \(self.writer.error?.localizedDescription ?? "Unknown")")
            return nil
        }
        
        let asset = AVURLAsset.init(url: self.writer.outputURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey : true])
        let duration = try await CMTimeGetSeconds( asset.load(.duration) )
        // can check for minimum duration here (ie. consider a failure if too short)
        print("VideoWriter: finishWriting() complete, duration=\(duration)")
        return asset
    }
}

extension AVAssetWriterInputPixelBufferAdaptor {
    func appendPixelBufferForImage(_ image: CIImage, presentationTime: CMTime) -> Bool {
        var appendSucceeded = false
        
        autoreleasepool {
            guard let pixelBufferPool = self.pixelBufferPool else {
                print("appendPixelBufferForImage: ERROR - missing pixelBufferPool") // writer can have error:  writer.error=\(String(describing: self.writer.error))
                return
            }
            
            let pixelBufferPointer = UnsafeMutablePointer<CVPixelBuffer?>.allocate(capacity: 1)
            let status: CVReturn = CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                pixelBufferPool,
                pixelBufferPointer
            )
            
            if let pixelBuffer = pixelBufferPointer.pointee, status == 0 {
                pixelBuffer.fillPixelBufferFromImage(image)
                appendSucceeded = self.append(pixelBuffer, withPresentationTime: presentationTime)
                if !appendSucceeded {
                    // If a result of NO is returned, clients can check the value of AVAssetWriter.status to determine whether the writing operation completed, failed, or was cancelled.  If the status is AVAssetWriterStatusFailed, AVAsset.error will contain an instance of NSError that describes the failure.
                    print("VideoWriter appendPixelBufferForImage: ERROR appending")
                }
                pixelBufferPointer.deinitialize(count: 1)
            } else {
                print("VideoWriter appendPixelBufferForImage: ERROR - Failed to allocate pixel buffer from pool, status=\(status)") // -6680 = kCVReturnInvalidPixelFormat
            }
            pixelBufferPointer.deallocate()
        }
        return appendSucceeded
    }
}

extension CVPixelBuffer {
    func fillPixelBufferFromImage(_ image: CIImage) {
        CVPixelBufferLockBaseAddress(self, [])
        
        VideoWriter.ciContext.render(image, to: self)
        
        CVPixelBufferUnlockBaseAddress(self, [])
    }
}
