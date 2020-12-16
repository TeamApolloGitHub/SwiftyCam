//
//  MediaUtil.swift
//  heic_demo
//
//  Created by Jerry Tian on 2020/11/25.
//
import UIKit
import AVKit
import AVFoundation
import MediaToolbox
import MediaPlayer
import Photos
import PhotosUI
import VideoToolbox


class MediaUtil : NSObject {
    
    static let documentInteractionController = UIDocumentInteractionController()
    
    class func systemShareAction(url: URL, from view:UIView) {
        documentInteractionController.url = url
        documentInteractionController.uti = url.typeIdentifier ?? "public.data, public.content"
        documentInteractionController.name = url.localizedName ?? url.lastPathComponent
        documentInteractionController.presentOptionsMenu(from: view.frame, in: view, animated: true)
    }
    
    class func getUrlFromPHAsset(asset: PHAsset, callBack: @escaping (_ url: URL?) -> Void)
    {
        asset.requestContentEditingInput(with: PHContentEditingInputRequestOptions(), completionHandler: { (contentEditingInput, dictInfo) in

            if let strURL = (contentEditingInput!.audiovisualAsset as? AVURLAsset)?.url.absoluteString
            {
                log.info("translated asset URL: \(strURL)")
                callBack(URL.init(string: strURL))
            }
        })
    }
    
    class func sampleHdrTestMovUrl() -> URL {
        guard let url = Bundle.main.url(forResource: "hdr_test", withExtension: "mov") else {
            fatalError("required video asset wasn't found in the app bundle.")
        }
        
        return url
    }
    
    class func sampleProRawUrl() -> URL {
        
            guard let url = Bundle.main.url(forResource: "proraw_test", withExtension: "dng") else {
                fatalError("required ProRaw asset wasn't found in the app bundle.")
            }
            
            return url
    }
    
    class func sampleProRaw16bitPNGExportUrl() -> URL {
        
            guard let url = Bundle.main.url(forResource: "proraw_test", withExtension: "png") else {
                fatalError("required ProRaw asset wasn't found in the app bundle.")
            }
            
            return url
    }
    
    class func createUrlForAsset(with name: String, ofType: String) -> URL? {
        let fileManager = FileManager.default
        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = cacheDirectory.appendingPathComponent("\(name).\(ofType)")
        
        guard fileManager.fileExists(atPath: url.path) else {
            guard let dataObj = NSDataAsset(name: name)  else { return nil }
            fileManager.createFile(atPath: url.path, contents: dataObj.data, attributes: nil)
            return url
        }
        
        return url
    }
    
    public static let hasHEVCHardwareEncoder: Bool = {
        let spec: [CFString: Any]
        #if os(macOS)
            spec = [ kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true ]
        #else
            spec = [:]
        #endif
        var outID: CFString?
        var properties: CFDictionary?
        let result = VTCopySupportedPropertyDictionaryForEncoder(width: 3840, height: 2160, codecType: kCMVideoCodecType_HEVC, encoderSpecification: spec as CFDictionary, encoderIDOut: &outID, supportedPropertiesOut: &properties)
        if result == kVTCouldNotFindVideoEncoderErr {
            return false // no hardware HEVC encoder
        }
        return result == noErr
    }()
    
    class  func imageFromVideo(url: URL, at time: CMTime) -> UIImage? {
        let asset = AVURLAsset(url: url)

        let assetIG = AVAssetImageGenerator(asset: asset)
        assetIG.appliesPreferredTrackTransform = true
        assetIG.apertureMode = AVAssetImageGenerator.ApertureMode.encodedPixels

        let thumbnailImageRef: CGImage
        do {
            thumbnailImageRef = try assetIG.copyCGImage(at: time, actualTime: nil)
        } catch let error {
            log.error("capture frame error: \(error)")
            return nil
        }
        
        log.info("color space for frame: \(String(describing: thumbnailImageRef.colorSpace))")
        log.info("bits per componet for frame: \(String(describing: thumbnailImageRef.bitsPerComponent))")
        log.info("bits per pixel for frame: \(String(describing: thumbnailImageRef.bitsPerPixel))")
        return UIImage(cgImage: thumbnailImageRef)
    }
    
    
    class func exportVideo(input:URL, output:URL, outputType:AVFileType, atTime:CMTime?, withLength:Float64, complete:@escaping () -> Void) {
        let anAsset = AVAsset(url:input)
        let outputURL = output// URL of your exported output //
        
        let preset:String
        if hasHEVCHardwareEncoder {
            preset = AVAssetExportPresetHEVCHighestQuality
        } else {
            preset = AVAssetExportPresetHighestQuality
        }
        let outFileType = outputType
        
        log.info("try to export to \(output)")
        
        AVAssetExportSession.determineCompatibility(ofExportPreset: preset,
                                                    with: anAsset, outputFileType: outFileType) { isCompatible in
            guard isCompatible else {
                log.warning("does not suport exporting to target profile.")
                return
            }
            
            // Compatibility check succeeded, continue with export.
            guard let exportSession = AVAssetExportSession(asset: anAsset,
                                                           presetName: preset) else {
                log.warning("no suport of target profile，export session init failure.")
                return
            }
            exportSession.outputFileType = outFileType
            exportSession.outputURL = outputURL
            
            if let t = atTime {
                let range = CMTimeRangeMake(start:t, duration:CMTimeMakeWithSeconds(withLength, preferredTimescale: 600))
                exportSession.timeRange = range
            }
            
            exportSession.exportAsynchronously {
                // Handle export results.
                log.info("export result: \(exportSession.status)")
                log.info("error found? \(String(describing: exportSession.error))")
                log.info("exported size: \(output.bytesSizeIfAvailable())")
                complete()
            }
            
        }
    }
    
