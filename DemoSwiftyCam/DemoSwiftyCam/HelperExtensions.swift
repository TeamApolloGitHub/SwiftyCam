//
//  HelperExtensions.swift
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

extension UIImage {
    public convenience init?(pixelBuffer: CVPixelBuffer) {
        var cgImageRef: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImageRef)

        guard let _ = cgImageRef else {
            return nil
        }
        
        log.info("color space for frame: \(String(describing: cgImageRef!.colorSpace))")
        log.info("bits per componet for frame: \(String(describing: cgImageRef!.bitsPerComponent))")
        log.info("bits per pixel for frame: \(String(describing: cgImageRef!.bitsPerPixel))")
//        self.init(cgImage: cgImageRef!, scale: 1.0, orientation:UIImage.Orientation.down)
        self.init(cgImage: cgImageRef!)
    }
}

extension URL {
    public func bytesSizeIfAvailable() -> Int {
        do {
            let resources = try self.resourceValues(forKeys:[.fileSizeKey])
            let fileSize = resources.fileSize!
            return fileSize
        } catch {
            return -1
        }
    }
    
    var typeIdentifier: String? {
        return (try? resourceValues(forKeys: [.typeIdentifierKey]))?.typeIdentifier
    }
    
    var localizedName: String? {
        return (try? resourceValues(forKeys: [.localizedNameKey]))?.localizedName
    }
}
