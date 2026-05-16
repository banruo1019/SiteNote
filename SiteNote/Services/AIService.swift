//
//  AIService.swift
//  SiteNote
//
//  AI 综合服务。根据用户设置在两个引擎间路由:
//    - `openai`:OpenAI GPT API(需 API key,云端,质量高)
//    - `local`:Apple Foundation Models(iOS 26+,本地,隐私)
//    - `auto`(默认):优先 OpenAI,失败/无 key 自动 fallback 到 local
//
//  `suggestTags` 是纯规则,不走 AI 引擎。
//

import Foundation
import UIKit
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

/// AI 引擎选择。
enum AIEngine: String, CaseIterable, Identifiable {
    case auto
    case openai
    case local

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .auto: return String(localized: "自动(推荐)", locale: AppLanguageManager.currentLocale)
        case .openai: return String(localized: "仅 OpenAI GPT", locale: AppLanguageManager.currentLocale)
        case .local: return String(localized: "仅本地 Apple Intelligence", locale: AppLanguageManager.currentLocale)
        }
    }
}

@MainActor
final class AIService {

    static let shared = AIService()

    enum AIError: LocalizedError {
        case unavailable
        case generationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return String(localized: "当前没有可用的 AI 引擎。请到「设置 → AI 辅助」配置 OpenAI API Key 或启用 Apple Intelligence。", locale: AppLanguageManager.currentLocale)
            case .generationFailed(let msg):
                return String(localized: "AI 生成失败:\(msg)", locale: AppLanguageManager.currentLocale)
            }
        }
    }

    struct TagSuggestion: Equatable {
        let suggestedSiteTag: String?
        let suggestedClauseRef: String?
        let reasoning: String?
    }

    struct PhotoAnalysis {
        let description: String
        let suggestedHazard: Bool
        let suggestedAction: String?
        let rawLabels: [String]
    }

    // MARK: - 引擎选择

    /// 当前用户设置的引擎。默认 `.auto`。
    static var currentEngine: AIEngine {
        let raw = UserDefaults.standard.string(forKey: "settings.aiEngine") ?? AIEngine.auto.rawValue
        return AIEngine(rawValue: raw) ?? .auto
    }

    /// 本地 Foundation Models 是否可用。
    static var isLocalAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        return false
        #else
        return false
        #endif
    }

    /// OpenAI 是否配置可用(只查 key,不测连通性)。
    static var isOpenAIAvailable: Bool {
        OpenAIClient.hasAPIKey
    }

    /// 为向后兼容保留的旧接口。
    static var isLanguageModelAvailable: Bool {
        isLocalAvailable || isOpenAIAvailable
    }

    // MARK: - 1. 转写修复

    /// 修复语音转写:加标点、纠错、规范数字。
    func polishTranscription(_ raw: String) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        // P0:先把用户配置的"快捷词"展开,例如 "打 con" → "打 concrete"。
        // 在送给 AI 之前做,这样 AI 看到的就是展开后的版本,不会再把 concrete 翻译成混凝土
        // (然后又被快捷词反复对齐)。
        let expanded = JargonStorage.applyShortcuts(to: trimmed)

        // P0:把行业词典塞给 AI 当 context,让它知道哪些是专业词不要瞎改。
        // 词典限制在 1500 字以内塞进 prompt(避免 token 爆炸),够覆盖 baseline 107 词 + 用户加的几十个。
        let hintList = JargonDictionary.contextHintForAI()
        let hint = hintList.count <= 1500 ? hintList : String(hintList.prefix(1500))

        let prompt = """
        你是悉尼建筑工地语音转写的修复+提炼助手。下面是工地一线人员说的话(中英混合,带行业术语),\
        语音识别可能有错字、缺标点、数字格式乱、把英文术语听成相近的中文,且**句首/句中常带说话人对 app 下的命令性短语**——这些命令词不属于内容本身,要去掉。

        修复规则(严格执行):

        1. **去命令头**——把以下"对 app 说话"的短语**完全去掉**(可能在句首,也可能在句中插入):
           - "提醒我 / 提醒一下 / 提醒一下我 / 麻烦提醒我"
           - "记一下 / 记下 / 记下来 / 记录 / 记录一下 / 帮我记 / 帮我记一下 / 给我记"
           - "保存 / 保存一下 / 存一下 / 存起来"
           - "标记 / 做个标记 / 标一下"
           - "录个音 / 录一下"
           - 例 1: "提醒我明天去验钢筋" → "明天去验钢筋"
           - 例 2: "记一下 3 楼漏水了" → "3 楼漏水了"
           - 例 3: "搞完这个提醒我去开会" → "搞完这个去开会"
           - 例 4: "保存一下今天打混凝土 10 方" → "今天打混凝土 10 方"
           - **去掉后剩的部分必须仍是通顺的一段话**;如果去命令词后内容空了,保留命令词。

        2. **保留中英混合**,不要把英文专有名词翻译成中文(例:concrete 不变"混凝土",RFI 不变"信息请求单")。

        3. **数字单位规范化**:"十方"→"10m³"、"两吨"→"2t"、"三米五"→"3.5m"、"五百方"→"500m³"。

        4. **行业术语保持原拼写**:看到下方"已知专业词汇"里的词,**完全保留**(包括大小写)。

        5. 加合适标点(中文用 ",。"; 英文用 ", . "),让句子分清楚。

        6. 不要添加新内容、不要解释、不要加引号、不要改原意。**只返回修复+提炼后的一段文本**。

        已知专业词汇(出现按这个写法): \(hint)

        原文:
        \(expanded)

        修复后:
        """

        return try await runText(prompt: prompt, fallbackToRaw: expanded)
    }

    // MARK: - 2. 自动标签推断(纯规则)

    func suggestTags(
        transcription: String,
        availableSites: [String],
        availableClauses: [String]
    ) -> TagSuggestion {
        let normalized = transcription.lowercased()

        let site = availableSites.first {
            normalized.contains($0.lowercased())
        }

        let clause = availableClauses.first {
            let keyPart = $0.lowercased()
            return normalized.contains(keyPart)
                || normalized.contains(extractClauseNumber($0))
        }

        var reasonParts: [String] = []
        if let s = site { reasonParts.append(String(localized: "工地「\(s)」", locale: AppLanguageManager.currentLocale)) }
        if let c = clause { reasonParts.append(String(localized: "条款「\(c)」", locale: AppLanguageManager.currentLocale)) }
        let reasoning: String?
        if reasonParts.isEmpty {
            reasoning = nil
        } else {
            let joined = reasonParts.joined(separator: "、")
            reasoning = String(localized: "检测到内容涉及: \(joined)", locale: AppLanguageManager.currentLocale)
        }

        return TagSuggestion(
            suggestedSiteTag: site,
            suggestedClauseRef: clause,
            reasoning: reasoning
        )
    }

    private func extractClauseNumber(_ ref: String) -> String {
        let digits = ref.filter { $0.isNumber || $0 == "." }
        return digits.isEmpty ? ref.lowercased() : digits
    }

    // MARK: - 3. 照片 AI 分析

    func analyzePhoto(_ image: UIImage) async throws -> PhotoAnalysis {
        let engine = Self.currentEngine
        let labels = (try? await classifyImage(image)) ?? []

        // OpenAI 可以直接理解图片(多模态),不需要先做 Vision 分类
        if engine == .openai || engine == .auto, Self.isOpenAIAvailable {
            if let analysis = try? await analyzePhotoOpenAI(image) {
                return analysis
            }
            if engine == .openai {
                // 严格 OpenAI 模式不回退
                throw AIError.generationFailed(String(localized: "OpenAI 图像分析失败", locale: AppLanguageManager.currentLocale))
            }
        }

        if engine == .local || engine == .auto, Self.isLocalAvailable {
            if let analysis = try? await analyzePhotoLocal(labels: labels) {
                return analysis
            }
        }

        // 全部失败:只返回 Vision 原始标签
        let labelsStr = labels.prefix(3).joined(separator: "、")
        return PhotoAnalysis(
            description: labels.isEmpty ? String(localized: "未能识别照片内容", locale: AppLanguageManager.currentLocale) : String(localized: "识别到: \(labelsStr)", locale: AppLanguageManager.currentLocale),
            suggestedHazard: false,
            suggestedAction: nil,
            rawLabels: labels
        )
    }

    private func analyzePhotoOpenAI(_ image: UIImage) async throws -> PhotoAnalysis {
        let prompt = """
        你是澳洲建筑工地的质量安全检查员。看这张照片,用**一句中文**描述你看到的重点(≤30 字),\
        然后判断是否应该标记为"隐患"(有明显安全或质量问题),最后给一句现场动作建议(≤30 字)。

        用纯文本返回,三行,每行一个字段:
        描述: ...
        隐患: 是 / 否
        建议: ...
        """
        let resp = try await OpenAIClient.chatVision(prompt: prompt, image: image)
        return parseAnalysisResponse(resp, labels: [])
    }

    private func analyzePhotoLocal(labels: [String]) async throws -> PhotoAnalysis {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *),
              SystemLanguageModel.default.availability == .available,
              !labels.isEmpty else {
            throw AIError.unavailable
        }

        let prompt = """
        你是澳洲建筑工地的质量安全检查员。以下是一张现场照片的 AI 图像识别标签:
        \(labels.joined(separator: ", "))

        请:
        1. 用**一句话**中文描述这张照片可能拍了什么(≤30 字)
        2. 判断是否应该标记为"隐患"
        3. 给一句现场动作建议(≤30 字)

        用纯文本返回,每行一个字段:
        描述: ...
        隐患: 是 / 否
        建议: ...
        """
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return parseAnalysisResponse(response.content, labels: labels)
        #else
        throw AIError.unavailable
        #endif
    }

    private func classifyImage(_ image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        // Xcode 26 SDK 的 VNClassifyImageRequest.results 已直接类型化为 [VNClassificationObservation]?,
        // 不再需要 as? 下转型。
        let observations = request.results ?? []
        return observations
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
            .filter { $0.confidence > 0.1 }
            .map { $0.identifier }
    }

    private func parseAnalysisResponse(_ text: String, labels: [String]) -> PhotoAnalysis {
        var description = ""
        var hazard = false
        var action: String?

        for line in text.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("描述") || s.hasPrefix("描述:") {
                description = valueAfterColon(s)
            } else if s.hasPrefix("隐患") {
                hazard = s.contains("是") && !s.contains("否")
            } else if s.hasPrefix("建议") {
                action = valueAfterColon(s)
            }
        }

        if description.isEmpty {
            if labels.isEmpty {
                description = text
            } else {
                let labelsStr = labels.prefix(3).joined(separator: "、")
                description = String(localized: "识别到: \(labelsStr)", locale: AppLanguageManager.currentLocale)
            }
        }

        return PhotoAnalysis(
            description: description,
            suggestedHazard: hazard,
            suggestedAction: action,
            rawLabels: labels
        )
    }

    private func valueAfterColon(_ s: String) -> String {
        let parts = s.split(whereSeparator: { $0 == ":" || $0 == ":" })
        guard parts.count >= 2 else { return "" }
        return parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - 通用文本路由(供 NarrativeService 使用)

    /// 给定 prompt,按引擎设置调用 OpenAI 或本地。`fallbackToRaw` 提供降级文本(完全失败时返回它)。
    /// 需要外部严格失败时应显式调 `runTextStrict`。
    func runText(prompt: String, fallbackToRaw: String) async throws -> String {
        let engine = Self.currentEngine

        if engine == .openai || engine == .auto, Self.isOpenAIAvailable {
            if let result = try? await OpenAIClient.chat(user: prompt) {
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if engine == .openai {
                throw AIError.unavailable
            }
        }

        #if canImport(FoundationModels)
        if engine == .local || engine == .auto,
           #available(iOS 26.0, *),
           SystemLanguageModel.default.availability == .available {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty { return content }
            } catch {
                if engine == .local {
                    throw AIError.generationFailed(error.localizedDescription)
                }
            }
        }
        #endif

        return fallbackToRaw
    }

    /// 严格模式:任一引擎都不可用时抛错(用于必需 AI 的功能,如叙事/claim letter)。
    func runTextStrict(prompt: String) async throws -> String {
        let engine = Self.currentEngine

        if engine == .openai || engine == .auto, Self.isOpenAIAvailable {
            do {
                let result = try await OpenAIClient.chat(user: prompt)
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } catch {
                if engine == .openai {
                    throw AIError.generationFailed(error.localizedDescription)
                }
            }
        }

        #if canImport(FoundationModels)
        if engine == .local || engine == .auto,
           #available(iOS 26.0, *),
           SystemLanguageModel.default.availability == .available {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                let content = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty { return content }
            } catch {
                throw AIError.generationFailed(error.localizedDescription)
            }
        }
        #endif

        throw AIError.unavailable
    }

    // MARK: - 4. 综合分类(omni-classify,Phase B)

    /// AI omni-classify 的 JSON 输出结构。所有字段可空——AI 判断不出就 null。
    struct ClassificationAIOutput: Codable {
        let site: String?
        let subTags: [String]?
        let deadline: String?
        let isHazard: Bool?
        let clauseRef: String?
        /// 每个字段一句理由(中文,≤20 字)。字段名就是 site/subTags/deadline/hazard/clauseRef。
        let reasoning: [String: String]?
        /// 每个字段的置信度 0-1。
        let confidences: [String: Double]?
    }

    /// 一次 AI 调用同时判断工地 / 分类 / deadline / 隐患 / 条款。
    /// - 所有"选项"从参数传入(AI 只能从已有列表选,不生成新值)
    /// - 用于 `NoteClassificationPipeline` 的 Phase B,保存流程后异步跑
    /// - 失败返回 nil,调用方把 Phase A(GPS)结果留住即可,不阻断
    func classifyNote(
        transcription: String,
        availableSites: [String],
        availableSubTags: [String],
        availableClauses: [String]
    ) async -> ClassificationAIOutput? {
        let text = transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, Self.isLanguageModelAvailable else { return nil }

        let sitesList = availableSites.isEmpty ? "(无)" : availableSites.joined(separator: ", ")
        let subsList = availableSubTags.isEmpty ? "(无)" : availableSubTags.joined(separator: ", ")
        let clauseList = availableClauses.isEmpty ? "(无)" : availableClauses.joined(separator: ", ")

        let prompt = """
        你是建筑工地语音速记的智能分类器。读下面一段转写,大多数字段从**已有列表**中选出对应项。
        **subTags / clauses / deadline 不要生成新值**——选不出就填 null。
        **site 例外**:用户明说了工地名(如"在 Olympic Park"、"在地铁西区项目")但列表里没有,
        **可以提议**新工地名,confidence 压到 0.65 表示建议(用户确认后 app 会自动加入工地列表)。
        每项给置信度 0.0-1.0 和一句中文理由(≤20 字)。
        **只返回纯 JSON**,不要 markdown 代码块、不要任何解释。

        可选项:
          sites:    \(sitesList)
          subTags:  \(subsList)
          clauses:  \(clauseList)
          deadline: "inbox" | "today" | "threeDays" | "thisWeek" | "archive"

        JSON schema(所有字段都可 null):
        {
          "site":      string|null,   // 列表里有 → 用列表的;明说但没列 → 给新工地名(confidence ≤ 0.7);未提 → null
          "subTags":   [string],      // 从 subTags 里挑 0-3 个,没匹配给空数组 []
          "deadline":  string|null,   // **只处理明确时间信号**:"今天/明天"→today、"三天内"→threeDays、"这周"→thisWeek、"备忘/记下就行"→archive。"赶紧/有空"这类模糊词给 null
          "isHazard":  boolean|null,  // 转写明显涉及漏电/裂缝/脚手架松动/坠落/火灾/违规 → true。无明显问题 → null(不要 false,避免覆盖用户自己标的)
          "clauseRef": string|null,
          "reasoning": { "site": "...", "subTags": "...", ... },
          "confidences": { "site": 0.9, ... }
        }

        # 示例
        输入: "悉尼 Olympic Park 东区 3 楼混凝土浇筑,配比 C30,钢筋 HRB400。今天下午业主要验收。"
          (sites 包含 "悉尼 Olympic Park",subTags 包含 "混凝土"、"钢筋")
        输出: {
          "site": "悉尼 Olympic Park",
          "subTags": ["混凝土", "钢筋"],
          "deadline": "today",
          "isHazard": null,
          "clauseRef": null,
          "reasoning": {
            "site": "明说 Olympic Park",
            "subTags": "提到混凝土/钢筋",
            "deadline": "下午验收 = 今天"
          },
          "confidences": {
            "site": 0.95, "subTags": 0.9, "deadline": 0.9
          }
        }

        # 本次输入
        \"\"\"
        \(text)
        \"\"\"

        JSON:
        """

        do {
            let raw = try await runTextStrict(prompt: prompt)
            return Self.parseClassificationJSON(raw)
        } catch {
            // B4:把 classify 的失败也 record 到 AIFailureTracker,
            // AIStatusBar 据此变红。之前只 print,用户感知不到。
            print("[SiteNote] classifyNote AI 失败: \(error.localizedDescription)")
            await AIFailureTracker.shared.record(reason: HomeViewModel.aiFailureReason(error))
            return nil
        }
    }

    static func parseClassificationJSON(_ raw: String) -> ClassificationAIOutput? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            if let firstNewline = s.firstIndex(of: "\n") {
                s = String(s[s.index(after: firstNewline)...])
            }
            if let end = s.range(of: "```", options: .backwards) {
                s = String(s[..<end.lowerBound])
            }
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let first = s.firstIndex(of: "{"),
              let last = s.lastIndex(of: "}"),
              first <= last else {
            return nil
        }
        let json = String(s[first...last])
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            return try JSONDecoder().decode(ClassificationAIOutput.self, from: data)
        } catch {
            print("[SiteNote] classifyNote JSON 解析失败: \(error.localizedDescription)")
            return nil
        }
    }
}
