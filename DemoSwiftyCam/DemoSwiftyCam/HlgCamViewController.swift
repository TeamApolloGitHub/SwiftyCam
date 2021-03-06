/*Copyright (c) 2016, Andrew Walz.

Redistribution and use in source and binary forms, with or without modification,are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS
BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */


import UIKit
import AVFoundation
import PhotosUI
import VideoToolBoxHelper

extension UIView {
  
    func getViewsByTag(tag:Int) -> Array<UIView> {
        var out = Array<UIView>()
        let found = subviews.filter { ($0 as UIView).tag == tag } as [UIView]
        out.append(contentsOf: found)
        for v in self.subviews {
            out.append(contentsOf: v.getViewsByTag(tag: tag))
        }
        return out
    }
    
    @IBInspectable var cornerRadiusV: CGFloat {
        get {
            return layer.cornerRadius
        }
        set {
            layer.cornerRadius = newValue
            layer.masksToBounds = newValue > 0
        }
    }

    @IBInspectable var borderWidthV: CGFloat {
        get {
            return layer.borderWidth
        }
        set {
            layer.borderWidth = newValue
        }
    }

    @IBInspectable var borderColorV: UIColor? {
        get {
            return UIColor(cgColor: layer.borderColor!)
        }
        set {
            layer.borderColor = newValue?.cgColor
        }
    }
    
}

class HlgCamViewController: SwiftyCamViewController, SwiftyCamViewControllerDelegate {
    
    
    let longestShutterSpeed = Double(1.0/30.0)
    
    @IBOutlet weak var captureButton    : SwiftyRecordButton!
    @IBOutlet weak var flipCameraButton : UIButton!
    
    @IBOutlet weak var previewButton : UIButton!
    
    
    @IBOutlet weak var zoom1_Btn    : UIButton!
    @IBOutlet weak var zoom2_Btn    : UIButton!
    @IBOutlet weak var zoom3_Btn    : UIButton!
    
    @IBOutlet private weak var iosAndSpeedALabel: UILabel?
    private var exposureSetItem:DispatchWorkItem?
    
    private func advCtrls() -> Array<UIView> {
        return self.view.getViewsByTag(tag: 100)
    }
    
    let backCameraOpts = [
        AVCaptureDevice.DeviceType.builtInUltraWideCamera,
        AVCaptureDevice.DeviceType.builtInWideAngleCamera,
        AVCaptureDevice.DeviceType.builtInTelephotoCamera,
    ]
    
    var availableCameraOpts:Array<AVCaptureDevice.DeviceType> = Array<AVCaptureDevice.DeviceType>()

    private func toggleBackCameraBtns() {
        let btns = [self.zoom1_Btn, self.zoom2_Btn, self.zoom3_Btn]
        
        if currentCamera == .front {
            for btn in btns {
                btn?.isHidden = true
            }
            
            return
        }
        
        var idx = 0
        availableCameraOpts.removeAll()
        for t in self.backCameraOpts {
            let btn = btns[idx]!
            if let _ = AVCaptureDevice.default(t, for: .video, position: .back) {
                availableCameraOpts.append(t)
            }
            
            if (self.videoDevice?.deviceType == t) {
                btn.isHidden = false
            } else {
                btn.isHidden = true
            }
            idx += 1
        }
        
        if (availableCameraOpts.count <= 1) {
            for btn in btns {
                btn?.isHidden = true
            }
        }
    }
    
    private var saveThisFrame = false
    
    private var vtbCompressor:VideoToolBoxCompressor? = nil
    private var vtbFailureAlert:Bool = false
    
	override func viewDidLoad() {
		super.viewDidLoad()
        shouldPrompToAppSettings = true
		cameraDelegate = self
		maximumVideoDuration = 10.0
        shouldUseDeviceOrientation = true
        allowAutoRotate = true
        audioEnabled = true
        flashMode = .auto
        captureButton.buttonEnabled = false
	}

	override var prefersStatusBarHidden: Bool {
		return true
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
        captureButton.delegate = self
	}
    
    func swiftyCamSessionDidStartRunning(_ swiftyCam: SwiftyCamViewController) {
        log.info("Session did start running")
        captureButton.buttonEnabled = true
        
        self.toggleBackCameraBtns()
    }
    
    func swiftyCamSessionDidStopRunning(_ swiftyCam: SwiftyCamViewController) {
        log.info("Session did stop running")
        captureButton.buttonEnabled = false
    }
    

	func swiftyCam(_ swiftyCam: SwiftyCamViewController, didTake photo: UIImage) {
//		let newVC = PhotoViewController(image: photo)
//		self.present(newVC, animated: true, completion: nil)
	}

