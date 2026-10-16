import SwiftUI
import SwiftData

@main
struct ThatsGoodApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.tgAccent)
        }
        .modelContainer(for: [Course.self, Round.self, HoleScore.self, Shot.self, Club.self])
    }
}

enum AppTab: Hashable {
    case home, friends, play, stats, bag
}

struct RootView: View {
    @State private var tab: AppTab = .home
    @Environment(\.modelContext) private var context

    var body: some View {
        tabs
        #if DEBUG
            .onAppear(perform: applyLaunchArguments)
        #endif
    }

    #if DEBUG
    /// Used by the CI screenshot step: `-demoData` loads demo rounds, `-tab stats` opens a tab.
    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demoData"),
           (try? context.fetchCount(FetchDescriptor<Course>(predicate: #Predicate { $0.name == "Demo Golf Club" }))) == 0 {
            SampleData.load(into: context)
        }
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "play": tab = .play
            case "stats": tab = .stats
            case "bag": tab = .bag
            default: tab = .home
            }
        }
    }
    #endif

    private var tabs: some View {
        TabView(selection: $tab) {
            HomeView(selectedTab: $tab)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)
            ComingSoonView(title: "Friends",
                           message: "Friends, rivalries, side matches, leaderboards and live tournaments arrive in Phase 3.")
                .tabItem { Label("Friends", systemImage: "person.2") }
                .tag(AppTab.friends)
            PlayView()
                .tabItem { Label("Play", systemImage: "flag") }
                .tag(AppTab.play)
            StatsView()
                .tabItem { Label("Stats", systemImage: "chart.bar") }
                .tag(AppTab.stats)
            BagView()
                .tabItem { Label("Bag", systemImage: "bag") }
                .tag(AppTab.bag)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Course.self, Round.self, HoleScore.self, Shot.self, Club.self], inMemory: true)
}
