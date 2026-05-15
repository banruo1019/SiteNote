//
//  ProfileSettingsView.swift
//  SiteNote
//
//  Settings 里的"角色切换"页。
//  Onboarding 之外的第二个角色选择入口。可随时切换,立即生效。
//

import SwiftUI
import UIKit

struct ProfileSettingsView: View {
    @State private var manager = UserProfileManager.shared
    @State private var pendingSelection: ProfileKind
    @Environment(\.dismiss) private var dismiss

    init() {
        self._pendingSelection = State(initialValue: UserProfileManager.shared.current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 顶部标题
                VStack(alignment: .leading, spacing: 8) {
                    Text("选个角色")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Ink.fg)
                    Text("App 会按你选的角色调整主屏分组、AI 识别重点、PDF 默认模板。可随时切换。")
                        .font(.system(size: 13))
                        .foregroundStyle(Ink.fgDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // 卡片选择器
                ProfileSelectorView(selection: $pendingSelection, mode: .light)
                    .padding(.horizontal, 16)

                // 当前生效提示 / 应用按钮
                if pendingSelection != manager.current {
                    Button {
                        applyChange()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("切换到 \(pendingSelection.displayName) 模式")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Ink.fg, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Ink.green)
                        Text("当前正在使用 \(manager.current.displayName) 模式")
                            .foregroundStyle(Ink.fgDim)
                    }
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }

                Spacer(minLength: 24)
            }
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("我是")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func applyChange() {
        withAnimation(.easeOut(duration: 0.15)) {
            manager.select(pendingSelection)
        }
        // 反馈三联:notification haptic(成功)+ 自动 dismiss 回上层。
        // 用户站在工地光线下,不会再困惑"切换成功了吗?"——直接回到主屏看到分组已变。
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // 留 0.18s 给 withAnimation 上面那行有时间播完,再 dismiss。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            dismiss()
        }
    }
}
