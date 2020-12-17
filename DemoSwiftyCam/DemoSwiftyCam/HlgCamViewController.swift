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

class HlgCamViewController: SwiftyCamViewController, SwiftyCamViewControllerDelegate {
    
    @IBOutlet weak var captureButton    : SwiftyRecordButton!
    @IBOutlet weak var flipCameraButton : UIButton!
    @IBOutlet weak var flashButton      : UIButton!
    
    private var saveThisFrame = false
    private var workOnSaving = false
    
    private var vtbCompressor:VideoToolBoxCompressor? = nil
    private var vtbFailureAlert:Bool = false
    
	override func viewDidLoad() {
		super.viewDidLoad()
        shouldPrompToAppSettings = true
		cameraDelegate = self
		maximumVideoDuration = 10.0
        shouldUseDeviceOrientation = true
        allowAutoRotate = false
        audioEnabled = true
        flashMode = .auto
        flashButton.setImage(#imageLiteral(resourceName: "flashauto"), for: UIControl.State())
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
        switchCamera()
    }
    
    @IBAction func toggleFlashTapped(_ sender: Any) {
        //flashEnabled = !flashEnabled
        toggleFlashAnimation()
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
        
        if (self.workOnSaving) {
            return
        }
        
        if (self.saveThisFrame == false) {
            return
        }
        
        self.workOnSaving = true
        self.saveThisFrame = false
        
//        log.info("got sample buffer: \(sampleBuffer)")
        
        self.vtbCompressor = VideoToolBoxCompressor()
        self.vtbCompressor?.expectingSingleFrame = true
        self.vtbCompressor?.compressQuality = UserDefaults.standard.double(forKey: "quality_preference")
        self.vtbCompressor?.forceAVCCodec = UserDefaults.standard.bool(forKey: "avc_preference")
        
        self.vtbCompressor?.imageOrientOpt =  self.orientation.getImageOrientation(forCamera: self.currentCamera)
        self.vtbCompressor?.videoOrientOpt = self.orientation.getVideoOrientation()!
        
        log.info("image orientation: \(self.vtbCompressor!.imageOrientOpt.rawValue)")
        log.info("video orientation: \(self.vtbCompressor!.videoOrientOpt.rawValue)")
        log.info("compress quality: \(self.vtbCompressor!.compressQuality), force AVC: \(self.vtbCompressor!.forceAVCCodec)")
        
        self.vtbCompressor?.vtbPrepareEncoding(for: sampleBuffer, completion: { (e) in
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
        
        self.workOnSaving = false
    }
    
    override public func buttonWasTapped() {
        if (self.workOnSaving) {
            return
        }
        
        self.saveThisFrame = true
    }
}


// UI Animations
extension HlgCamViewController {
    
    fileprivate func hideButtons() {
        UIView.animate(withDuration: 0.25) {
            self.flashButton.alpha = 0.0
            self.flipCameraButton.alpha = 0.0
        }
    }
    
    fileprivate func showButtons() {
        UIView.animate(withDuration: 0.25) {
            self.flashButton.alpha = 1.0
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
    
    fileprivate func toggleFlashAnimation() {
        //flashEnabled = !flashEnabled
        if flashMode == .auto{
            flashMode = .on
            flashButton.setImage(#imageLiteral(resourceName: "flash"), for: UIControl.State())
        }else if flashMode == .on{
            flashMode = .off
            flashButton.setImage(#imageLiteral(resourceName: "flashOutline"), for: UIControl.State())
        }else if flashMode == .off{
            flashMode = .auto
            flashButton.setImage(#imageLiteral(resourceName: "flashauto"), for: UIControl.State())
        }
    }
}

