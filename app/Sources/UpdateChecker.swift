//
//  UpdateChecker.swift
//  KISSTranslator
//
//  Checks GitHub Releases for a newer build of this app.
//
//  ── Why GitHub Releases and not Sparkle ────────────────────────────────────
//  Releases of this project are unsigned (ad-hoc) and distributed as a DMG the
//  user drags into /Applications. Sparkle's automatic in-place update requires
//  an EdDSA-signed appcast, which would only be meaningful once the app is
//  Developer-ID signed and notarised. Until then, the honest behaviour is to
//  *tell* the user a new version exists and link to the download, leaving the
//  replacement to them. Swapping the binary out from under a running,
//  unsigned, sandboxed app would also fail Gatekeeper.
//
//  The endpoint is the public REST API, which needs no auth for a handful of
//  requests per launch. It is overridable (`KISS_UPDATES_URL`) for testing.
//

import Foundation

// MARK: - Public value types

/// A release as reported by the GitHub API, reduced to what the UI needs.
struct UpdateRelease: Sendable, Equatable, Identifiable {
    var id: String { version }

    /// Version without a leading "v", e.g. "2.1.2".
    let version: String
    /// Release page the user is sent to.
    let pageURL: URL
    /// Preferred direct download (the DMG) when the release has one.
    let downloadURL: URL?
    /// Rendered Markdown body, or nil when the release has no notes.
    let notes: String?
    /// Where the release was published from, for the "published N days ago" line.
    let publishedAt: Date?

    /// True when this release is a pre-release (e.g. `v2.2.0-beta.1`).
    let isPrerelease: Bool
}

/// Outcome of an update check.
enum UpdateCheckResult: Sendable, Equatable {
    /// The running version is the newest available.
    case upToDate(latest: String)
    /// A newer version exists.
    case updateAvailable(UpdateRelease)
    /// The check could not be completed.
    case failed(UpdateCheckError)
}

enum UpdateCheckError: Error, Sendable, Equatable {
    /// No network, DNS failure, timeout, …
    case network(String)
    /// The server answered with a non-200 status.
    case http(Int)
    /// The payload was not a usable release object.
    case malformed(String)
}

extension UpdateCheckError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .network(let detail):
            String(localized: "无法连接更新服务器。", comment: "Update check network failure") + " (\(detail))"
        case .http(let status):
            String(localized: "更新服务器返回错误。", comment: "Update check HTTP failure") + " (HTTP \(status))"
        case .malformed(let detail):
            String(localized: "无法解析更新信息。", comment: "Update check parse failure") + " (\(detail))"
        }
    }
}

// MARK: - Version comparison

/// Semantic-ish version ordering for the strings this project actually uses.
///
/// Upstream version numbers are 2-4 dot-separated integers ("2.1.1"), but
/// pre-releases ("2.2.0-beta.1") also occur. Numeric components compare
/// numerically (so 2.1.10 > 2.1.9, unlike a string compare); a version with a
/// pre-release suffix sorts *before* the same version without one, matching
/// SemVer. Missing components are treated as 0.
enum VersionOrdering {
    /// Returns true when `candidate` is strictly newer than `current`.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) > 0
    }

    /// Three-way comparison: negative when `lhs` is older, 0 when equal.
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let l = split(lhs)
        let r = split(rhs)

        // 1. Numeric core, zero-padded so 2.1 == 2.1.0.
        let count = max(l.numbers.count, r.numbers.count)
        for index in 0..<count {
            let a = index < l.numbers.count ? l.numbers[index] : 0
            let b = index < r.numbers.count ? r.numbers[index] : 0
            if a != b { return a < b ? -1 : 1 }
        }

        // 2. Identical cores: a pre-release ranks below the final release.
        switch (l.prerelease, r.prerelease) {
        case (nil, nil): return 0
        case (nil, _): return 1            // 2.1.0 > 2.1.0-beta
        case (_, nil): return -1
        case let (a?, b?): return comparePrerelease(a, b)
        }
    }

    /// Compares pre-release identifiers per SemVer §11.
    private static func comparePrerelease(_ lhs: String, _ rhs: String) -> Int {
        let a = lhs.split(separator: ".").map(String.init)
        let b = rhs.split(separator: ".").map(String.init)
        for index in 0..<max(a.count, b.count) {
            // A shorter list sorts first when all preceding identifiers match.
            if index >= a.count { return -1 }
            if index >= b.count { return 1 }
            let x = a[index], y = b[index]
            let xn = Int(x), yn = Int(y)
            switch (xn, yn) {
            case let (x?, y?):
                if x != y { return x < y ? -1 : 1 }
            case (_?, nil):
                return -1                 // numeric identifiers rank below alphanumeric
            case (nil, _?):
                return 1
            case (nil, nil):
                if x != y { return x < y ? -1 : 1 }
            }
        }
        return 0
    }

    /// Splits "v2.1.1-beta.1+build5" into ([2,1,1], "beta.1").
    private static func split(_ version: String) -> (numbers: [Int], prerelease: String?) {
        var text = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = text.first, first == "v" || first == "V" {
            text.removeFirst()
        }
        // Build metadata does not affect precedence.
        if let plus = text.firstIndex(of: "+") {
            text = String(text[..<plus])
        }
        let core: Substring
        var prerelease: String?
        if let dash = text.firstIndex(of: "-") {
            core = text[..<dash]
            prerelease = String(text[text.index(after: dash)...])
        } else {
            core = Substring(text)
        }
        let numbers = core.split(separator: ".").map { Int($0) ?? 0 }
        return (numbers.isEmpty ? [0] : numbers, prerelease)
    }
}

