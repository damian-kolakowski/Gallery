import Foundation
import AVFoundation
import Photos

public class ClosuredAVCaptureMovieFileOutput: NSObject, AVCaptureFileOutputRecordingDelegate {
    
  private let output: AVCaptureMovieFileOutput
  private let queue: DispatchQueue
  
  private var videoRecordStartedCompletion: ((Bool) -> Void)?
  private var videoRecordCompletion: ((URL?) -> Void)?
  
  public init(sessionQueue: DispatchQueue) {
    self.queue = sessionQueue
    self.output = AVCaptureMovieFileOutput()
    self.output.minFreeDiskSpaceLimit = 1024 * 1024
    self.output.movieFragmentInterval = CMTime.invalid
    
    if let maxLengthInSecondsFound = Config.VideoRecording.maxLengthInSeconds {
        self.output.maxRecordedDuration = CMTimeMakeWithSeconds(Float64(maxLengthInSecondsFound), preferredTimescale: Int32(30))
    }
    
    if let maxBytesCountFound = Config.VideoRecording.maxBytesCount {
      self.output.maxRecordedFileSize = maxBytesCountFound
    }
  }
  
  public func addToSession(_ session: AVCaptureSession) {
    if session.canAddOutput(output) {
      session.addOutput(output)
    }
    
    if Permission.Microphone.hasPermission {
      if let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio) {
        if let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
          if session.canAddInput(audioInput){
            session.addInput(audioInput)
          }
        }
      }
    }
  }
  
  public func isRecording() -> Bool {
    return output.isRecording
  }
  
  public func startRecording(startCompletion: ((Bool) -> Void)?, stopCompletion: ((URL?) -> Void)?) {
    
    guard let connection = output.connection(with: AVMediaType.video) else {
      startCompletion?(false)
      return
    }
    
    connection.videoOrientation = Utils.videoOrientation()
    
    self.videoRecordCompletion = stopCompletion
    
    queue.async {
        if let url = NSURL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(UUID().uuidString + ".mov") {
        if FileManager.default.fileExists(atPath: url.absoluteString) {
          try? FileManager.default.removeItem(at: url)
        }
        self.videoRecordStartedCompletion = startCompletion
        self.output.startRecording(to: url, recordingDelegate: self)
      } else {
        DispatchQueue.main.async { startCompletion?(false) }
      }
    }
  }
  
  public func stopVideoRecording() {
    queue.async {
      self.output.stopRecording()
    }
  }
    
  public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
     self.videoRecordStartedCompletion?(false)
     self.videoRecordStartedCompletion = nil
  }

  public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
    if error == nil {
      DispatchQueue.main.async {
        self.videoRecordCompletion?(outputFileURL)
        self.videoRecordCompletion = nil
      }
    } else {
      let finishedSuccesfully = recodringFinishedWithSuccess(error!)
      DispatchQueue.main.async {
        self.videoRecordCompletion?(finishedSuccesfully ? outputFileURL : nil)
        self.videoRecordCompletion = nil
      }
    }
  }
  
  private func recodringFinishedWithSuccess(_ error: Error) -> Bool {
    let nserror = error as NSError
    let success = nserror.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool
    if nserror.domain == AVFoundationErrorDomain, let successFound = success, successFound {
      return true
    }
    return false
  }
}
