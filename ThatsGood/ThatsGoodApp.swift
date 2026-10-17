import SwiftUI
import SwiftData
import UIKit

@main
struct ThatsGoodApp: App {
    init() {
        BrandFonts.register()
        Self.styleBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color.tgFairway)
                .fontDesign(.rounded)
                .preferredColorScheme(.light)  // the golf course look is light; a dark version can come later
        }
        .modelContainer(for: [Course.self, Round.self, HoleScore.self, Shot.self, Club.self, ImportedScore.self])
    }
}

extension ThatsGoodApp {
    /// Deep rough tab bar, and titles in the logo font.
    static func styleBars() {
        let rough = UIColor(Color.tgRough)
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = rough
        tab.shadowColor = .clear
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(Color(hex: 0xA9C9B4))
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(Color(hex: 0xA9C9B4))]
            item.selected.iconColor = UIColor(Color.tgPale)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(Color.tgPale)]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = UIColor(Color.tgBackground)
        nav.largeTitleTextAttributes = [.font: BrandFonts.uiFont(38, bold: true), .foregroundColor: rough]
        nav.titleTextAttributes = [.font: BrandFonts.uiFont(21, bold: true), .foregroundColor: rough]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
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
        if args.contains("-socialDemo") {
            Backend.shared.loadDemo()
        }
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
            switch args[i + 1] {
            case "friends": tab = .friends
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
            FriendsView()
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
        .modelContainer(for: [Course.self, Round.self, HoleScore.self, Shot.self, Club.self, ImportedScore.self], inMemory: true)
}
