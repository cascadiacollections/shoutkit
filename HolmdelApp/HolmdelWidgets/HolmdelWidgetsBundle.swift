import SwiftUI
import WidgetKit

@main
struct HolmdelWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingLiveActivity()
        QuickPlayWidget()
    }
}
