import Foundation
import Observation

@Observable
final class MessageStore {
    var messages: [Message] = []
    var isLoading = false
    var errorMessage: String?

    private let baseURL = "http://localhost:3000"

    func fetchNearby(latitude: Double, longitude: Double, radius: Double = 500) async {
        isLoading = true
        errorMessage = nil

        var components = URLComponents(string: "\(baseURL)/v1/messages/nearby")!
        components.queryItems = [
            URLQueryItem(name: "latitude",  value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "radius",    value: String(radius)),
        ]

        guard let url = components.url else {
            errorMessage = "Invalid request URL."
            isLoading = false
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            guard http.statusCode == 200 else {
                // Surface the server's Dark Souls error message if available
                if let body = try? JSONDecoder().decode([String: String].self, from: data),
                   let msg = body["error"] {
                    throw AppNetworkError.server(msg)
                }
                throw URLError(.badServerResponse)
            }

            messages = try JSONDecoder().decode([Message].self, from: data)
        } catch let AppNetworkError.server(msg) {
            errorMessage = msg
        } catch {
            errorMessage = "The link to the bonfire hath been severed."
        }

        isLoading = false
    }
}

private enum AppNetworkError: Error {
    case server(String)
}
