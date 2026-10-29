import Foundation

enum AdminConfig {
    /// Address of your admin server (see admin/README.md), for example
    /// "https://i4a-admin.yourname.workers.dev". Leave empty to use I4A
    /// without an admin.
    static let serverURL = ""

    static var baseURL: URL? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : URL(string: trimmed)
    }
}

/// Keeps the time limit in step with the admin page and reports today's
/// usage and whether the Instagram app is installed.
final class AdminSync: ObservableObject {
    static let pollInterval: TimeInterval = 20

    private let settings: AppSettings
    private let tracker: UsageTracker
    private let session: URLSession
    private var timer: Timer?
    private var isFetching = false

    init(settings: AppSettings, tracker: UsageTracker) {
        self.settings = settings
        self.tracker = tracker
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    deinit {
        timer?.invalidate()
    }

    /// Polls while the app is in the foreground.
    func setActive(_ active: Bool) {
        guard AdminConfig.baseURL != nil else { return }
        if active {
            sync()
            guard timer == nil else { return }
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                self?.sync()
            }
            timer.tolerance = 2
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            sendReport()
        }
    }

    func sync() {
        fetchPolicy()
        sendReport()
    }

    private func fetchPolicy() {
        guard !isFetching, let url = AdminConfig.baseURL?.appendingPathComponent("api/policy") else { return }
        isFetching = true
        session.dataTask(with: url) { [weak self] data, response, _ in
            let policy = data.flatMap { data -> AdminPolicy? in
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                return try? JSONDecoder().decode(AdminPolicy.self, from: data)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                // Offline or a bad answer: keep the last known policy.
                if let policy { self.settings.apply(policy) }
            }
        }.resume()
    }

    private func sendReport() {
        Self.sendReport(
            usedSeconds: tracker.usedSeconds,
            day: tracker.day,
            instagramInstalled: InstagramApp.isInstalled,
            session: session
        )
    }

    /// Also used by the background refresh task.
    static func sendReport(usedSeconds: Int, day: String, instagramInstalled: Bool,
                           session: URLSession = .shared, completion: (() -> Void)? = nil) {
        guard let url = AdminConfig.baseURL?.appendingPathComponent("api/report") else {
            completion?()
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "day": day,
            "usedSeconds": min(max(0, usedSeconds), 86_400),
            "instagramInstalled": instagramInstalled,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        session.dataTask(with: request) { _, _, _ in completion?() }.resume()
    }
}
