import AppKit
import MapKit

enum MapNavigation {
    static func openAppleMaps(title: String, latitude: Double, longitude: Double) {
        let item = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        item.name = title
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    static func openGoogleMapsApp(title: String, latitude: Double, longitude: Double) {
        let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        let urlString = "comgooglemaps://?daddr=\(latitude),\(longitude)&directionsmode=driving&q=\(encoded)"
        if let url = URL(string: urlString), NSWorkspace.shared.open(url) { return }
        openGoogleMapsWeb(latitude: latitude, longitude: longitude)
    }

    static func openGoogleMapsWeb(latitude: Double, longitude: Double) {
        let destination = "\(latitude),\(longitude)"
        let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination
        if let url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(encoded)&travelmode=driving") {
            NSWorkspace.shared.open(url)
        }
    }

    static var canOpenGoogleMapsApp: Bool {
        guard let url = URL(string: "comgooglemaps://") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }
}
