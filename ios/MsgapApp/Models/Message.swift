import CoreLocation

struct Message: Codable, Identifiable {
    let id: String
    let content: String?
    let latitude: Double
    let longitude: Double
    let isReadable: Bool

    enum CodingKeys: String, CodingKey {
        case id, content, latitude, longitude
        case isReadable = "is_readable"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
