import SwiftUI
import AVKit

/// Spiegelt AVRoutePickerView in SwiftUI. Triggered den iOS-System-AirPlay-Picker
/// (hifispeaker-Icon). Farbe wird vom tintColor uebernommen.
struct AirPlayButton: UIViewRepresentable {
    var tintColor: UIColor = .white
    var activeColor: UIColor = UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tintColor
        view.activeTintColor = activeColor
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = activeColor
    }
}
