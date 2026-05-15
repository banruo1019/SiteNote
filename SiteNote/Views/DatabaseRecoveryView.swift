//
//  DatabaseRecoveryView.swift
//  SiteNote
//
//  ModelContainer 创建失败时的兜底界面。三个出路:
//    1. 重试初始化(可能是临时磁盘问题)
//    2. 导诊断包(发给开发者排查)
//    3. 重置数据库(最后手段,会清空所有速记/LogEntry)
//
//  设计原则:不假装"加载中",直接告诉用户"数据库异常,这是恢复选项",
//  保持冷静工程感。给用户 agency 比假装一切正常更可靠。
//

import SwiftUI

struct DatabaseRecoveryView: View {
    let error: Error
    let retry: () -> Void

    @State private var isExportingDiagnostic = false
    @State private var diagnosticURL: URL?
    @State private var diagnosticError: String?
    @State private var showsResetConfirm = false
    @State private var resetCountdown: Int? = nil
    @State private var resetTask: Task<Void, Never>? = nil

    var body: some View {
        ZStack {
            Ink.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    errorBlock
                    actions
                    Spacer(minLength: 40)
                    contactBlock
                }
                .padding(24)
            }
        }
        .sheet(item: Binding(
            get: { diagnosticURL.map { DiagnosticShareItem(url: $0) } },
            set: { _ in diagnosticURL = nil }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert("导出诊断包失败", isPresented: Binding(
            get: { diagnosticError != nil },
            set: { if !$0 { diagnosticError = nil } }
        )) {
            Button("知道了") { diagnosticError = nil }
        } message: {
            Text(diagnosticError ?? "")
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Ink.red)
            Text("SiteNote 启动失败")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Ink.fg)
            Text("数据库无法初始化。你的数据**可能仍然安全**,只是这次没读上来。先试下面的恢复步骤,不行再联系开发者。")
                .font(.system(size: 14))
                .foregroundStyle(Ink.fgDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 错误详情

    private var errorBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("错误详情")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
            Text(error.localizedDescription)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Ink.fg)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Ink.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - 三个动作

    private var actions: some View {
        VStack(spacing: 10) {
            actionButton(
                title: "重试加载",
                subtitle: "如果是临时问题(刚装/刚关机)通常这一下就好",
                icon: "arrow.clockwise",
                tone: .primary,
                disabled: resetCountdown != nil
            ) {
                retry()
            }

            actionButton(
                title: isExportingDiagnostic ? "正在打包..." : "导出诊断包",
                subtitle: "把出错的数据库 + 设置打包成 ZIP 发给开发者排查",
                icon: "square.and.arrow.up",
                tone: .neutral,
                disabled: isExportingDiagnostic || resetCountdown != nil
            ) {
                exportDiagnostic()
            }

            if let countdown = resetCountdown {
                resetCountdownRow(countdown: countdown)
            } else {
                actionButton(
                    title: "重置数据库",
                    subtitle: "**最后手段** · 会清空所有速记/LogEntry。建议先导诊断包再做。",
                    icon: "trash",
                    tone: .destructive,
                    disabled: false
                ) {
                    showsResetConfirm = true
                }
                .alert("确定要重置数据库吗?", isPresented: $showsResetConfirm) {
                    Button("取消", role: .cancel) {}
                    Button("我已导出诊断包,继续重置", role: .destructive) {
                        startResetCountdown()
                    }
                } message: {
                    Text("此操作不可撤销。所有速记 / 日志条 / 分享记录都会被删除。录音和照片文件保留在沙盒里(诊断包里也有一份)。")
                }
            }
        }
    }

    // MARK: - 联系区

    private var contactBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("还是不行?")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
            Text("把诊断包发到 banruostudio@gmail.com,主题写「SiteNote 启动失败」。请附上你的 iOS 版本和 App 版本(在设置 → 关于里看)。")
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 重置倒计时

    private func resetCountdownRow(countdown: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Ink.red)
            Text("\(countdown) 秒后清空数据库")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Ink.red)
                .contentTransition(.numericText())
            Spacer()
            Button("取消") {
                cancelReset()
            }
            .buttonStyle(.bordered)
            .font(.system(size: 13, weight: .semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 通用按钮

    private enum ButtonTone { case primary, neutral, destructive }

    private func actionButton(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        icon: String,
        tone: ButtonTone,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor(for: tone))
                    .frame(width: 28, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(textColor(for: tone))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fgDim)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.card)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Ink.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func iconColor(for tone: ButtonTone) -> Color {
        switch tone {
        case .primary: return Ink.accentBlue
        case .neutral: return Ink.fg
        case .destructive: return Ink.red
        }
    }

    private func textColor(for tone: ButtonTone) -> Color {
        switch tone {
        case .destructive: return Ink.red
        default: return Ink.fg
        }
    }

    // MARK: - 动作实现

    private func exportDiagnostic() {
        isExportingDiagnostic = true
        Task {
            do {
                let url = try DiagnosticPackager.createDiagnosticZip(
                    errorDescription: error.localizedDescription
                )
                await MainActor.run {
                    diagnosticURL = url
                    isExportingDiagnostic = false
                }
            } catch {
                await MainActor.run {
                    diagnosticError = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    isExportingDiagnostic = false
                }
            }
        }
    }

    private func startResetCountdown() {
        resetTask?.cancel()
        resetCountdown = 3
        resetTask = Task { @MainActor in
            for i in stride(from: 3, through: 1, by: -1) {
                resetCountdown = i
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            DiagnosticPackager.resetDatabase()
            resetCountdown = nil
            resetTask = nil
            // 重置完直接重试加载——理论上现在是空库,会成功。
            retry()
        }
    }

    private func cancelReset() {
        resetTask?.cancel()
        resetTask = nil
        resetCountdown = nil
    }
}

private struct DiagnosticShareItem: Identifiable {
    let id = UUID()
    let url: URL
}
