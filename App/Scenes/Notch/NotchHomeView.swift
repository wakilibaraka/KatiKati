import AppKit
import SwiftUI

/// Open state of the full notch skin: header row on top, then music (or the winning activity) on the
/// left and the calendar on the right. The Shelf tab swaps the body for the parked files.
struct NotchHomeView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var feed: LiveActivityFeed
    let metrics: NotchMetrics
    let calendarEnabled: Bool

    var body: some View {
        VStack(spacing: 0) {
            NotchHeaderView(model: model, metrics: metrics)
            Group {
                switch model.tab {
                case .home: home
                case .shelf: NotchShelfPanel()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 4)
        }
        // NotchShape's top corners flare outward, so the body is inset by the top radius per side.
        .padding(.horizontal, NotchLayoutSpec.openCornerRadii.top + NotchLayoutSpec.openPadding)
        .padding(.bottom, NotchLayoutSpec.openPadding)
    }

    private var home: some View {
        let panels = NotchLayoutSpec.panels(activityKind: feed.activity.kind, calendarEnabled: calendarEnabled)
        return HStack(alignment: .top, spacing: NotchLayoutSpec.homeSpacing) {
            switch panels.left {
            case .music: NotchMusicPanel(feed: feed)
            case .activity: NotchActivityPanel(activity: feed.activity)
            }
            if panels.showsCalendar {
                NotchCalendarPanel(calendar: ProductivityServices.shared.calendar)
                    .frame(width: NotchLayoutSpec.calendarColumnWidth)
            }
        }
    }
}

/// The Shelf tab: the files parked on the dock shelf, as icons that drag out. Read from the same
/// persisted list the dock uses, on each appearance (the shelf is small).
struct NotchShelfPanel: View {
    @State private var paths: [String] = []

    var body: some View {
        Group {
            if paths.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 28)).foregroundStyle(.white.opacity(0.4))
                    Text("Nothing on the Shelf").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(paths, id: \.self) { path in
                            VStack(spacing: 4) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 48, height: 48)
                                Text(verbatim: (path as NSString).lastPathComponent).font(.system(size: 10)).lineLimit(1).frame(width: 64)
                            }
                            .onDrag { NSItemProvider(object: URL(fileURLWithPath: path) as NSURL) }
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { paths = (UserDefaults.standard.stringArray(forKey: "shelfItemPaths") ?? []).filter { FileManager.default.fileExists(atPath: $0) } }
    }
}
