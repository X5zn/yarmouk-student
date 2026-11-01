import Foundation
import CoreLocation
import UserNotifications

/// Geofence around Yarmouk University (Irbid). Arrive → next lecture; arrival cancels today's «يلا اطلع».
final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()
    static let campus = CLCircularRegion(center: CLLocationCoordinate2D(latitude: 32.5365, longitude: 35.8555),
                                         radius: 900, identifier: "yarmouk-campus")

    override init() {
        super.init()
        manager.delegate = self
        Self.campus.notifyOnEntry = true
        Self.campus.notifyOnExit = false
    }

    func apply(enabled: Bool) {
        if enabled {
            if manager.authorizationStatus == .notDetermined { manager.requestAlwaysAuthorization() }
            else if manager.authorizationStatus == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
            if CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
                manager.startMonitoring(for: Self.campus)
            }
        } else {
            manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.campus.identifier else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [NotificationManager.leaveId(for: .now)])
        Task { @MainActor in
            let store = AppStore.shared
            guard let next = store.timetable.nextLecture(), Calendar.yarmouk.isDateInToday(next.interval.start),
                  let course = store.course(next.slot.courseCode) else { return }
            var line = "\(course.name) الساعة \(next.slot.startLabel)"
            if !next.slot.room.isEmpty && !next.slot.isOnline { line += " بقاعة \(next.slot.room)" }
            if let seat = next.slot.seat { line += " · مقعدك \(seat)" }
            NotificationManager.shared.arrivedOnCampus(next: line)
        }
    }
}
