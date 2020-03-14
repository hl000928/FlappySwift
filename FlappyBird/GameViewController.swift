//
//  GameViewController.swift
//  FlappyBird
//
//  Created by Nate Murray on 6/2/14.
//  Copyright (c) 2014 Fullstack.io. All rights reserved.
//

import AVFoundation
import SpriteKit
import UIKit
import Vision

extension SKNode {
    class func unarchiveFromFile(_ file: String) -> SKNode? {
        let path = Bundle.main.path(forResource: file, ofType: "sks")

        let sceneData: Data?
        do {
            sceneData = try Data(contentsOf: URL(fileURLWithPath: path!), options: .mappedIfSafe)
        } catch _ {
            sceneData = nil
        }
        let archiver = NSKeyedUnarchiver(forReadingWith: sceneData!)

        archiver.setClass(classForKeyedUnarchiver(), forClassName: "SKScene")
        let scene = archiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as! GameScene
        archiver.finishDecoding()
        return scene
    }
}

class GameViewController: UIViewController {
    @IBOutlet var faceView: FaceView!
    @IBOutlet var skView: SKView!

    var sequenceHandler = VNSequenceRequestHandler()
    let session = AVCaptureSession()
    var previewLayer: AVCaptureVideoPreviewLayer!

    let dataOutputQueue = DispatchQueue(
        label: "video data queue",
        qos: .userInitiated,
        attributes: [],
        autoreleaseFrequency: .workItem)

    var maxX: CGFloat = 0.0
    var midY: CGFloat = 0.0
    var maxY: CGFloat = 0.0
    
    var gameScene: GameScene!

    override func viewDidLoad() {
        super.viewDidLoad()

        if let scene = GameScene.unarchiveFromFile("GameScene") as? GameScene {
            // Configure the view.
            skView.showsFPS = true
            skView.showsNodeCount = true
            skView.allowsTransparency = true

            /* Sprite Kit applies additional optimizations to improve rendering performance */
            skView.ignoresSiblingOrder = true

            /* Set the scale mode to scale to fit the window */
            scene.scaleMode = .aspectFill

            skView.presentScene(scene)
            gameScene = scene
        }

        configureCaptureSession()

        maxX = view.bounds.maxX
        midY = view.bounds.midY
        maxY = view.bounds.maxY

        session.startRunning()
    }

    override var shouldAutorotate: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return UIInterfaceOrientationMask.allButUpsideDown
        } else {
            return UIInterfaceOrientationMask.all
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        gameScene.resetScene()
    }
}

// MARK: - Video Processing methods

extension GameViewController {
    func configureCaptureSession() {
        // Define the capture device we want to use
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front) else {
            fatalError("No front video camera available")
        }

        // Connect the camera to the capture session input
        do {
            let cameraInput = try AVCaptureDeviceInput(device: camera)
            session.addInput(cameraInput)
        } catch {
            fatalError(error.localizedDescription)
        }

        // Create the video data output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: dataOutputQueue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        // Add the video output to the capture session
        session.addOutput(videoOutput)

        let videoConnection = videoOutput.connection(with: .video)
        videoConnection?.videoOrientation = .portrait

        // Configure the preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate methods

extension GameViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 1
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // 2
        let detectFaceRequest = VNDetectFaceRectanglesRequest(completionHandler: detectedFace)

        // 3
        do {
            try sequenceHandler.perform(
                [detectFaceRequest],
                on: imageBuffer,
                orientation: .leftMirrored)
        } catch {
            print(error.localizedDescription)
        }
    }

    func detectedFace(request: VNRequest, error: Error?) {
        // 1
        guard
            let results = request.results as? [VNFaceObservation],
            let result = results.first
        else {
            // 2
            faceView.clear()
            return
        }

        updateFaceView(for: result)
    }

    func updateFaceView(for result: VNFaceObservation) {
      defer {
        DispatchQueue.main.async {
          self.faceView.setNeedsDisplay()
        }
      }

      let box = result.boundingBox
      faceView.boundingBox = convert(rect: box)
        gameScene.birdY = faceView.boundingBox.origin.y + faceView.boundingBox.height / 2
//        gameScene.birdY = 400
    }

    func convert(rect: CGRect) -> CGRect {
      // 1
      let origin = previewLayer.layerPointConverted(fromCaptureDevicePoint: rect.origin)

      // 2
      let size = previewLayer.layerPointConverted(fromCaptureDevicePoint: rect.size.cgPoint)

      // 3
      return CGRect(origin: origin, size: size.cgSize)
    }
}
