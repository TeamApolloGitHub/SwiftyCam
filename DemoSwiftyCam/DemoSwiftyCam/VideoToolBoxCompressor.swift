//
//  VTBCompressor.swift
//  heic_demo
//
//  Created by Jerry Tian on 2020/12/11.
//

import UIKit
import AVKit
import AVFoundation
import MediaToolbox
import MediaPlayer
import Photos
import PhotosUI
import VideoToolbox

func compressionOutputCallback(outputCallbackRefCon: UnsafeMutableRawPointer?,
                               sourceFrameRefCon: UnsafeMutableRawPointer?,
                               status: OSStatus,
                               infoFlags: VTEncodeInfoFlags,
                               sampleBuffer: CMSampleBuffer?) -> Swift.Void {
    
    let vc: VideoToolBoxCompressor = Unmanaged.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
    
    guard status == noErr else {
        log.warning("error from encoder: \(status)")
        vc.setCompressSessionError(with: VideoCompressionError.CompressionFailure)
        return
    }
    
    if infoFlags == .frameDropped {
        log.warning("frame dropped from encoder.")
        vc.setCompressSessionError(with: VideoCompressionError.CompressionFailure)
        return
    }
    
    guard let sampleBuffer = sampleBuffer else {
        log.warning("no returned buffer.")
        vc.setCompressSessionError(with: VideoCompressionError.CompressionFailure)
        return
    }
    
    if CMSampleBufferDataIsReady(sampleBuffer) != true {
        log.warning("buffer compressed data is not ready.")
        vc.setCompressSessionError(with: VideoCompressionError.CompressionFailure)
        return
    }
    
    vc.writeCompressedFrame(frame: sampleBuffer)
}

class VideoToolBoxCompressor : NSObject {
    
    public var expectingSingleFrame = false
    
    public var compressQuality = 0.5
    public var forceAVCCodec = false
    
    public var imageOrientOpt:UIImage.Orientation = .up
    public var videoOrientOpt:AVCaptureVideoOrientation = .landscapeLeft
    
    private var frameCount = 0
    
    private var lastFrameTime = CMTimeMake(value:0, timescale:600)
    
    private let compressionQueue = DispatchQueue(label: "vtb.compression.queue")
    private let writingQueue = DispatchQueue(label: "vtb.writing.queue")
    
    //prepare a compress session.
    private var compressionSession:VTCompressionSession?
    private var assetWriter:AVAssetWriter?
    private var assetWriterInput:AVAssetWriterInput?
    
    var outputMovURL:URL?
    var outputJpegURL:URL?
    private var completionBlock:((Error?) -> ())?
    
    // Only MOV container is supported.
    private func prepareTmpOutputMovFile() {
        self.outputMovURL = MediaUtil.generateTmpFileURL(extension: "mov")
    }
    
    private func prepareTmpOutputJpegFile() {
        self.outputJpegURL = MediaUtil.generateTmpFileURL(extension: "jpg")
    }
    
    private func getVideoTransform() -> CGAffineTransform {
        switch self.videoOrientOpt {
            case .portrait:
                return CGAffineTransform(rotationAngle: .pi/2)
            case .portraitUpsideDown:
                return CGAffineTransform(rotationAngle: -.pi/2)
            case .landscapeLeft:
                return CGAffineTransform(rotationAngle: .pi)
            case .landscapeRight:
                return .identity
            default:
                return .identity
            }
        }
    
