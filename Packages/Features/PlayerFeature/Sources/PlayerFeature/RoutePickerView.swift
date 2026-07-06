import AVKit
import SwiftUI

/// SwiftUI wrapper around `AVRoutePickerView` for AirPlay / output selection.
public struct RoutePickerView: UIViewRepresentable {
    public var tintColor: UIColor
    public var activeTintColor: UIColor

    public init(tintColor: UIColor = .label, activeTintColor: UIColor = .tintColor) {
        self.tintColor = tintColor
        self.activeTintColor = activeTintColor
    }

    public func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        view.tintColor = tintColor
        view.activeTintColor = activeTintColor
        return view
    }

    public func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = activeTintColor
    }
}
