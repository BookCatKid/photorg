import SwiftUI
import AVFoundation
import UIKit

/// Full-screen in-app camera. On capture, calls `onCapture(data, orientation)` with the
/// raw HEIC (or JPEG fallback) bytes — we write them to disk untouched.
struct CameraView: View {
    let onCapture: (Data, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cam = CameraController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: cam.session)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                    Button {
                        cam.toggleCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(.black.opacity(0.4), in: Circle())
                    }
                }
                .padding()
                Spacer()
                Button {
                    cam.capture { data, orientation in
                        guard let data else { return }
                        onCapture(data, orientation)
                        // Stay open so user can keep shooting into the same collection.
                    }
                } label: {
                    ZStack {
                        Circle().stroke(Color.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(Color.white).frame(width: 66, height: 66)
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .task { await cam.start() }
        .onDisappear { cam.stop() }
        .statusBarHidden()
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.videoPreviewLayer.session = session
        v.videoPreviewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

@MainActor
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.session")
    private let output = AVCapturePhotoOutput()
    private var currentInput: AVCaptureDeviceInput?
    private var position: AVCaptureDevice.Position = .back
    private var captureCompletion: ((Data?, Int) -> Void)?

    func start() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                self?.configure()
                self?.session.startRunning()
                cont.resume()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.session.stopRunning()
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        if let currentInput { session.removeInput(currentInput) }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration(); return
        }
        session.addInput(input)
        currentInput = input
        if !session.outputs.contains(output), session.canAddOutput(output) {
            session.addOutput(output)
        }
        if output.availablePhotoCodecTypes.contains(.hevc) {
            output.maxPhotoQualityPrioritization = .quality
        }
        session.commitConfiguration()
    }

    func toggleCamera() {
        position = (position == .back) ? .front : .back
        queue.async { [weak self] in self?.configure() }
    }

    func capture(completion: @escaping (Data?, Int) -> Void) {
        captureCompletion = completion
        let settings: AVCapturePhotoSettings
        if output.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.photoQualityPrioritization = .quality
        queue.async { [weak self] in
            guard let self else { return }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let data = photo.fileDataRepresentation()
        let orientation = (photo.metadata[kCGImagePropertyOrientation as String] as? Int) ?? 1
        Task { @MainActor [weak self] in
            self?.captureCompletion?(data, orientation)
            self?.captureCompletion = nil
        }
    }
}