    func vtbPrepareEncoding(for sampleBuf:CMSampleBuffer, completion: @escaping (Error?) -> ()) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuf) else {
            self.completionBlock?(VideoCompressionError.SessionInitFailure)
            return
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        let status = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                                width: Int32(width),
                                                height: Int32(height),
                                                codecType: MediaUtil.hasHEVCHardwareEncoder ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
                                                encoderSpecification: nil,
                                                imageBufferAttributes: nil,
                                                compressedDataAllocator: nil,
                                                outputCallback: compressionOutputCallback,
                                                refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                                                compressionSessionOut: &self.compressionSession)
        
        self.completionBlock = completion
        
        if (status != noErr) {
            self.completionBlock?(VideoCompressionError.SessionInitFailure)
            return
        }
        
        guard let c = self.compressionSession else {
            self.completionBlock?(VideoCompressionError.SessionInitFailure)
            return
        }
        
        self.lastFrameTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuf)
        
        if MediaUtil.hasHEVCHardwareEncoder {
            VTSessionSetProperty(c, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main10_AutoLevel)
        } else {
            VTSessionSetProperty(c, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        }
        
        if self.forceAVCCodec {
            log.info("force AVC codec.")
            VTSessionSetProperty(c, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        }
        // if capture frame stream from camera, set to true, else
        VTSessionSetProperty(c, key: kVTCompressionPropertyKey_RealTime, value: false as CFTypeRef)
        VTSessionSetProperty(c, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 1 as CFTypeRef)
        
        // bitrates & quality control
//        let bitRate =  width * height * 4 * 32
//        print("target bit rate: \(bitRate/1000/1000)Mbps")
//        VTSessionSetProperty(c, key: kVTCompressionPropertyKey_AverageBitRate, value: bitRate as CFTypeRef)
        VTSessionSetProperty(c, key: kVTCompressionPropertyKey_Quality, value: self.compressQuality as CFTypeRef)
//        VTSessionSetProperty(c, key: kVTCompressionPropertyKey_DataRateLimits, value: [100*1024*1024, 1] as CFArray)
//        VTSessionSetProperty(c, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 3 as CFTypeRef)
        VTSessionSetProperty(c, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCMFormatDescriptionColorPrimaries_ITU_R_2020)
        VTSessionSetProperty(c, key: kVTCompressionPropertyKey_TransferFunction, value: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG)
        VTSessionSetProperty(c, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCMFormatDescriptionYCbCrMatrix_ITU_R_2020)
        //if HLG, false; if P3_D65, true.
        VTSessionSetProperty(c, key: kCMFormatDescriptionExtension_FullRangeVideo, value: false as CFTypeRef)
        
        VTCompressionSessionPrepareToEncodeFrames(c)
        
        do {
            if let _ = self.outputMovURL, let _ = self.outputJpegURL {
                
            } else {
                self.prepareTmpOutputMovFile()
                self.prepareTmpOutputJpegFile()
            }
            self.assetWriter = try AVAssetWriter(outputURL: self.outputMovURL!, fileType: .mov)
            
            //outputSettings = nil => no compression, buffer is in compressed state already.
            self.assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil)
            self.assetWriterInput?.transform = self.getVideoTransform()
            
            guard let writer = assetWriter, let writerInput = assetWriterInput else {
                throw VideoCompressionError.NotSupported
            }
            
            if (writer.canAdd(writerInput)) {
                writer.add(writerInput)
            } else {
                throw VideoCompressionError.NotSupported
            }
            
            writer.startWriting()
            writer.startSession(atSourceTime: self.lastFrameTime)
        } catch {
            log.warning("can not init MOV writer. \(error)")
            self.completionBlock?(VideoCompressionError.AVWriterInitFailure)
            return
        }
    }
    
    func vtbEncodeFrame(buffer sampleBuf:CMSampleBuffer) {
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuf) else {
            self.completionBlock?(VideoCompressionError.ImageMissing)
            return
        }
        
        guard let c = self.compressionSession else {
            self.completionBlock?(VideoCompressionError.NoCompressSession)
            return
        }
        
        let t = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuf)
        self.lastFrameTime = t
        
        self.compressionQueue.async {
             pixelBuffer.lock(.readwrite) {
                 let duration = CMSampleBufferGetOutputDuration(sampleBuf)
                 VTCompressionSessionEncodeFrame(c,
                                                 imageBuffer: pixelBuffer,
                                                 presentationTimeStamp: self.lastFrameTime,
                                                 duration: duration,
                                                 frameProperties: nil,
                                                 sourceFrameRefcon: nil,
                                                 infoFlagsOut: nil)
                
                
                // Create a CIImage from the pixel buffer and apply a filter
                let image = UIImage(pixelBuffer: pixelBuffer, with:self.imageOrientOpt)
                do {
                    try image!.jpegData(compressionQuality: 0.85)!.write(to: self.outputJpegURL!)
                    log.info("JPEG written at: \(self.outputJpegURL!), size: \(self.outputJpegURL!.bytesSizeIfAvailable())")
                } catch {
                    log.warning("failed to write JPEG: \(error)")
                }
             }
            
            
         }
    }
    
    fileprivate func setCompressSessionError(with err:VideoCompressionError) {
        self.completionBlock?(err)
    }
    
    func vtbFinishEncoding() {
        guard let c = self.compressionSession else {
            self.completionBlock?(VideoCompressionError.NoCompressSession)
            return
        }
        
        guard let w = self.assetWriter else {
            self.completionBlock?(VideoCompressionError.NoCompressSession)
            return
        }
        
        guard let wi = self.assetWriterInput else {
            self.completionBlock?(VideoCompressionError.NoCompressSession)
            return
        }
        
        
        self.compressionQueue.async {
            VTCompressionSessionCompleteFrames(c, untilPresentationTimeStamp: CMTime.invalid)
            VTCompressionSessionInvalidate(c)
            self.compressionSession = nil
            
            self.writingQueue.async {
                
                wi.markAsFinished()
                var t = self.lastFrameTime
                if (self.expectingSingleFrame) {
                    t = CMTimeMakeWithSeconds(CMTimeGetSeconds(t) + 3, preferredTimescale: t.timescale)
                }
                w.endSession(atSourceTime: t)
                
                w.finishWriting {
                    if (w.status == .completed) {
                        log.info("MOV file written ok. \(self.outputMovURL!.bytesSizeIfAvailable()) bytes of \(self.frameCount) frames.")
                    } else {
                        log.warning("MOV file written with error: \(String(describing: w.error))")
                        self.completionBlock?(w.error)
                    }
                    
                    self.assetWriterInput = nil
                    self.assetWriter = nil
                    
                    self.completionBlock?(nil)
                }
            }
        }
    }
    
    fileprivate func writeCompressedFrame(frame sampleBuffer: CMSampleBuffer) {
        
        guard let writerInput = self.assetWriterInput else {
            return
        }
        
        writingQueue.sync {
            defer {
                let result = writerInput.append(sampleBuffer)
                self.frameCount += 1
                log.debug("append buffer to writer good? \(self.frameCount):\(result)")
            }
            
            while (!writerInput.isReadyForMoreMediaData) {}
        }
    }
}
