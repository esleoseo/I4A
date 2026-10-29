import Foundation

enum AdminConfig {
    /// The admin server (see admin/README.md). Its host is set as
    /// I4A_ADMIN_HOST in I4A/Config/Local.xcconfig and reaches the app through
    /// Info.plist, so it never has to be edited in source. Empty: no admin.
    static var baseURL: URL? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "I4AAdminHost") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return URL(string: value.contains("://") ? value : "https://" + value)
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

    /// The report request, or nil when no admin server is set.
    static func reportRequest(usedSeconds: Int, day: String, instagramInstalled: Bool) -> URLRequest? {
        guard let url = AdminConfig.baseURL?.appendingPathComponent("api/report") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "day": day,
            "usedSeconds": min(max(0, usedSeconds), 86_400),
            "instagramInstalled": instagramInstalled,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func sendReport(usedSeconds: Int, day: String, instagramInstalled: Bool, session: URLSession) {
        guard let request = reportRequest(usedSeconds: usedSeconds, day: day, instagramInstalled: instagramInstalled) else { return }
        session.dataTask(with: request) { _, _, _ in }.resume()
    }

    /// For the background refresh task, which iOS gives only about 30 seconds:
    /// short timeouts, so a slow server can't keep the task past its budget.
    static let backgroundSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        return URLSession(configuration: config)
    }()
}