// MARK: - Checker

/// Fetches the newest release for the configured repository.
///
/// Deliberately stateless and injectable so the parsing/ordering logic can be
/// exercised without a network (§`UpdateCheckerTests`).
struct UpdateChecker: Sendable {
    /// Repository whose releases are considered.
    let repository: String
    /// Session used for the request; injectable for tests.
    let session: URLSession

    /// Set by the build or a developer to point at a staging endpoint.
    static let endpointOverrideKey = "KISS_UPDATES_URL"

    init(
        repository: String = AppConfiguration.updatesRepository,
        session: URLSession = .shared
    ) {
        self.repository = repository
        self.session = session
    }

    /// Release API endpoint, honouring `KISS_UPDATES_URL` for testing.
    var endpoint: URL {
        if let override = ProcessInfo.processInfo.environment[Self.endpointOverrideKey],
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    /// Checks whether a newer release than `currentVersion` exists.
    ///
    /// Never throws: every failure is mapped into `.failed`, because the caller
    /// is a background convenience check that must not disturb the UI.
    func check(currentVersion: String = AppConfiguration.version) async -> UpdateCheckResult {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub rejects requests without a User-Agent.
        request.setValue(
            "KISSTranslator-Safari/\(AppConfiguration.version)",
            forHTTPHeaderField: "User-Agent"
        )
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failed(.network(error.localizedDescription))
        }

        if let http = response as? HTTPURLResponse {
            // 404 means "no releases yet", which is not an error worth showing.
            if http.statusCode == 404 {
                return .upToDate(latest: currentVersion)
            }
            guard http.statusCode == 200 else {
                return .failed(.http(http.statusCode))
            }
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed(.malformed("响应不是 JSON 对象"))
        }
        return Self.evaluate(payload, currentVersion: currentVersion)
    }

    /// Pure decision step, separated so it is trivially testable.
    static func evaluate(_ payload: [String: Any], currentVersion: String) -> UpdateCheckResult {
        guard let tag = payload["tag_name"] as? String else {
            return .failed(.malformed("缺少 tag_name"))
        }
        // Draft releases should never be advertised.
        if payload["draft"] as? Bool == true {
            return .upToDate(latest: currentVersion)
        }

        let latest = normalizedVersion(tag)
        guard VersionOrdering.isNewer(latest, than: currentVersion) else {
            return .upToDate(latest: latest)
        }

        guard let pageString = payload["html_url"] as? String,
              let pageURL = URL(string: pageString) else {
            return .failed(.malformed("缺少 html_url"))
        }

        // Prefer the DMG asset; fall back to the release page.
        var downloadURL: URL?
        if let assets = payload["assets"] as? [[String: Any]] {
            let preferred = assets.first { asset in
                (asset["name"] as? String)?.lowercased().hasSuffix(".dmg") == true
            }
            if let url = preferred?["browser_download_url"] as? String {
                downloadURL = URL(string: url)
            }
        }

        let publishedAt = (payload["published_at"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        }

        return .updateAvailable(
            UpdateRelease(
                version: latest,
                pageURL: pageURL,
                downloadURL: downloadURL,
                notes: (payload["body"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                publishedAt: publishedAt,
                isPrerelease: payload["prerelease"] as? Bool ?? false
            )
        )
    }

    /// Strips a leading "v" so comparisons and display agree.
    static func normalizedVersion(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first, first == "v" || first == "V" {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}
