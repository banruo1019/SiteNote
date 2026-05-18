//
//  SettingsView.swift
//  SiteNote
//
//  v1.5:按 ProfileKind 分流 PM / Engineer。
//  - PM → SiteTeamSettingsRoot(精简版,无建造商联系簿 + 无报告段)
//  - Engineer → EngineerSettingsRoot(完整版,含建造商 + 免责声明 + 邮件模板)
//
//  共用 sub-view(ProfileSettings / CompanyInfo / Team / SitePreset /
//  SavedReports / Trash)两个 root 都引用同一份 file。
//  角色切换是 @Observable 驱动,无需重启。
//
//  v1.3 历史清理(保留):原 InputAISettingsView / RemindersSettingsView /
//  SiteResourcesSettingsView / DataAboutSettingsView 4 个 sub-view 是统一
//  settings 前的 legacy,**已全部删除**(0 caller)。
//

import SwiftUI

struct SettingsView: View {
    @State private var profileManager = UserProfileManager.shared

    var body: some View {
        switch profileManager.current {
        case .siteTeam:
            SiteTeamSettingsRoot()
        case .engineer:
            EngineerSettingsRoot()
        }
    }
}
