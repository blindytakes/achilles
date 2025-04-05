//
//  YearsAgoWidgetLiveActivity.swift
//  YearsAgoWidget
//
//  Created by Blind Takes on 4/5/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct YearsAgoWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct YearsAgoWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: YearsAgoWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension YearsAgoWidgetAttributes {
    fileprivate static var preview: YearsAgoWidgetAttributes {
        YearsAgoWidgetAttributes(name: "World")
    }
}

extension YearsAgoWidgetAttributes.ContentState {
    fileprivate static var smiley: YearsAgoWidgetAttributes.ContentState {
        YearsAgoWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: YearsAgoWidgetAttributes.ContentState {
         YearsAgoWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: YearsAgoWidgetAttributes.preview) {
   YearsAgoWidgetLiveActivity()
} contentStates: {
    YearsAgoWidgetAttributes.ContentState.smiley
    YearsAgoWidgetAttributes.ContentState.starEyes
}
