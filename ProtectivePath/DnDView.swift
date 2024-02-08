//
//  DnDView.swift
//  ProtectivePath
//
//  Created by Messs  on 5/2/24.
//
import SwiftUI
import RealityKit
import ARKit
import Vision
import AVFoundation

struct DndView: View {
    @State private var detectedObject: String = "No object detected"
    @State private var detectedObjectDistance: Float = 0.0

    var body: some View {
        ZStack {
            ARViewContainer(detectedObject: $detectedObject, detectedObjectDistance: $detectedObjectDistance)
                .edgesIgnoringSafeArea(.all)
            VStack {
                Spacer()
                Text("There is \(detectedObject) in \(String(format: "%.2f", detectedObjectDistance)) meters away from you.")
                    .foregroundColor(.white)
                    .font(.headline)
                    .padding(.bottom, 100)
            }
        }
    }
}

struct ARViewContainer: UIViewRepresentable {
    @Binding var detectedObject: String
    @Binding var detectedObjectDistance: Float

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic

        arView.session.delegate = context.coordinator
        arView.session.run(config)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    func makeCoordinator() -> ARSessionDelegateCoordinator {
        return ARSessionDelegateCoordinator(detectedObject: $detectedObject, detectedObjectDistance: $detectedObjectDistance)
    }
}

class ARSessionDelegateCoordinator: NSObject, ARSessionDelegate {
    @Binding var detectedObject: String
    @Binding var detectedObjectDistance: Float
    var objectDetectionModel: VNCoreMLModel!
    var closestDistance: Float = Float.greatestFiniteMagnitude // Declare at the class level

    // AVSpeechSynthesizer instance for text-to-speech
    let speechSynthesizer = AVSpeechSynthesizer()
    
    // Timer property for periodic announcements
    var announcementTimer: Timer?

    init(detectedObject: Binding<String>, detectedObjectDistance: Binding<Float>) {
        _detectedObject = detectedObject
        _detectedObjectDistance = detectedObjectDistance

        // Load the Core ML model
        guard let model = try? VNCoreMLModel(for: YOLOv3TinyInt8LUT__1_().model) else {
            fatalError("Failed to load Core ML model.")
        }
        objectDetectionModel = model
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let currentPointCloud = frame.rawFeaturePoints else { return }
        let cameraTransform = frame.camera.transform

        closestDistance = Float.greatestFiniteMagnitude // Reset closestDistance

        for point in currentPointCloud.points {
            let pointInCameraSpace = cameraTransform.inverse * simd_float4(point, 1)
            let distanceToCamera = sqrt(pointInCameraSpace.x * pointInCameraSpace.x + pointInCameraSpace.y * pointInCameraSpace.y + pointInCameraSpace.z * pointInCameraSpace.z)

            if distanceToCamera < closestDistance {
                closestDistance = distanceToCamera
            }
        }

        // Perform object detection and update the detectedObject and detectedObjectDistance
        detectObjectDistance(frame.capturedImage)

        // Start the announcement timer if not already started
        if announcementTimer == nil {
            announcementTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.speakDetectedObjectAndDistance()
            }
        }
    }


    func detectObjectDistance(_ image: CVPixelBuffer) {
        let request = VNCoreMLRequest(model: objectDetectionModel) { [weak self] (finishedRequest, error) in
            guard let results = finishedRequest.results as? [VNRecognizedObjectObservation], let detectedObject = results.first?.labels.first?.identifier else {
                return
            }

            DispatchQueue.main.async {
                // Update the detectedObject and detectedObjectDistance only if the object is found
                self?.detectedObject = detectedObject
                self?.detectedObjectDistance = self?.closestDistance ?? 0.0
            }
        }

        try? VNImageRequestHandler(cvPixelBuffer: image, options: [:]).perform([request])
    }

    // Function to speak the detected object and its distance
    @objc func speakDetectedObjectAndDistance() {
        let objectString = detectedObject
        let distanceString = String(format: "%.2f", detectedObjectDistance)

        let announcement = "There is \(objectString) in \(distanceString) meters away from you."
        let speechUtterance = AVSpeechUtterance(string: announcement)

        // Configure speech parameters if needed
        speechUtterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechUtterance.volume = 1.0
        speechUtterance.pitchMultiplier = 1.0

        // Speak the announcement
        speechSynthesizer.speak(speechUtterance)
    }

    deinit {
        // Invalidate the timer to prevent memory leaks
        announcementTimer?.invalidate()
        announcementTimer = nil
    }
}

struct ViewContainer: PreviewProvider {
    static var previews: some View {
        DndView()
    }
}
