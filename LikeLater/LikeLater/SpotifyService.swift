//
//  SpotifyService.swift
//  LikeLater
//
//  Created by jihoon_macbook_air_13_m2 on 1/21/26.
//

import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import UIKit

@MainActor
final class SpotifyService: NSObject, ObservableObject {
    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var expiresAt: Date?
    @Published private(set) var lastStatus: String = "Not connected."

    private var authSession: ASWebAuthenticationSession?
    private var pkceVerifier: String?

    // TODO: Replace with your Spotify app Client ID.
    private let clientID = "YOUR_SPOTIFY_CLIENT_ID"
    // TODO: Register this redirect URI in Spotify Developer Dashboard.
    private let redirectURI = "likelater://spotify-auth"
    private let scopes = [
        "user-read-recently-played",
        "user-read-currently-playing"
    ]

    func startAuthorization() {
        guard clientID != "YOUR_SPOTIFY_CLIENT_ID" else {
            lastStatus = "Set your Spotify client ID first."
            return
        }

        let verifier = PKCE.codeVerifier()
        pkceVerifier = verifier
        let challenge = PKCE.codeChallenge(for: verifier)

        guard let authURL = authorizationURL(codeChallenge: challenge) else {
            lastStatus = "Failed to build auth URL."
            return
        }

        authSession = ASWebAuthenticationSession(url: authURL, callbackURLScheme: redirectScheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                self?.handleAuthCallback(url: callbackURL, error: error)
            }
        }
        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = true
        authSession?.start()
        lastStatus = "Opening Spotify login..."
    }

    func fetchRecentlyPlayed(into store: QueueStore) async {
        guard let data = await fetchRecentlyPlayedData() else { return }
        let items = store.decodeRecentlyPlayed(from: data)
        store.applyRecentPlays(items)
        lastStatus = "Fetched \(items.count) recently played items."
    }

    func tryMatchCapture(id: UUID, store: QueueStore) async {
        switch await fetchCurrentlyPlayingResult() {
        case .matched(let title):
            store.applyMatchResult(for: id, matchedTrack: title)
            lastStatus = "Matched with currently playing."
        case .noPlayback:
            store.removeCapture(id: id)
            lastStatus = "Removed capture (no playback)."
        case .failed:
            store.applyMatchResult(for: id, matchedTrack: nil)
        }
    }

    private func handleAuthCallback(url: URL?, error: Error?) {
        if let error {
            lastStatus = "Auth cancelled: \(error.localizedDescription)"
            return
        }
        guard let url, let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            lastStatus = "No auth code in callback."
            return
        }
        guard let verifier = pkceVerifier else {
            lastStatus = "Missing PKCE verifier."
            return
        }
        Task {
            await exchangeCodeForToken(code: code, verifier: verifier)
        }
    }

    private func authorizationURL(codeChallenge: String) -> URL? {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        return components?.url
    }

    private var redirectScheme: String {
        URL(string: redirectURI)?.scheme ?? "likelater"
    }

    private func exchangeCodeForToken(code: String, verifier: String) async {
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            lastStatus = "Invalid token URL."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "code_verifier": verifier
        ]

        request.httpBody = body.formURLEncodedData()

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            accessToken = token.accessToken
            refreshToken = token.refreshToken
            expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
            lastStatus = "Spotify connected."
        } catch {
            lastStatus = "Token exchange failed."
        }
    }

    private func refreshAccessToken() async {
        guard let refreshToken else {
            lastStatus = "Missing refresh token."
            return
        }
        guard let url = URL(string: "https://accounts.spotify.com/api/token") else {
            lastStatus = "Invalid token URL."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        request.httpBody = body.formURLEncodedData()

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
            accessToken = token.accessToken
            expiresAt = Date().addingTimeInterval(TimeInterval(token.expiresIn))
            lastStatus = "Spotify token refreshed."
        } catch {
            lastStatus = "Token refresh failed."
        }
    }

    private func fetchRecentlyPlayedData() async -> Data? {
        guard let token = accessToken else {
            lastStatus = "Connect Spotify first."
            return nil
        }

        if let expiresAt, expiresAt < Date() {
            await refreshAccessToken()
        }

        guard let url = URL(string: "https://api.spotify.com/v1/me/player/recently-played?limit=50") else {
            lastStatus = "Invalid recently played URL."
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return data
        } catch {
            lastStatus = "Failed to fetch recently played."
            return nil
        }
    }

    private func fetchCurrentlyPlayingResult() async -> NowPlayingResult {
        guard let token = accessToken else {
            lastStatus = "Connect Spotify first."
            return .failed
        }

        if let expiresAt, expiresAt < Date() {
            await refreshAccessToken()
        }

        guard let url = URL(string: "https://api.spotify.com/v1/me/player/currently-playing") else {
            lastStatus = "Invalid currently playing URL."
            return .failed
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                lastStatus = "No response from Spotify."
                return .failed
            }
            if httpResponse.statusCode == 204 {
                lastStatus = "No active playback."
                return .noPlayback
            }
            guard httpResponse.statusCode == 200 else {
                lastStatus = "Currently playing failed: \(httpResponse.statusCode)"
                return .failed
            }
            let payload = try JSONDecoder().decode(SpotifyNowPlayingResponse.self, from: data)
            guard let track = payload.item else {
                lastStatus = "No track in response."
                return .failed
            }
            let artists = track.artists.map { $0.name }.joined(separator: ", ")
            return .matched("\(track.name) • \(artists)")
        } catch {
            lastStatus = "Failed to fetch currently playing."
            return .failed
        }
    }
}

extension SpotifyService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) else {
            return ASPresentationAnchor()
        }
        return window
    }
}

private enum PKCE {
    static func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).base64URLEncodedString()
    }

    static func codeChallenge(for verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hashed = SHA256.hash(data: data)
        return Data(hashed).base64URLEncodedString()
    }
}

private extension Dictionary where Key == String, Value == String {
    func formURLEncodedData() -> Data? {
        let string = self.map { key, value in
            "\(key.urlQueryEncoded())=\(value.urlQueryEncoded())"
        }
        .sorted()
        .joined(separator: "&")
        return string.data(using: .utf8)
    }
}

private extension String {
    func urlQueryEncoded() -> String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        let base64 = base64EncodedString()
        return base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct SpotifyTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let scope: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct SpotifyNowPlayingResponse: Codable {
    let item: SpotifyNowPlayingTrack?
}

private struct SpotifyNowPlayingTrack: Codable {
    let name: String
    let uri: String
    let artists: [SpotifyNowPlayingArtist]
}

private struct SpotifyNowPlayingArtist: Codable {
    let name: String
}

private enum NowPlayingResult {
    case matched(String)
    case noPlayback
    case failed
}
