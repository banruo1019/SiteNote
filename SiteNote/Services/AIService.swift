//
//  AIService.swift
//  SiteNote
//
//  v1.2 AI 精简后:**只保留语音转写修复**,只走本地 Apple Intelligence
//  (FoundationModels)。OpenAI / GPT-4V / Embedding / Jargon 字典 / 自动分类
//  全部下架。
//
//  不可用时(Apple Intelligence 关 / iPhone 14 及以下 / iOS < 26),
//  polishTranscription 直接返回原文,不报错。语音识别原文是 always 可见的。
//

import Foundation

// FoundationModels 只在 iOS 26+ 存在。**必须 weak link**,否则 iOS 24/25 真机
// dyld 找不到 framework → 启动 SIGKILL。@_weakLinked 让 binary 标记为
// "optional dependency",运行时按需加载。
#if canImport(FoundationModels)
@_weakLinked import FoundationModels
#endif

@MainActor
final class AIService {

    static let shared = AIService()
    private init() {}

    // MARK: - 可用性检查

    /// 本地 Apple Intelligence(FoundationModels)是否可用。
    /// 需要 iPhone 15 Pro/Pro Max / 15+ / iOS 26+ 且用户已在系统设置启用。
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

    /// 兼容旧名 — 仅本地可用即认为 AI 可用(v1.2 已没 OpenAI)。
    static var isLanguageModelAvailable: Bool {
        isLocalAvailable
    }

    // MARK: - 转写修复

    /// 修复 Apple Speech 转写出的口语化文本(加标点、去口癖、规范数字)。
    /// Apple Intelligence 不可用时**直接返回原文**(不抛错,不阻塞)。
    func polishTranscription(_ raw: String) async throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return raw }

        guard Self.isLocalAvailable else { return raw }

        let prompt = """
        你是悉尼建筑工地语音转写的修复助手。下面是一线人员说的话(中英混合,有行业术语),\
        语音识别可能有错字、缺标点、数字格式乱、把英文术语听成相近的中文,且句首/句中常带说话人对 app 下的命令性短语 \
        ——这些命令词不属于内容本身,要去掉。

        修复规则(严格执行):
        1. **不要扩写、不要总结、不要翻译、不要把英文改成中文,反之亦然。** 只修复语音识别错误。
        2. 保留所有专业术语原样(包括中英混合,如 "Level 3 的 reo"、"FFL"、"打 concrete")。
        3. 句首/句中的 "把上面的话改成…"、"现在记一下…"、"等下记录…"、"录入" 之类 **命令性自语** 直接删除。
        4. 数字、单位、日期保持原意(50 → 50,五十 → 50,3 米 → 3m)。
        5. 加标点和换行,让文字易读。
        6. 输出只含修复后的内容文本,**不要前缀或解释**。

        原文:
        \(trimmed)

        修复后:
        """

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                let polished = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !polished.isEmpty {
                    return polished
                }
            } catch {
                // 失败不抛,返回原文。用户至少能看到 Speech 输出。
                #if DEBUG
                print("[AIService] polish 失败,返回原文: \(error.localizedDescription)")
                #endif
            }
        }
        #endif

        return raw
    }
}
