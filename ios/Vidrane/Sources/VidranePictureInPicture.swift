import AVKit
import Foundation

/// Native Picture-in-Picture for Vidrane's custom AVPlayerLayer presentation.
/// The controller must remain strongly retained for the PiP session lifetime.
final class VidranePictureInPicture: NSObject {
    private var controller: AVPictureInPictureController?
    private weak var attachedLayer: AVPlayerLayer?

    var supported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var possible: Bool {
        supported && controller?.isPictureInPicturePossible == true
    }

    func attach(layer: AVPlayerLayer) {
        guard supported else { return }
        guard attachedLayer !== layer else { return }
        controller?.stopPictureInPicture()
        attachedLayer = layer
        controller = AVPictureInPictureController(playerLayer: layer)
    }

    func start() {
        guard let controller = controller, controller.isPictureInPicturePossible else {
            return
        }
        controller.startPictureInPicture()
    }

    func detach(layer: AVPlayerLayer) {
        guard attachedLayer === layer else { return }
        controller?.stopPictureInPicture()
        controller = nil
        attachedLayer = nil
    }
}
