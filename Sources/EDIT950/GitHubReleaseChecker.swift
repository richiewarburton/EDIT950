import AppKit
import Foundation
import SwiftUI

struct GitHubRelease: Equatable {
    let tagName: String
    let pageURL: URL
}

enum GitHubReleaseCheckStatus: Equatable {
    case idle
    case checking
    case current(latestTag: String)
    case available(GitHubRelease)
    case failed(message: String)
}

@MainActor
final class GitHubReleaseChecker: ObservableObject {
    @Published private(set) var status: GitHubReleaseCheckStatus = .idle
    @Published private(set) var isBannerDismissed = false
    @Published var isPresentingResult = false

    let product: String
    let currentVersion: String

    private let owner: String
    private let repository: String
    private var didStartAutomaticCheck = false

    init(product: String, owner: String, repository: String, currentVersion: String) {
        self.product = product
        self.owner = owner
        self.repository = repository
        self.currentVersion = currentVersion
    }

    var bannerRelease: GitHubRelease? {
        guard !isBannerDismissed, case let .available(release) = status else {
            return nil
        }
        return release
    }

    func startAutomaticCheck() async {
        guard !didStartAutomaticCheck else { return }
        didStartAutomaticCheck = true
        await checkForUpdates(presentResult: false)
    }

    func checkForUpdates(presentResult: Bool) async {
        guard status != .checking else {
            if presentResult { isPresentingResult = true }
            return
        }
        status = .checking
        if presentResult { isPresentingResult = true }

        do {
            var request = URLRequest(url: apiURL)
            request.timeoutInterval = 12
            request.cachePolicy = .reloadRevalidatingCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            request.setValue(
                "\(product)/\(currentVersion) 950TOOLS",
                forHTTPHeaderField: "User-Agent"
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode)
            else {
                throw ReleaseCheckError.unexpectedResponse
            }

            let payload = try JSONDecoder().decode(LatestReleasePayload.self, from: data)
            guard let pageURL = URL(string: payload.htmlURL) else {
                throw ReleaseCheckError.invalidReleaseURL
            }
            let release = GitHubRelease(tagName: payload.tagName, pageURL: pageURL)
            isBannerDismissed = false
            status = Self.isVersion(payload.tagName, newerThan: currentVersion)
                ? .available(release)
                : .current(latestTag: payload.tagName)
        } catch {
            status = .failed(
                message: "EDIT950 could not reach GitHub. Check your connection and try again."
            )
        }
    }

    func dismissBanner() {
        isBannerDismissed = true
    }

    func open(_ release: GitHubRelease) {
        NSWorkspace.shared.open(release.pageURL)
    }

    nonisolated static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        guard let remoteParts = versionComponents(remote),
              let localParts = versionComponents(local)
        else { return false }
        let componentCount = max(remoteParts.count, localParts.count)
        for index in 0..<componentCount {
            let remotePart = index < remoteParts.count ? remoteParts[index] : 0
            let localPart = index < localParts.count ? localParts[index] : 0
            if remotePart != localPart { return remotePart > localPart }
        }
        return false
    }

    private nonisolated static func versionComponents(_ value: String) -> [Int]? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.first?.lowercased() == "v"
            ? String(trimmed.dropFirst())
            : trimmed
        let stablePart = withoutPrefix.split(whereSeparator: { $0 == "-" || $0 == "+" }).first
            .map(String.init) ?? withoutPrefix
        let components = stablePart.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }
        let numbers = components.compactMap { Int($0) }
        return numbers.count == components.count ? numbers : nil
    }

    private var apiURL: URL {
        URL(
            string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest"
        )!
    }
}

private struct LatestReleasePayload: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private enum ReleaseCheckError: Error {
    case unexpectedResponse
    case invalidReleaseURL
}

struct SuiteUpdateBanner: View {
    @ObservedObject var checker: GitHubReleaseChecker

    var body: some View {
        if let release = checker.bannerRelease {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.suiteBlue)
                Text("\(checker.product) \(release.tagName) IS AVAILABLE")
                    .font(SuiteFont.medium(10))
                    .tracking(1.2)
                Spacer()
                Button("VIEW RELEASE ↗") { checker.open(release) }
                    .buttonStyle(SuiteSecondaryButtonStyle())
                Button(action: checker.dismissBanner) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss update notice")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .background(Color.suiteSlab)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.suiteBlue).frame(height: 2)
            }
        }
    }
}

struct SuiteUpdateResultView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var checker: GitHubReleaseChecker

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: resultIcon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(resultColour)
            Text("CHECK FOR UPDATES")
                .font(SuiteFont.bold(14))
                .tracking(2.6)
            resultText
                .font(SuiteFont.regular(11))
                .foregroundStyle(Color.suiteLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
            if case let .available(release) = checker.status {
                Button("VIEW \(release.tagName) ON GITHUB ↗") {
                    checker.open(release)
                }
                .buttonStyle(SuitePrimaryButtonStyle(role: .neutral))
            }
            Button("DONE") { dismiss() }
                .buttonStyle(SuiteSecondaryButtonStyle())
                .keyboardShortcut(.cancelAction)
        }
        .padding(26)
        .frame(width: 410)
        .frame(minHeight: 280)
        .foregroundStyle(Color.suiteInk)
        .background(Color.suitePanel)
    }

    @ViewBuilder
    private var resultText: some View {
        switch checker.status {
        case .idle:
            Text("Ready to check the latest EDIT950 release on GitHub.")
        case .checking:
            VStack(spacing: 10) {
                ProgressView()
                Text("CONTACTING GITHUB…")
            }
        case let .current(latestTag):
            Text("EDIT950 \(checker.currentVersion) is current. Latest release: \(latestTag).")
        case let .available(release):
            Text("EDIT950 \(release.tagName) is available. Download it from the GitHub release page when you are ready.")
        case let .failed(message):
            Text(message)
        }
    }

    private var resultIcon: String {
        switch checker.status {
        case .checking: "arrow.triangle.2.circlepath"
        case .available: "arrow.down.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "checkmark.circle.fill"
        }
    }

    private var resultColour: Color {
        switch checker.status {
        case .available: .suiteBlue
        case .failed: .suiteAmber
        default: .suiteGreen
        }
    }
}
