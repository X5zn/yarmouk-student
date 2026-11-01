import SwiftUI
import BackgroundTasks

@main
struct YarmoukStudentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore.shared
    @StateObject private var router = Router.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if store.onboarded {
                    RootView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(store)
            .environmentObject(router)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar_JO"))
            .tint(Brand.green)
            .sheet(item: $router.web) { link in
                InAppBrowser(url: link.url, title: link.title)
            }
            .sheet(item: Binding(get: { router.notesFor.map { CourseRoute(code: $0) } },
                                 set: { router.notesFor = $0?.code })) { route in
                NavigationStack { NotesView(courseCode: route.code) }
                    .environmentObject(store)
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, store.onboarded {
                Task { await store.refreshMoodle() }
                Task { await store.refreshSISIfStale() }
                LiveActivityManager.shared.refresh(store: store)
            }
            if phase == .background { BackgroundRefresh.schedule() }
        }
    }
}

extension CourseRoute: Identifiable { var id: String { code } }

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationManager.shared.setup()
        BackgroundRefresh.register()
        Task { @MainActor in
            await WebSession.shared.restoreCookies()
            LocationManager.shared.apply(enabled: AppStore.shared.settings.geofence)
        }
        return true
    }
}

enum BackgroundRefresh {
    static let id = "com.baihas.yarmoukstudent.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                _ = await AppStore.shared.refreshMoodle(background: true)
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: id)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
