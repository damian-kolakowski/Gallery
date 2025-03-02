import Foundation
import UIKit
import AVFoundation
import AVKit
import QuartzCore

class CameraController: UIViewController {

  var locationManager: LocationManager?
  lazy var cameraMan: CameraMan = self.makeCameraMan()
  lazy var cameraView: CameraView = self.makeCameraView()
  lazy var videoBox: VideoBox = self.makeVideoBox()
  
  let once = Once()

  // MARK: - Life cycle

  override func viewDidLoad() {
    super.viewDidLoad()

    setup()
    setupLocation()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)

    locationManager?.start()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)

    locationManager?.stop()
  }

  // MARK: - Setup

  func setup() {
    view.addSubview(cameraView)
    cameraView.g_pinEdges()
    
    if Config.Camera.recordMode == .video {
    
      cameraView.bottomView.addSubview(videoBox)
      
      videoBox.g_pin(size: CGSize(width: 44, height: 44))
      videoBox.g_pin(on: .centerY)
      videoBox.g_pin(on: .left, constant: 38)
    }

    cameraView.closeButton.addTarget(self, action: #selector(closeButtonTouched(_:)), for: .touchUpInside)
    cameraView.flashButton.addTarget(self, action: #selector(flashButtonTouched(_:)), for: .touchUpInside)
    cameraView.rotateButton.addTarget(self, action: #selector(rotateButtonTouched(_:)), for: .touchUpInside)
    cameraView.stackView.addTarget(self, action: #selector(stackViewTouched(_:)), for: .touchUpInside)
    cameraView.shutterButton.addTarget(self, action: #selector(shutterButtonTouched(_:)), for: .touchUpInside)
    cameraView.doneButton.addTarget(self, action: #selector(doneButtonTouched(_:)), for: .touchUpInside)
  }

  @objc func setupLocation() {
    if Config.Camera.recordLocation {
      locationManager = LocationManager()
    }
  }

  // MARK: - Action

  @objc func closeButtonTouched(_ button: UIButton) {
    EventHub.shared.close?()
  }

  @objc func flashButtonTouched(_ button: UIButton) {
    cameraView.flashButton.toggle()

    if let flashMode = AVCaptureDevice.FlashMode(rawValue: cameraView.flashButton.selectedIndex) {
      cameraMan.flash(flashMode)
    }
  }

  @objc func rotateButtonTouched(_ button: UIButton) {
    UIView.animate(withDuration: 0.3, animations: {
      self.cameraView.rotateOverlayView.alpha = 1
    }, completion: { _ in
      self.cameraMan.switchCamera {
        UIView.animate(withDuration: 0.7, animations: {
          self.cameraView.rotateOverlayView.alpha = 0
        }) 
      }
    })
  }

  @objc func stackViewTouched(_ stackView: StackView) {
    EventHub.shared.stackViewTouched?()
  }

    
  @objc func shutterButtonTouched(_ button: ShutterButton) {
    guard let previewLayer = cameraView.previewLayer else { return }
    
    switch Config.Camera.recordMode {
    case .photo:
        
      if let limit = Config.selectionLimit, Cart.shared.images.count >= limit {
        EventHub.shared.reachedSelectionLimit?()
        return
      }
      
      button.isEnabled = false
      UIView.animate(withDuration: 0.1, animations: {
        self.cameraView.shutterOverlayView.alpha = 1
      }, completion: { _ in
        UIView.animate(withDuration: 0.1, animations: {
          self.cameraView.shutterOverlayView.alpha = 0
        })
      })
      
      self.cameraView.stackView.startLoading()
      cameraMan.takePhoto(previewLayer, location: locationManager?.latestLocation) { asset in
        button.isEnabled = true
        self.cameraView.stackView.stopLoading()
        
        if let asset = asset {
          Cart.shared.add(Image(asset: asset), newlyTaken: true)
        }
      }
    case .video:
      
      if self.cameraMan.isRecording() {
        button.isEnabled = false
        self.cameraView.morphToVideoRecordingSavingStarted()
        self.cameraMan.stopVideoRecording()
      } else {
        button.isEnabled = false
        self.cameraMan.startVideoRecord(location: locationManager?.latestLocation, startCompletion: { result in
          button.isEnabled = true
          self.cameraView.morphToVideoRecordingStarted()
        }, stopCompletion: { asset in
          button.isEnabled = true
          self.cameraView.morphToVideoRecordingSavingDone()
          if let asset = asset {
            Cart.shared.setVideo(Video(asset: asset))
          }
      
        })
      }
    }
  }
  
  func stopVideoRecordingIfStarted() {
    if self.cameraMan.isRecording() {
      self.cameraMan.stopVideoRecording()
      self.cameraView.morphToVideoRecordingReset()
    }
  }

  @objc func doneButtonTouched(_ button: UIButton) {
      switch Config.Camera.recordMode {
      case .photo:
          EventHub.shared.doneWithImages?()
      case .video:
          EventHub.shared.doneWithVideos?()
      }
  }

  // MARK: - View

  func refreshView() {
    let hasImages = !Cart.shared.images.isEmpty
    cameraView.bottomView.g_fade(visible: hasImages)
  }

  // MARK: - Controls

  func makeCameraMan() -> CameraMan {
    let man = CameraMan()
    man.delegate = self

    return man
  }

  func makeCameraView() -> CameraView {
    let view = CameraView()
    view.delegate = self

    return view
  }
  
  func makeVideoBox() -> VideoBox {
    let videoBox = VideoBox()
    videoBox.delegate = self
    
    return videoBox
  }
}

extension CameraController: CartDelegate {
  
  func cart(_ cart: Cart, didSet video: Video) {
    self.videoBox.imageView.g_loadImage(video.asset)
  }

  func cart(_ cart: Cart, didAdd image: Image, newlyTaken: Bool) {
    cameraView.stackView.reload(cart.images, added: true)
    refreshView()
  }

  func cart(_ cart: Cart, didRemove image: Image) {
    cameraView.stackView.reload(cart.images)
    refreshView()
  }

  func cartDidReload(_ cart: Cart) {
    cameraView.stackView.reload(cart.images)
    refreshView()
  }
}

extension CameraController: PageAware {
  
  func pageDidHide() {
    self.stopVideoRecordingIfStarted()
  }

  func pageDidShow() {
    once.run {
      cameraMan.setup()
    }
  }
  
  
}

extension CameraController: CameraViewDelegate {

  func cameraView(_ cameraView: CameraView, didTouch point: CGPoint) {
    cameraMan.focus(point)
  }
}

extension CameraController: CameraManDelegate {

  func cameraManDidStart(_ cameraMan: CameraMan) {
    cameraView.setupPreviewLayer(cameraMan.session)
  }

  func cameraManNotAvailable(_ cameraMan: CameraMan) {
    cameraView.focusImageView.isHidden = true
  }

  func cameraMan(_ cameraMan: CameraMan, didChangeInput input: AVCaptureDeviceInput) {
    cameraView.flashButton.isHidden = !input.device.hasFlash
  }

}

extension CameraController: VideoBoxDelegate {
  
  func videoBoxDidTap(_ videoBox: VideoBox) {
    Cart.shared.video?.fetchPlayerItem { item in
      guard let item = item else { return }
      
      DispatchQueue.main.async {
        let controller = AVPlayerViewController()
        let player = AVPlayer(playerItem: item)
        controller.player = player
        
        self.present(controller, animated: true) {
          player.play()
        }
      }
    }
  }
}
