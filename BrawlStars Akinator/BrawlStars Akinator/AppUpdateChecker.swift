import Foundation
import Observation

@MainActor @Observable
final class AppUpdateChecker {
    private static let appStoreID = "6808567765"
    private(set) var isUpdateAvailable = false
    private(set) var latestVersion = ""
    private(set) var updateURL: URL?

    private let defaults = UserDefaults.standard
    private let reminderInterval: TimeInterval = 24 * 60 * 60

    func check() async {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(Self.appStoreID)&country=jp") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let result = try JSONDecoder().decode(LookupResponse.self, from: data).results.first,
                  let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  Self.isVersion(result.version, newerThan: currentVersion) else { return }

            let dismissedVersion = defaults.string(forKey: "dismissedUpdateVersion")
            let dismissedAt = defaults.object(forKey: "dismissedUpdateAt") as? Date
            if dismissedVersion == result.version,
               let dismissedAt,
               Date().timeIntervalSince(dismissedAt) < reminderInterval { return }

            latestVersion = result.version
            updateURL = URL(string: result.trackViewUrl)
            isUpdateAvailable = updateURL != nil
        } catch {
            // An update check must never prevent the game from launching.
        }
    }

    func dismiss() {
        if !latestVersion.isEmpty {
            defaults.set(latestVersion, forKey: "dismissedUpdateVersion")
            defaults.set(Date(), forKey: "dismissedUpdateAt")
        }
        isUpdateAvailable = false
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

}

private struct LookupResponse: Decodable {
    let results: [LookupResult]
}

private struct LookupResult: Decodable {
    let version: String
    let trackViewUrl: String
}
