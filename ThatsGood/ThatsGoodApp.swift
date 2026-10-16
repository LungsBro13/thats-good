import SwiftUI
import SwiftData

@main
struct ThatsGoodApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.tgAccent)
        }
        .modelContainer(for: [Course.self, Round.self, HoleScore.self])
    }
}

enum AppTab: Hashable {
    case home, friends, play, stats, bag
}

struct RootView: View {
    @State private var tab: AppTab = .home

    var body: some View {
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
        .modelContainer(for: [Course.self, Round.self, HoleScore.self], inMemory: true)
}