	func swiftyCam(_ swiftyCam: SwiftyCamViewController, didBeginRecordingVideo camera: SwiftyCamViewController.CameraSelection) {
		log.info("Did Begin Recording")
		captureButton.growButton()
        hideButtons()
	}

	func swiftyCam(_ swiftyCam: SwiftyCamViewController, didFinishRecordingVideo camera: SwiftyCamViewController.CameraSelection) {
		log.info("Did finish Recording")
		captureButton.shrinkButton()
        showButtons()
	}

	func swiftyCam(_ swiftyCam: SwiftyCamViewController, didFinishProcessVideoAt url: URL) {
//		let newVC = VideoViewController(videoURL: url)
//		self.present(newVC, animated: true, completion: nil)
	}

	func swiftyCam(_ swiftyCam: SwiftyCamViewController, didFocusAtPoint point: CGPoint) {
        log.info("Did focus at point: \(point)")
        focusAnimationAt(point)
	}
    
    func swiftyCamDidFailToConfigure(_ swiftyCam: SwiftyCamViewController) {
        let message = NSLocalizedString("Unable to capture media", comment: "Alert message when something goes wrong during capture session configuration")
        let alertController = UIAlertController(title: "AVCam", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
        present(alertController, animated: true, completion: nil)
    }

	func swiftyCam(_ swiftyCam: SwiftyCamViewController, didChangeZoomLevel zoom: CGFloat) {
        log.info("Zoom level did change. Level: \(zoom)")
		log.info(zoom)
	}

	func swiftyCam(_ swiftyCam: SwiftyCamViewController, didSwitchCameras camera: SwiftyCamViewController.CameraSelection) {
        log.info("Camera did change to \(camera.rawValue)")
		log.info(camera)
	}
    
    func swiftyCam(_ swiftyCam: SwiftyCamViewController, didFailToRecordVideo error: Error) {
        log.info(error)
    }

    @IBAction func cameraSwitchTapped(_ sender: Any) {
        switchCamera(nil, completion: {_ in })
    }
    
    
    private func saveFrameMovToCameraRoll(movFile:URL, pngFile:URL) {
        // Check the authorization status.
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                // Save the movie file to the photo library and cleanup.
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.shouldMoveFile = true
                    
                    let pngCreation = PHAssetCreationRequest.forAsset()
                    pngCreation.addResource(with: .photo, fileURL: pngFile, options: options)
                    
                    let movCreation = PHAssetCreationRequest.forAsset()
                    movCreation.addResource(with: .video, fileURL: movFile, options: options)
                }, completionHandler: { success, error in
                    
                    
                    if !success {
                        log.warning("couldn't save the movie to your photo library: \(String(describing: error))")
                        DispatchQueue.main.sync {
                            MediaUtil.systemShareAction(url: movFile, from: self.view)
                        }
                    }
                })
            }
        }
    }
    
    public func swiftyCamCaptureOutput(_ output:AVCaptureOutput, didOutput sampleBuffer:CMSampleBuffer, from connection:AVCaptureConnection) {
        
        if let _ = self.vtbCompressor {
            return
        }
        
        if (self.saveThisFrame == false) {
            return
        }
        
        self.saveThisFrame = false
        self.vtbCompressor = VideoToolBoxCompressor()
        
//        log.info("got sample buffer: \(sampleBuffer)")
        
        
        self.vtbCompressor?.expectingSingleFrame = true
        self.vtbCompressor?.saveExtraStillImageFrame = true
        self.vtbCompressor?.compressQuality = 0.9
        
        self.vtbCompressor?.imageOrientOpt =  self.orientation.getImageOrientation(forCamera: self.currentCamera)
        self.vtbCompressor?.videoOrientOpt = self.orientation.getVideoOrientation()!
        
        log.info("image orientation: \(self.vtbCompressor!.imageOrientOpt.rawValue)")
        log.info("video orientation: \(self.vtbCompressor!.videoOrientOpt.rawValue)")
        log.info("compress quality: \(self.vtbCompressor!.compressQuality), force AVC: \(String(describing: self.vtbCompressor?.codecProfile))")
        
        self.vtbCompressor?.vtbPrepareEncoding(for: sampleBuffer, completion: { (e) in
            
            defer {
                DispatchQueue.main.async {
                    if let thumb = self.vtbCompressor?.targetThumb {
                        for s:UIControl.State in [.normal, .focused, .highlighted, .selected] {
                            self.previewButton.imageView?.contentMode = .scaleAspectFill
                            self.previewButton.setImage(thumb, for: s)
//                            self.previewButton.setImage(nil, for: s)
//                            self.previewButton.setBackgroundImage(thumb, for: s)
                        }
                    }
                    
                    self.vtbCompressor = nil
                }
            }
            if let error = e {
                log.error("failed to save pixel buffer as mov file: \(error)")
                if (self.vtbFailureAlert) {
                    return
                }
                
                self.vtbFailureAlert = true
                DispatchQueue.main.async {
                    let errorAlert = UIAlertController(title: "Failed", message: "Unable to capture this frame: \(error)", preferredStyle: UIAlertController.Style.alert)

                    errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: { (action: UIAlertAction!) in
                        self.vtbFailureAlert = false
                    }))

                    self.present(errorAlert, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.saveFrameMovToCameraRoll(
                        movFile:self.vtbCompressor!.outputMovURL!,
                        pngFile:self.vtbCompressor!.outputJpegURL!
                    )
                }
            }
        })
        
        self.vtbCompressor?.vtbEncodeFrame(buffer: sampleBuffer)
        self.vtbCompressor?.vtbFinishEncoding()
    }
    
    override public func buttonWasTapped() {
        if let _ = self.vtbCompressor {
            return
        }
        
        self.saveThisFrame = true
        self.captureButton.growButton()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.captureButton.shrinkButton()
        }
    }
}


