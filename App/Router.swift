import SwiftUI

enum AppTab: Hashable { case home, schedule, summary, account, search }

/// Navigation that notifications, Siri and widgets can drive.
@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var tab: AppTab = .home
    @Published var homePath = NavigationPath()
    @Published var web: WebLink?
    @Published var notesFor: String?

    func openCourse(_ code: String) {
        tab = .home
        homePath = NavigationPath()
        homePath.append(CourseRoute(code: code))
    }

    func openNotes(for code: String) { notesFor = code }

    func open(_ urlString: String?, title: String = "") {
        guard let s = urlString, let u = URL(string: s) else { return }
        web = WebLink(url: u, title: title)
    }
}

struct CourseRoute: Hashable { let code: String }
struct SISPageRoute: Hashable { let key: String }
struct PlanRoute: Hashable {}
struct ExamsRoute: Hashable {}
struct PoetryRoute: Hashable {}
struct AssignmentsRoute: Hashable {}
