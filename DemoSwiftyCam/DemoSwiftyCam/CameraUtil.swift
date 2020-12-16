//
//  CameraUtil.swift
//  heic_demo
//
//  Created by OSX on 2020/11/26.
//

import Foundation
import AVFoundation


//@available(iOS 10.0, *)
//public enum AVCaptureColorSpace : Int {
//
//    case sRGB = 0
//
//    case P3_D65 = 1
//
//    @available(iOS 14.1, *)
//    case HLG_BT2020 = 2
//}

class CameraUtil {
    
    
    class func dumpAllFormats(with formats:Array<AVCaptureDevice.Format>) {
        log.debug(formatCaptureFormats(with: formats))
    }
    
    class func formatColorSpaceInfo(f:AVCaptureDevice.Format) -> String {
        var out = "["
        for c in f.supportedColorSpaces {
            if (c == AVCaptureColorSpace.sRGB) {
                out = out + "sRGB,"
            } else if (c == AVCaptureColorSpace.P3_D65) {
                out = out + "P3_D65,"
            } else {
                if #available(iOS 14.1, *) {
                    if (c == AVCaptureColorSpace.HLG_BT2020) {
                        out = out + "HLG_BT2020,"
                    }
                }
            }
        }
        out = out + "]"
        return out
    }
    
    class func formatCaptureFormats(with formats:Array<AVCaptureDevice.Format>) -> String {
        var out = ""
        
        for f in formats {
            out =  "\(out)\(String(describing: f))\n"
        }
        
        return out
    }
    
    
    class func find4kHDR_P3D65_Format(with formats:Array<AVCaptureDevice.Format>) -> AVCaptureDevice.Format? {
        for f in formats {
            if (false == f.isVideoHDRSupported) {
                continue
            }
            
            let fDesc:CMFormatDescription = f.formatDescription
            let dim = CMVideoFormatDescriptionGetDimensions(fDesc)
            if (dim.width != 3840 && dim.height != 2160) {
                continue
            }
            
            if ("420f" == fDesc.mediaSubType.rawValue.codeString) {
                return f
            }
            
            for c in f.supportedColorSpaces {
                log.debug("dump color space: \(c.rawValue)")
                if (c == AVCaptureColorSpace.P3_D65) {
                    return f
                }
            }
        }
        
        for f in formats {
            
            let fDesc:CMFormatDescription = f.formatDescription
            let dim = CMVideoFormatDescriptionGetDimensions(fDesc)
            if (dim.width != 3840 && dim.height != 2160) {
                continue
            }
            
            if ("420f" == fDesc.mediaSubType.rawValue.codeString) {
                return f
            }
        }
        
        return nil
    }
    
    
    class func find4kHDR_HLG_BT2020_Format(with formats:Array<AVCaptureDevice.Format>) -> AVCaptureDevice.Format? {
        for f in formats {
            let fDesc:CMFormatDescription = f.formatDescription
            let dim = CMVideoFormatDescriptionGetDimensions(fDesc)
            if (dim.width != 3840 && dim.height != 2160) {
                continue
            }
            
//            log.debug("dump descriptor: \(fDesc)")
//            log.debug("media subtype: \(fDesc.mediaSubType.rawValue.codeString)")
            if ("x420" == fDesc.mediaSubType.rawValue.codeString) {
                return f
            }
            
        }
        
        return nil
    }
    
    class func setHighestVideoCaptureMode(with videoDevice:AVCaptureDevice) {
        do {
            try videoDevice.lockForConfiguration()
            if let f_4k_hlg = CameraUtil.find4kHDR_HLG_BT2020_Format(with: videoDevice.formats) {
                videoDevice.activeFormat = f_4k_hlg
            } else if let f_4k_p3 = CameraUtil.find4kHDR_P3D65_Format(with: videoDevice.formats) {
                videoDevice.activeFormat = f_4k_p3
            }
            videoDevice.unlockForConfiguration()
            log.info("camera format set to: \(videoDevice.activeFormat)")
        } catch {
            log.warning("configure camera failed: \(error)")
        }
    }
}