// UI Animations
extension HlgCamViewController {
    
    fileprivate func hideButtons() {
        UIView.animate(withDuration: 0.25) {
            self.flipCameraButton.alpha = 0.0
        }
    }
    
    fileprivate func showButtons() {
        UIView.animate(withDuration: 0.25) {
            self.flipCameraButton.alpha = 1.0
        }
    }
    
    fileprivate func focusAnimationAt(_ point: CGPoint) {
        let focusView = UIImageView(image: #imageLiteral(resourceName: "focus"))
        focusView.center = point
        focusView.alpha = 0.0
        view.addSubview(focusView)
        
        UIView.animate(withDuration: 0.25, delay: 0.0, options: .curveEaseInOut, animations: {
            focusView.alpha = 1.0
            focusView.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        }) { (success) in
            UIView.animate(withDuration: 0.15, delay: 0.5, options: .curveEaseInOut, animations: {
                focusView.alpha = 0.0
                focusView.transform = CGAffineTransform(translationX: 0.6, y: 0.6)
            }) { (success) in
                focusView.removeFromSuperview()
            }
        }
    }
    
}


extension HlgCamViewController {
    
    
    @IBAction func chooseNextAvailableCamera(_ sender:Any) {
        if self.availableCameraOpts.count <= 1 {
            return
        }
        
        var cameraId = 0
        var idx = 0
        for t in self.availableCameraOpts {
            if self.videoDevice?.deviceType == t {
                cameraId = idx
                break
            }
            
            idx+=1
        }
        
        cameraId = (cameraId+1)%self.availableCameraOpts.count
        
        let t = self.availableCameraOpts[cameraId]
        self.switchCamera(t, completion: {ok in
            DispatchQueue.main.async {
                self.toggleBackCameraBtns()
            }
        })
    }
    
    @IBAction func chooseLeftExpBias(_ sender:Any) {
        self.adjustExposureBias(-1)
    }
    
    @IBAction func chooseRightExpBias(_ sender:Any) {
        self.adjustExposureBias(1)
    }
    
    
    @IBAction func chooseFasterShutter(_ sender:Any) {
        self.iosAndSpeedALabel?.text = self.formatISO_ShutterSpeed()
        
        self.adjustExposure(-1)
    }
    
    
    @IBAction func chooseSlowerShutter(_ sender:Any) {
        self.iosAndSpeedALabel?.text = self.formatISO_ShutterSpeed()
        
        self.adjustExposure(1)
    }
    
    
    
    @IBAction func resetShutter(_ sender:Any) {
        self.iosAndSpeedALabel?.text = self.formatISO_ShutterSpeed()
        
        self.adjustExposure(0)
    }
    
    private func chooseProperISO(_ target:Float, of device:AVCaptureDevice) -> Float {
        if (target < device.activeFormat.minISO) {
            return device.activeFormat.minISO
        }
        
        if (target > device.activeFormat.maxISO) {
            return device.activeFormat.maxISO
        }
        
        return target
    }
    
    private func chooseProperExpBias(_ target:Float, of device:AVCaptureDevice) -> Float {
        let minBias = device.minExposureTargetBias
        let maxBias = device.maxExposureTargetBias
        
        if (target < minBias) {
            return minBias
        }
        
        if (target > maxBias) {
            return maxBias
        }
        
        return target
    }
    
    private func chooseProperShutterSpeed(_ target:CMTime, of device:AVCaptureDevice) -> CMTime {
        let speed = Double(Double(target.value)/Double(target.timescale))
        
        let min = device.activeFormat.minExposureDuration
        let minSpeed = Double(Double(min.value)/Double(min.timescale))
        
        let max = device.activeFormat.maxExposureDuration
        let maxSpeed = Double(Double(max.value)/Double(max.timescale))
        
        log.info("min: \(minSpeed), max: \(maxSpeed), target: \(speed)")
        
        if (speed < minSpeed) {
            return min
        }
        
        if (speed > maxSpeed) {
            return max
        }
        
        if (speed > longestShutterSpeed) {
            return CMTimeMake(value: Int64(Double(target.timescale)*longestShutterSpeed), timescale: target.timescale)
        }
        
        return target
    }
    
