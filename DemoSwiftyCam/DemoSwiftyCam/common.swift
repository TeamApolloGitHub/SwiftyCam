//
//  common.swift
//  heic_demo
//
//  Created by Jerry Tian on 2020/11/25.
//

import UIKit
import SwiftyBeaver
import AVFoundation
import VideoToolbox

let log = SwiftyBeaver.self
let cvPxFormat = kCVPixelFormatType_420YpCbCr10BiPlanarFullRange

// Good ones
// 
// kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
// kCVPixelFormatType_64RGBALE
// kCVPixelFormatType_32ARGB

// Bad ones
//
// kCVPixelFormatType_64ARGB: no buffer got
// kCVPixelFormatType_48RGB: no buffer got
// kCVPixelFormatType_32RGBA: wrong buffer, always green.
//

enum ImageCompressionError: Error {
  case NotSupported
  case ImageMissing
  case CanNotFinalize
}

enum VideoCompressionError: Error {
  case NotSupported
  case SessionInitFailure
  case AVWriterInitFailure
  case NoCompressSession
  case CompressionFailure
  case ImageMissing
  case CanNotFinalize
}

enum FrameCaptureStrategy {
    case FromAVAssetImageGenerator
    case FromDisplayLinkCVBuffer
}

enum SessionSetupResult {
    case success
    case notAuthorized
    case configurationFailed
}


extension FourCharCode {
    private static let bytesSize = MemoryLayout<Self>.size
    var codeString: String {
        get {
            withUnsafePointer(to: bigEndian) { pointer in
                pointer.withMemoryRebound(to: UInt8.self, capacity: Self.bytesSize) { bytes in
                    String(bytes: UnsafeBufferPointer(start: bytes,
                                                      count: Self.bytesSize),
                           encoding: .macOSRoman)!
                }
            }
        }
    }
}

extension OSStatus {
    var codeString: String {
        FourCharCode(bitPattern: self).codeString
    }
}

private func fourChars(_ string: String) -> String? {
    string.count == MemoryLayout<FourCharCode>.size ? string : nil
}
private func fourBytes(_ string: String) -> Data? {
    fourChars(string)?.data(using: .macOSRoman, allowLossyConversion: false)
}
func stringCode(_ string: String) -> FourCharCode {
    fourBytes(string)?.withUnsafeBytes { $0.load(as: FourCharCode.self).byteSwapped } ?? 0
}

extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
    
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension AVCaptureDevice.DiscoverySession {
    var uniqueDevicePositionsCount: Int {
        
        var uniqueDevicePositions = [AVCaptureDevice.Position]()
        
        for device in devices where !uniqueDevicePositions.contains(device.position) {
            uniqueDevicePositions.append(device.position)
        }
        
        return uniqueDevicePositions.count
    }
}

extension CVPixelBuffer {
    public enum LockFlag {
        case readwrite
        case readonly
        
        func flag() -> CVPixelBufferLockFlags {
            switch self {
            case .readonly:
                return .readOnly
            default:
                return CVPixelBufferLockFlags.init(rawValue: 0)
            }
        }
    }
    
    public func lock(_ flag: LockFlag, closure: (() -> Void)?) {
        if CVPixelBufferLockBaseAddress(self, flag.flag()) == kCVReturnSuccess {
            if let c = closure {
                c()
            }
        }
        
        CVPixelBufferUnlockBaseAddress(self, flag.flag())
    }
}

struct OrientationHelper {
    // indicate current device is in the LandScape orientation
    static var isLandscape: Bool {
        get {
            return UIDevice.current.orientation.isValidInterfaceOrientation
                ? UIDevice.current.orientation.isLandscape
                : (UIApplication.shared.windows.first?.windowScene?.interfaceOrientation.isLandscape)!
        }
    }
    // indicate current device is in the Portrait orientation
    static var isPortrait: Bool {
        get {
            return UIDevice.current.orientation.isValidInterfaceOrientation
                ? UIDevice.current.orientation.isPortrait
                : (UIApplication.shared.windows.first?.windowScene?.interfaceOrientation.isPortrait)!
        }
    }
}