    class func generateTmpMovFileURL() -> URL {
        let outputFileName = ProcessInfo().globallyUniqueString
        let outputFilePath = (NSTemporaryDirectory() as NSString).appendingPathComponent((outputFileName as NSString).appendingPathExtension("mov")!)
        return URL(fileURLWithPath: outputFilePath)
    }
    
    class func writeTmpFileWithData(data:Data, tmpName:String?) throws -> URL {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(),
                                            isDirectory: true)
        
        
        let temporaryFilename = ProcessInfo().globallyUniqueString

        let temporaryFileURL:URL
        if (tmpName == nil) {
            temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(temporaryFilename)
        } else {
            temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(tmpName!)
        }
        
        try data.write(to: temporaryFileURL,
                       options: .atomic)
        
        return temporaryFileURL
    }

    class func cvPixelBufToVideo(pixBuf: CVPixelBuffer,
                                   withFileType: AVFileType,
                                   movieLength: TimeInterval,
                                   outputFileURL: URL,
                                   completion: @escaping (Error?) -> ()) {
         do {
           let w = CVPixelBufferGetWidth(pixBuf)
           let h = CVPixelBufferGetHeight(pixBuf)
           let videoWriter = try AVAssetWriter(outputURL: outputFileURL, fileType: withFileType)
            log.info("save image as video with spec: \(w)*\(h)")
            
            
            var settingAssist:AVOutputSettingsAssistant
            if (w == 3840) {
                settingAssist = AVOutputSettingsAssistant(preset: AVOutputSettingsPreset.hevc3840x2160)!
            } else if (w == 1920) {
                settingAssist = AVOutputSettingsAssistant(preset: AVOutputSettingsPreset.hevc1920x1080)!
            } else {
               throw VideoCompressionError.NotSupported
            }
            var settings:[String : Any] = settingAssist.videoSettings!
            
            var compressionProps:[String: Any] = settings[AVVideoCompressionPropertiesKey] as! [String: Any]
            compressionProps[AVVideoProfileLevelKey as String] = kVTProfileLevel_HEVC_Main10_AutoLevel
            compressionProps[AVVideoAverageBitRateKey as String] = 100000000
            compressionProps[AVVideoQualityKey] = 0.9
            let fps:Int32 = 5//not working, for an one-frame-video, fps is really meaningful?
            compressionProps[AVVideoExpectedSourceFrameRateKey] = fps
            settings[AVVideoCompressionPropertiesKey] = compressionProps
            log.info("compress settings: \(String(describing: compressionProps))")
            
            var colorProps:[String: Any] = settings[AVVideoColorPropertiesKey] as! [String: Any]
            colorProps[AVVideoColorPrimariesKey] = AVVideoColorPrimaries_ITU_R_2020
            colorProps[AVVideoTransferFunctionKey] = AVVideoTransferFunction_ITU_R_2100_HLG
            colorProps[AVVideoYCbCrMatrixKey] = AVVideoYCbCrMatrix_ITU_R_2020
            log.info("color properties: \(String(describing: colorProps))")
//            settings[AVVideoColorPropertiesKey] = colorProps
            
            settings.removeValue(forKey: AVVideoColorPropertiesKey)
            settings.removeValue(forKey: AVVideoScalingModeKey)
            
            
            log.info("overall settings: \(String(describing: settings))")
            let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video,
                                                      outputSettings: settings)
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput,
                                                               sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String:CVPixelBufferGetPixelFormatType(pixBuf)])
            
            if !videoWriter.canAdd(videoWriterInput) { throw VideoCompressionError.NotSupported }
            videoWriterInput.expectsMediaDataInRealTime = true
            videoWriter.add(videoWriterInput)
            
            let timeScale = fps // recommended in CMTime for movies.
            let startFrameTime = CMTimeMake(value:0, timescale:timeScale)
            
            var ok = videoWriter.startWriting()
            log.info("video writer start writing success? \(ok)")
            videoWriter.startSession(atSourceTime: startFrameTime)
            
            let buffer: CVPixelBuffer = pixBuf
            while !adaptor.assetWriterInput.isReadyForMoreMediaData { usleep(10) }
            ok = adaptor.append(buffer, withPresentationTime: startFrameTime)
            log.info("set frame_0 buffer success? \(ok)")
            
//            let halfMovieLength = Float64(movieLength/2.0) // videoWriter assumes frame lengths are equal.
//            let endFrameTime = CMTimeMakeWithSeconds(halfMovieLength, preferredTimescale:timeScale)
//            while !adaptor.assetWriterInput.isReadyForMoreMediaData { usleep(10) }
//            ok = adaptor.append(buffer, withPresentationTime: endFrameTime)
//            log.info("set end frame buffer success? \(ok)")
            
            videoWriterInput.markAsFinished()
            videoWriter.finishWriting {
                if (videoWriter.status == .completed) {
                    completion(nil)
                } else {
                    if (videoWriter.error != nil) {
                        completion(videoWriter.error)
                    } else {
                        completion(VideoCompressionError.CanNotFinalize)
                    }
                }
            }
         } catch {
             completion(error)
         }
     }
    
    class func dumpOutputPresets() {
        log.info("available presets: \(String(describing: AVOutputSettingsAssistant.availableOutputSettingsPresets()))")
    }
}
