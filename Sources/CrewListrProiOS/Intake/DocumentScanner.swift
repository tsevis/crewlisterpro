import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// The camera, as a document scanner rather than as a camera.
///
/// `VNDocumentCameraViewController` is the one Apple ships behind Notes: it
/// finds the edges of the page, corrects the perspective and returns a
/// flattened rectangle. That matters more here than it looks. Extraction lives
/// or dies on the machine-readable zone, two lines of OCR-B along the bottom of
/// the page, and a passport photographed at an angle across a desk gives Vision
/// a trapezoid whose characters lean. The same page through this scanner comes
/// back square, which is the difference between three fields recovered and all
/// five.
///
/// It also means the phone can do something the Mac never could: the passport
/// is in the operator's hand, and the document goes straight from the page into
/// the encrypted store without ever being a photograph in anybody's camera roll.
struct DocumentScanner: UIViewControllerRepresentable {
    /// One JPEG per scanned page, in the order they were taken.
    var onFinish: ([Data]) -> Void
    var onCancel: () -> Void = {}
    var onFailure: (Error) -> Void = { _ in }

    /// False in the Simulator and on a device with no usable camera. The button
    /// that opens this is hidden rather than disabled when it is false — an
    /// always-greyed control is a promise the app cannot keep.
    static var isAvailable: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish, onCancel: onCancel, onFailure: onFailure)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onFinish: ([Data]) -> Void
        private let onCancel: () -> Void
        private let onFailure: (Error) -> Void

        init(onFinish: @escaping ([Data]) -> Void, onCancel: @escaping () -> Void, onFailure: @escaping (Error) -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
            self.onFailure = onFailure
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            // Encoded here rather than carrying `UIImage`s out: the scanner
            // hands back full-resolution pages, and a handful of them held as
            // decoded bitmaps is a hundred megabytes of live memory on a phone.
            let pages: [Data] = (0..<scan.pageCount).compactMap { index in
                guard let page = scan.imageOfPage(at: index).platformCGImage else { return nil }
                return PlatformImageCodec.encode(page, as: .jpeg, quality: 0.95)
            }
            onFinish(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            onFailure(error)
        }
    }
}
