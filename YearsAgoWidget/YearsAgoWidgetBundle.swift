import WidgetKit
import SwiftUI

@main
struct YearsAgoWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        YearsAgoWidget() // ← this is the important part
    }
}
