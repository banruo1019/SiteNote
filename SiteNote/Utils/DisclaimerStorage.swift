//
//  DisclaimerStorage.swift
//  SiteNote
//
//  巡检报告默认 disclaimer 文本。InspectionDraft.disclaimerText 为 nil(或
//  PDF 渲染时未自定义)时,使用这里的内容。
//
//  存 UserDefaults JSON([String])。空数组表示"用 defaults",即用户从未自
//  定义或主动恢复了默认。
//

import Foundation

/// 巡检报告默认 disclaimer 文本。InspectionDraft.disclaimerText 为 nil 时,PDF 用这个。
enum DisclaimerStorage {
    private static let key = "settings.inspectionDisclaimers.v1"

    /// QDE Engineering 报告里那 5 条标准 disclaimer。
    static let defaults: [String] = [
        "This inspection does not include the foundation material and ground stability including: excavations, cuttings, batters and stabilizing elements such as soil nails, rock bolts and ground anchors etc. It is the builder's responsibility to have the Geotechnical engineer inspect and approve prior to placing concrete.",
        "This inspection does not include the formwork, formwork support and back-propping. It has not been inspected and should be separately certified by an experienced formwork engineer.",
        "This inspection does not include epoxy grouted bars, chemical or expansion anchors. The correct installation of these items is the responsibility of the builder.",
        "Reinforcement inspections are subject to final clean out of formwork or excavation and maintaining specified cover during placement of concrete.",
        "The builder must rectify the defects listed in this report as a contractual, Work Health and Safety, building certification requirement."
    ]

    /// 读用户自定义。空数组表示用 defaults。失败/没存过返回空。
    static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// 保存(覆盖)。空数组表示删除自定义,回退到 defaults。
    /// - 空字符串条目会被先过滤掉(避免存"5 条空白")。
    static func save(_ items: [String]) {
        let cleaned = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if cleaned.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(cleaned) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 当前生效的(用户自定义优先,空则用 defaults)。PDF 渲染调用这个。
    static func current() -> [String] {
        let custom = load()
        return custom.isEmpty ? defaults : custom
    }

    /// 恢复到 defaults(清自定义)。
    static func restoreDefaults() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
