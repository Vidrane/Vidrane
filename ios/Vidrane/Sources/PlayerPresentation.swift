import SwiftUI
import AVKit

/// Selects the controls shown around the same native AVFoundation decoder.
/// A different playback UI does not unlock new codecs or Apple entitlements.
enum PlayerPresentation: String, CaseIterable, Identifiable {
    case vidrane
    case apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple Player"
        case .vidrane: return "Vidrane"
        }
    }

    var detail: String {
        switch self {
        case .apple: return "Системные элементы управления iOS и Picture-in-Picture"
        case .vidrane: return "Собственные кнопки, перемотка и ползунок Vidrane"
        }
    }

    var symbol: String {
        switch self {
        case .apple: return "apple.logo"
        case .vidrane: return "play.rectangle.on.rectangle"
        }
    }
}

enum VideoScaling: String, CaseIterable, Identifiable {
    case fit
    case fill

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fit: return "Вместить"
        case .fill: return "Заполнить"
        }
    }

    var gravity: AVLayerVideoGravity {
        switch self {
        case .fit: return .resizeAspect
        case .fill: return .resizeAspectFill
        }
    }
}

/// Used only for Vidrane presentation; AVPlayer remains the single playback
/// session when switching between Apple and custom controls.
struct VidraneVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let gravity: AVLayerVideoGravity
    let pictureInPicture: VidranePictureInPicture

    func makeCoordinator() -> VidranePictureInPicture { pictureInPicture }

    func makeUIView(context: Context) -> VidraneVideoLayerView {
        let view = VidraneVideoLayerView()
        view.backgroundColor = .black
        view.videoLayer.videoGravity = gravity
        view.videoLayer.player = player
        context.coordinator.attach(layer: view.videoLayer)
        return view
    }

    func updateUIView(_ view: VidraneVideoLayerView, context: Context) {
        if view.videoLayer.player !== player {
            view.videoLayer.player = player
        }
        if view.videoLayer.videoGravity != gravity {
            view.videoLayer.videoGravity = gravity
        }
        context.coordinator.attach(layer: view.videoLayer)
    }

    static func dismantleUIView(
        _ view: VidraneVideoLayerView,
        coordinator: VidranePictureInPicture
    ) {
        coordinator.detach(layer: view.videoLayer)
    }
}

final class VidraneVideoLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var videoLayer: AVPlayerLayer {
        // The layer type is guaranteed by layerClass.
        layer as! AVPlayerLayer
    }
}
