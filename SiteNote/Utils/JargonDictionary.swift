//
//  JargonDictionary.swift
//  SiteNote
//
//  统一的"工地行业词典":同时给两个地方用——
//  1. SFSpeechRecognizer.contextualStrings(无模型转录的 hint,提升识别准确率)
//  2. AIService.polishTranscription 的 prompt(让 AI 知道哪些是专业词,不要瞎改)
//
//  词典来源 3 类合并(去重 + 去空白 + 30 字符以内):
//  - **静态 baseline**:107 个澳洲建筑工地通用词(本文件下方写死)
//  - **动态用户数据**:已建的工地名 / 分类 / 模板 / 条款,从 storage 实时拉
//  - **用户自定义**:JargonStorage 里维护的"专业词汇"(用户在 Settings 加)
//
//  Apple SFSpeechRecognizer 文档:每条 ≤30 字符,数组总大小 ≤50KB(~1500 词足够)。
//

import Foundation

enum JargonDictionary {

    /// 给 SFSpeechRecognizer 用。合并三方词源 + 去重 + 过长截断。
    static func contextualStrings() -> [String] {
        var all = Set<String>()
        all.formUnion(baseline)
        all.formUnion(SiteTagsStorage.load())
        all.formUnion(SubTagsStorage.load().map { $0.name })
        all.formUnion(ClauseRefsStorage.load())
        all.formUnion(JargonStorage.loadCustomTerms())

        return all
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 30 }
    }

    /// 给 AI prompt 用。返回逗号分隔的字符串(节省 token,且 AI 一行能扫完)。
    /// 按字母序排,稳定 prompt → cache 命中率高。
    static func contextHintForAI() -> String {
        contextualStrings().sorted().joined(separator: ", ")
    }

    // MARK: - Baseline 静态词典(2026-04 整合自澳洲工地通用词 + 中英混词)

    /// 107 词,**首批不要轻易改**——改了等于改 STT 的 prior,会影响识别。
    /// 加新词推荐走"用户自定义"(Settings → AI → 专业词汇),不要改这个常量。
    private static let baseline: [String] = [
        // A. 澳洲税务 / 商务缩写
        "ABN", "ACN", "ATO", "GST",

        // B. 法规 / 标准 / 文件类型
        "AS4000", "AS3600", "BCA", "NCC", "BAL",
        "RFI", "EOT", "ITP", "NCR", "JSA", "SWMS", "WHS", "MSDS",

        // C. 项目管理 / 设计缩写
        "PM", "QA", "QC", "PPE", "BIM", "CAD", "IFC", "CPM", "WBS", "SOV",

        // D. 图纸 / 工种缩写
        "arch", "archi", "elec", "mech", "hydraulic", "hydro",
        "struct", "civil", "fab", "plast", "plumb",

        // E. 角色 / 联系方
        "subby", "subbie", "subcontractor", "foreman", "supervisor",
        "site manager", "sparky", "sparkie", "chippie", "brickie",
        "plumber", "tradie", "lollipop worker",

        // F. 材料(中英混)
        "concrete", "打混凝土", "rebar", "钢筋",
        "plasterboard", "gyprock", "石膏板",
        "render", "批荡", "formwork", "模板",
        "scaffolding", "脚手架", "mesh", "钢筋网",
        "screed", "自流平", "blockwork",
        "acoustic batt", "insulation",

        // G. 设备 / 机械
        "excavator", "挖机", "crane", "吊车", "bobcat",
        "EWP", "scissor lift", "forklift", "scaffold", "hoist",

        // H. 施工动作 / 流程
        "pour", "打浇", "strip", "fix-out", "hand-over",
        "defects", "snag list", "punch list", "variation", "rain-day",

        // I. 检查 / 验收
        "inspection", "巡检", "hold point", "witness point",
        "sign-off", "certify", "completion",

        // J. 进度 / 商务
        "progress claim", "milestone", "programme",
        "lookahead", "baseline", "tender", "quote",

        // K. 单位
        "m³", "方", "m²", "kN", "kPa", "MPa",

        // L. 时间 / 文化
        "arvo", "smoko", "knock-off", "bundy-off", "RDO", "working back"
    ]
}
