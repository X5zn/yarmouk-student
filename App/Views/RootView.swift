import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var router: Router

    var body: some View {
        TabView(selection: $router.tab) {
            Tab("الرئيسية", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView().withDestinations()
                }
            }
            Tab("الجدول", systemImage: "calendar", value: AppTab.schedule) {
                NavigationStack { ScheduleView().withDestinations() }
            }
            Tab("الملخص", systemImage: "heart.text.square.fill", value: AppTab.summary) {
                NavigationStack { SummaryView().withDestinations() }
            }
            Tab("حسابي", systemImage: "person.crop.circle.fill", value: AppTab.account) {
                NavigationStack { AccountView().withDestinations() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView().withDestinations() }
            }
        }
        .tint(Brand.green)
        .sensoryFeedback(.selection, trigger: router.tab)
    }
}

extension View {
    /// Every stack in the app can push the same native screens.
    func withDestinations() -> some View {
        self
            .navigationDestination(for: CourseRoute.self) { CourseDetailView(code: $0.code) }
            .navigationDestination(for: SISPageRoute.self) { SISPageView(key: $0.key) }
            .navigationDestination(for: PlanRoute.self) { _ in PlanView() }
            .navigationDestination(for: ExamsRoute.self) { _ in ExamsView() }
            .navigationDestination(for: PoetryRoute.self) { _ in PoetryView() }
            .navigationDestination(for: AssignmentsRoute.self) { _ in AssignmentsView() }
    }
}
