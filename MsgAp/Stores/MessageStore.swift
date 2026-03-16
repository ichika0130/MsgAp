import Foundation
import Observation

@Observable
final class MessageStore {
    var messages: [Message] = []
    var isLoading = false
    var isSubmitting = false
    var errorMessage: String?

    private let baseURL = "http://localhost:3000"

    // MARK: – Fetch nearby

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
            try validate(response: response, data: data)
            messages = try JSONDecoder().decode([Message].self, from: data)
        } catch let AppNetworkError.server(msg) {
            errorMessage = msg
        } catch {
            errorMessage = "The link to the bonfire hath been severed."
        }

        isLoading = false
    }

    // MARK: – Submit new message

    /// Returns `true` on success so the caller can dismiss the sheet.
    @discardableResult
    func submitMessage(content: String, latitude: Double, longitude: Double) async -> Bool {
        isSubmitting = true
        errorMessage = nil

        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            isSubmitting = false
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = CreateMessageBody(content: content, latitude: latitude, longitude: longitude)
        do {
            request.httpBody = try JSONEncoder().encode(body)
            let (data, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, data: data)
        } catch let AppNetworkError.server(msg) {
            errorMessage = msg
            isSubmitting = false
            return false
        } catch {
            errorMessage = "The link to the bonfire hath been severed."
            isSubmitting = false
            return false
        }

        isSubmitting = false
        return true
    }

    // MARK: – Helpers

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            if let body = try? JSONDecoder().decode([String: String].self, from: data),
               let msg = body["error"] {
                throw AppNetworkError.server(msg)
            }
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: – Supporting types

private struct CreateMessageBody: Encodable {
    let content: String
    let latitude: Double
    let longitude: Double
}

private enum AppNetworkError: Error {
    case server(String)
}
