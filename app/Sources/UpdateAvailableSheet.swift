//
//  UpdateAvailableSheet.swift
//  KISSTranslator
//
//  Sheet shown when the update check finds a newer release.
//
//  It intentionally does not attempt to install anything: releases of this
//  project are unsigned, so replacing a running app would be refused by
//  Gatekeeper. The sheet therefore explains the update and hands the user a
//  download link plus the exact replacement steps.
//

import SwiftUI

struct UpdateAvailableSheet: View {
    let release: UpdateRelease
    let currentVersion: String

    let onDownload: () -> Void
    let onViewAllReleases: () -> Void
    let onLater: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            notes
            Divider()
            footnote
            actions
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white, Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "发现新版本", comment: "Update sheet title"))
                    .font(.title3.weight(.semibold))
                Text("\(currentVersion) → \(release.version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if release.isPrerelease {
                    Label(
                        String(localized: "预发布版本", comment: "Prerelease badge"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    @ViewBuilder
    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let notes = release.notes {
                    // Release notes are Markdown; render as selectable plain
                    // text so no embedded HTML/Markdown quirks can break layout.
                    Text(verbatim: notes)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(String(localized: "该版本没有提供更新说明。", comment: "No release notes"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxHeight: 180)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(String(localized: "下载后把应用拖入「应用程序」文件夹覆盖旧版本即可。",
                             comment: "Replacement instructions"))
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let publishedAt = release.publishedAt {
                Text(
                    String(localized: "发布日期", comment: "Release date label")
                        + " " + publishedAt.formatted(date: .abbreviated, time: .omitted)
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button(String(localized: "查看全部版本", comment: "View all releases"), action: onViewAllReleases)
                .buttonStyle(.link)
                .font(.callout)

            Spacer()

            Button(String(localized: "以后再说", comment: "Dismiss update sheet")) {
                onLater()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button(action: onDownload) {
                Text(
                    release.downloadURL == nil
                        ? String(localized: "打开下载页面", comment: "Open release page")
                        : String(localized: "下载", comment: "Download the update")
                )
                .fontWeight(.semibold)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

#Preview {
    UpdateAvailableSheet(
        release: UpdateRelease(
            version: "2.2.0",
            pageURL: URL(string: "https://github.com/ftzahao/kiss-translator-safari/releases")!,
            downloadURL: nil,
            notes: "## 更新内容\n\n- 升级上游至 2.2.0\n- 修复 Safari 26 上字幕翻译的问题",
            publishedAt: Date(),
            isPrerelease: false
        ),
        currentVersion: "2.1.1",
        onDownload: {},
        onViewAllReleases: {},
        onLater: {}
    )
}
