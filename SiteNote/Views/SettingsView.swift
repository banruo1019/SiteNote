//
//  SettingsView.swift
//  SiteNote
//
//  v1.3:统一 Settings —— PM 和 Engineer 共用一个设置页。
//  内容由 EngineerSettingsRoot 提供(名字保留为 legacy,实际作为统一设置 root)。
//  顶部第 1 项是角色 picker,后续 sections 共用 + 内部按角色微调显示。
//
//  v1.3 后续清理:原 InputAISettingsView / RemindersSettingsView /
//  SiteResourcesSettingsView / DataAboutSettingsView 4 个 sub-view 是
//  统一 settings 前的 legacy,**已全部删除**(0 caller)。需要这些设置项
//  请在 EngineerSettingsRoot 里加,不要再开新 sub-view。
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        EngineerSettingsRoot()
    }
}
