//
//  OnboardingView.swift
//  KISSTranslator
//
//  The single window of the containing app: a short, self-contained how-to
//  that walks the user through enabling the Safari web extension.
//

import AppKit
import SwiftUI

struct OnboardingView: View {
    @State private var model = OnboardingViewModel()

    /// The update currently being described in an alert, if any.
    @State private var presentedUpdate: UpdateRelease?

    private let windowWidth: CGFloat = 520
    private let windowHeight: CGFloat = 600

    var body: some View {
        VStack(spacing: 0) {
            header
            instructions
            Spacer(minLength: 12)
            footer
        }
        .frame(width: windowWidth, height: windowHeight)
        .background(.background)
        .task {
            await model.refreshStatus()
            // Convenience check; quiet on failure and never blocks the UI.
            await model.checkForUpdatesIfNeeded()
        }
        .onChange(of: model.isOpeningPreferences) { _, isOpening in
            // Safari is about to come to the front; re-check once we come back.
            if !isOpening {
                Task { await model.refreshStatus() }
            }
        }
        .onChange(of: model.availableUpdate) { _, update in
            // Surface a newly discovered release once, as a native sheet.
            if let update, presentedUpdate == nil {
                presentedUpdate = update
            }
        }
        .sheet(item: $presentedUpdate) { release in
            UpdateAvailableSheet(
                release: release,
                currentVersion: model.version,
                onDownload: {
                    presentedUpdate = nil
                    model.openUpdateDownload(release)
                },
                onViewAllReleases: {
                    presentedUpdate = nil
                    model.openAllReleases()
                },
                onLater: { presentedUpdate = nil }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            icon
            Text(verbatim: AppConfiguration.displayName)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text(String(localized: "优雅的双语对照翻译扩展，支持网页、选词与视频字幕。",
                        comment: "App subtitle"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 36)
            statusBadge
                .padding(.top, 2)
        }
        .padding(.top, 28)
        .padding(.bottom, 20)
    }

    private var icon: some View {
        Group {
            if let appIcon = Self.appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "character.bubble.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(22)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous)
                    )
            }
        }
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
    }

    /// The generated AppIcon (Assets.xcassets), when one is available.
    ///
    /// App icons are not always present while the wrapper is being built out,
    /// so fall back to an SF Symbol rendering instead of showing a blank square.
    private static let appIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: url) else { return nil }
        return image
    }()

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.12), in: Capsule())
        .foregroundStyle(statusColor)
        .help(statusHelp)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(statusText))
    }

    private var statusText: String {
        switch model.status {
        case .unknown: String(localized: "正在检查扩展状态…", comment: "Status: checking")
        case .enabled: String(localized: "已启用", comment: "Status: enabled")
        case .disabled: String(localized: "未启用", comment: "Status: disabled")
        case .failed: String(localized: "无法获取状态", comment: "Status: query failed")
        }
    }

    private var statusHelp: String {
        switch model.status {
        case .unknown: String(localized: "正在向 Safari 查询扩展状态。", comment: "Status help: checking")
        case .enabled: String(localized: "Safari 已启用 KISS Translator 扩展。", comment: "Status help: enabled")
        case .disabled: String(localized: "请在 Safari 设置的「扩展」中勾选 KISS Translator。", comment: "Status help: disabled")
        case .failed(let reason): reason
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .enabled: .green
        case .disabled: .orange
        case .failed: .red
        case .unknown: .secondary
        }
    }

    // MARK: - Instructions

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "开启 Safari 扩展", comment: "Instructions heading"))
                .font(.headline)

            step(1, String(localized: "点击下方按钮，浏览器会打开 Safari 设置。", comment: "Step 1"))
            step(2, String(localized: "在左侧选择「扩展」，勾选右侧的 KISS Translator。", comment: "Step 2"))
            step(3, String(localized: "首次使用时，按提示允许扩展访问网页；随后刷新页面即可。", comment: "Step 3"))

            Divider()
                .padding(.vertical, 2)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "快捷键：⌥K 打开面板，⌥Q 翻译当前网页，⌥S 打开翻译框。",
                            comment: "Keyboard shortcut hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
                .accessibilityHidden(true)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 12) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await model.openSafariExtensionPreferences() }
            } label: {
                HStack(spacing: 8) {
                    if model.isOpeningPreferences {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "safari")
                    }
                    Text(String(localized: "打开 Safari 扩展设置", comment: "Primary button"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isOpeningPreferences)
            .padding(.horizontal, 32)

            if !model.status.isEnabled {
                Button(String(localized: "重新检查状态", comment: "Refresh status button")) {
                    Task { await model.refreshStatus() }
                }
                .buttonStyle(.link)
                .font(.caption)
            }

            Divider()
                .padding(.horizontal, 32)

            HStack(spacing: 14) {
                footerLink(String(localized: "上游项目", comment: "Footer link to upstream"), AppConfiguration.upstreamURL)
                footerLink(String(localized: "本仓库", comment: "Footer link to this repository"), AppConfiguration.projectURL)
                footerLink("GPL-3.0", AppConfiguration.licenseURL)
            }

            versionRow
        }
        .padding(.bottom, 20)
    }

    /// Version label plus the update affordance.
    ///
    /// Kept on one line so the window height never changes: when an update
    /// exists the label turns into a highlighted button, it does not push the
    /// layout around.
    private var versionRow: some View {
        HStack(spacing: 8) {
            Text(String(localized: "版本", comment: "Version label") + " \(model.version) (\(model.build))")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            switch model.updateState {
            case .idle, .upToDate:
                EmptyView()

            case .checking:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)

            case .available(let release):
                Button {
                    presentedUpdate = release
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(String(localized: "可更新至", comment: "Update available label") + " \(release.version)")
                    }
                    .font(.caption2.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.accentColor, in: Capsule())
                .help(String(localized: "查看新版本说明", comment: "Tooltip on update badge"))

            case .failed(let message):
                // A background check failing is not actionable, so it is only
                // a retry affordance with the reason as a tooltip.
                Button(String(localized: "检查更新", comment: "Manual update check link")) {
                    Task { await model.checkForUpdates() }
                }
                .buttonStyle(.link)
                .font(.caption2)
                .help(message)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.updateState)
    }

    private func footerLink(_ title: String, _ url: URL) -> some View {
        Link(title, destination: url)
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(url.absoluteString)
    }
}

#Preview {
    OnboardingView()
}
