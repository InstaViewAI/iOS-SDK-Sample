//
//  QRCodeScannerView.swift
//  Sandbox
//
//  Camera preview that reports the first QR payload it reads. Used to read the
//  code printed on a cellular camera's body during setup — the other direction
//  from the pairing handshake, where the phone displays a code for the camera.
//

import SwiftUI
import AVFoundation
import AudioToolbox

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?

        private let session = AVCaptureSession()
        private var previewLayer: AVCaptureVideoPreviewLayer?
        /// The delegate fires repeatedly while a code is in frame; only the
        /// first read should drive navigation.
        private var hasReported = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configureSession()
        }

        private func configureSession() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                Logger.debugLog("QR scanner: no usable capture device")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.layer.bounds
            view.layer.addSublayer(layer)
            previewLayer = layer
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            hasReported = false
            guard !session.isRunning else { return }
            // startRunning blocks; keep it off the main thread.
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning { session.stopRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            previewLayer?.frame = view.layer.bounds
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !hasReported,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            hasReported = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onCode?(value)
        }
    }
}