    private func adjustExposure(_ relativeExp:Int) {
        if let _ = self.exposureSetItem {
            return
        }
        
        self.exposureSetItem = DispatchWorkItem(block: {
            defer {
                self.exposureSetItem = nil
            }
            
            guard let captureDevice = self.videoDevice else {
                return
            }
            
            do {
                try captureDevice.lockForConfiguration()
                
                if (relativeExp == 0) {
                    captureDevice.exposureMode = .continuousAutoExposure
                } else {
                    var iso = captureDevice.iso, shutter = captureDevice.exposureDuration
                    
                    if (relativeExp < 0) {//increase shutter speed
                        iso = iso * 2
                        shutter.value = shutter.value/2
                    } else {//decrease shutter speed
                        iso = iso / 2
                        shutter.value = shutter.value*2
                    }
                    
                    iso = self.chooseProperISO(iso, of: captureDevice)
                    shutter = self.chooseProperShutterSpeed(shutter, of: captureDevice)
                    
                    log.info("locked exposure supported? \(captureDevice.isExposureModeSupported(.locked))")
                    log.info("autoExpose exposure supported? \(captureDevice.isExposureModeSupported(.autoExpose))")
                    log.info("continuousAutoExposure exposure supported? \(captureDevice.isExposureModeSupported(.continuousAutoExposure))")
                    log.info("custom exposure supported? \(captureDevice.isExposureModeSupported(.custom))")
                    captureDevice.exposureMode = .custom
                    
                    if (captureDevice.isExposureModeSupported(.custom)) {//not working with virtual dual/triple camera.
                        captureDevice.setExposureModeCustom(duration: shutter, iso: iso) { (exp:CMTime) in
                            DispatchQueue.main.async {
                                self.iosAndSpeedALabel?.text = self.formatISO_ShutterSpeed()
                            }
                        }
                    }
                    
                }
                captureDevice.unlockForConfiguration()
            } catch {
                log.warning("configure for exposure failed: \(error)")
            }
        })
        
        sessionQueue.async(execute:self.exposureSetItem!)
    }
    
    // -1, 0, 1
    private func adjustExposureBias(_ targetExpBias:Int) {
        if let _ = self.exposureSetItem {
            return
        }
        
        self.exposureSetItem = DispatchWorkItem(block: {
            defer {
                self.exposureSetItem = nil
            }
            
            guard let captureDevice = self.videoDevice else {
                return
            }
            
            do {
                try captureDevice.lockForConfiguration()
                var currentBias = captureDevice.exposureTargetBias
                
                if (targetExpBias == 0) {
                    currentBias = 0
                    captureDevice.exposureMode  = .continuousAutoExposure
                } else if (targetExpBias > 0) {
                    currentBias += 1.0/3
                    captureDevice.exposureMode  = .autoExpose
                } else {
                    currentBias -= 1.0/3
                    captureDevice.exposureMode  = .autoExpose
                }
                
                log.info("set exposure bias to \(currentBias)")
                currentBias = self.chooseProperExpBias(currentBias, of: captureDevice)
                
                captureDevice.setExposureTargetBias(currentBias) { (exp) in
                    DispatchQueue.main.async {
                        self.iosAndSpeedALabel?.text = self.formatISO_ShutterSpeed()
                    }
                }
                
                captureDevice.unlockForConfiguration()
            } catch {
                log.warning("configure for exposure bias failed: \(error)")
            }
        })
        
        sessionQueue.async(execute:self.exposureSetItem!)
    }
    
    private func formatISO_ShutterSpeed() -> String {
        var iso = 0, shutter = 0
        if let device = self.videoDevice {
            iso = Int(device.iso)
            let t = device.exposureDuration
            shutter = Int((Int64(t.timescale)/t.value))
        }
        return "ISO: \(iso)/SHUTTER: 1/\(shutter)"
    }
    
    @IBAction func toggleMoreCtrls(_ sender:Any) {
        let ctrls = self.advCtrls()
        
        var active = false
        for v in ctrls {
            if v.isHidden == false {
                active = true
                break
            }
        }
        
        if active {
            for v in ctrls {
                v.isHidden = true
            }
        } else {
            for v in ctrls {
                v.isHidden = false
            }
        }
    }
    
    @IBAction func openGallery(_ sender:Any) {
        UIApplication.shared.open(URL(string: "photos-redirect://")!)
    }
}
