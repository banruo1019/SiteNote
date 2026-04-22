//
//  SemanticSearchService.swift
//  SiteNote
//
//  Phase 10b:自然语言智能搜索。按 AI 引擎路由 embedding:
//    - OpenAI `text-embedding-3-small` / `-large`(云,质量好,需 API Key)
//    - Apple `NLContextualEmbedding`(本地,免费,需 iOS 17+ 中文模型)
//    - 两者都不可用时 fallback 到关键词子串匹配
//
//  session 内缓存每条 note 的 embedding,避免重复调用。引擎切换时自动清缓存
//  (不同模型的向量空间不兼容)。
//

import Foundation
import NaturalLanguage

@MainActor
final class SemanticSearchService {

    static let shared = SemanticSearchService()

    /// 当前搜索用的 embedding 引擎(和 AIService.currentEngine 关联但不完全相同)。
    private enum EmbeddingEngine: String {
        case openai
        case appleContextual
        case none
    }

    /// noteID → embedding 向量。
    private var cache: [UUID: [Double]] = [:]
    private var lastEngine: EmbeddingEngine?

    private var contextual: NLContextualEmbedding?
    private var contextualAssetsReady: Bool = false

    private init() {}

    /// 至少有一种 embedding 引擎可用。
    static var isAvailable: Bool {
        if OpenAIClient.hasAPIKey { return true }
        if #available(iOS 17.0, *), NLContextualEmbedding(language: .simplifiedChinese) != nil {
            return true
        }
        return false
    }

    /// 按用户 AI 引擎设置 + 可用性决定用哪种 embedding。
    private func resolveEngine() -> EmbeddingEngine {
        let appEngine = AIService.currentEngine
        let openAIAvailable = OpenAIClient.hasAPIKey
        let appleAvailable: Bool = {
            if #available(iOS 17.0, *) {
                return NLContextualEmbedding(language: .simplifiedChinese) != nil
            }
            return false
        }()

        switch appEngine {
        case .openai:
            return openAIAvailable ? .openai : .none
        case .local:
            return appleAvailable ? .appleContextual : .none
        case .auto:
            if openAIAvailable { return .openai }
            if appleAvailable { return .appleContextual }
            return .none
        }
    }

    // MARK: - 公共搜索 API

    /// 对 notes 按查询做语义搜索,返回相似度从高到低(过滤低分项)。
    /// 任一引擎不可用时 fallback 到关键词子串。
    func search(query: String, in notes: [Note], limit: Int = 50) async -> [Note] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return notes }

        let engine = resolveEngine()
        invalidateCacheIfEngineChanged(to: engine)

        switch engine {
        case .none:
            return fallbackRegexSearch(query: trimmed, notes: notes)

        case .openai:
            return await searchWithOpenAI(query: trimmed, notes: notes, limit: limit)

        case .appleContextual:
            if #available(iOS 17.0, *) {
                return await searchWithApple(query: trimmed, notes: notes, limit: limit)
            } else {
                return fallbackRegexSearch(query: trimmed, notes: notes)
            }
        }
    }

    /// 清缓存(note 更新/删除后调用)。
    func invalidate(noteID: UUID) {
        cache.removeValue(forKey: noteID)
    }

    func clearCache() {
        cache.removeAll()
        lastEngine = nil
    }

    // MARK: - OpenAI 路径

    private func searchWithOpenAI(query: String, notes: [Note], limit: Int) async -> [Note] {
        // 1. 找出缓存中没有的 notes,批量计算 embedding
        let missing = notes.filter { cache[$0.id] == nil && !$0.transcription.isEmpty }
        if !missing.isEmpty {
            // 每批最多 100 条,防止请求过大
            let chunkSize = 100
            for chunk in missing.chunked(by: chunkSize) {
                let texts = chunk.map { $0.transcription }
                do {
                    let vectors = try await OpenAIClient.embedBatch(texts)
                    for (note, vec) in zip(chunk, vectors) {
                        cache[note.id] = vec
                    }
                } catch {
                    // 批量失败直接回退正则
                    print("[SiteNote] OpenAI embed batch failed: \(error.localizedDescription)")
                    return fallbackRegexSearch(query: query, notes: notes)
                }
            }
        }

        // 2. 计算 query embedding
        let queryVec: [Double]
        do {
            queryVec = try await OpenAIClient.embed(query)
        } catch {
            return fallbackRegexSearch(query: query, notes: notes)
        }

        // 3. 打分排序
        return rankByCosine(query: queryVec, notes: notes, limit: limit)
    }

    // MARK: - Apple NLContextualEmbedding 路径

    @available(iOS 17.0, *)
    private func searchWithApple(query: String, notes: [Note], limit: Int) async -> [Note] {
        do {
            try await ensureAppleEmbedder()
        } catch {
            return fallbackRegexSearch(query: query, notes: notes)
        }
        guard let queryVec = try? embedApple(query) else {
            return fallbackRegexSearch(query: query, notes: notes)
        }

        for note in notes where cache[note.id] == nil && !note.transcription.isEmpty {
            if let vec = try? embedApple(note.transcription) {
                cache[note.id] = vec
            }
        }

        return rankByCosine(query: queryVec, notes: notes, limit: limit)
    }

    @available(iOS 17.0, *)
    private func ensureAppleEmbedder() async throws {
        if contextual != nil, contextualAssetsReady { return }
        guard let e = NLContextualEmbedding(language: .simplifiedChinese) else {
            throw EmbeddingError.unavailable
        }
        // Xcode 26 SDK 下 `requestEmbeddingAssets` 可能已变名/移除。
        // 直接调 load()——若语言包尚未下载会抛错,上层退回正则搜索。
        try e.load()
        contextual = e
        contextualAssetsReady = true
    }

    @available(iOS 17.0, *)
    private func embedApple(_ text: String) throws -> [Double] {
        guard let e = contextual else { throw EmbeddingError.unavailable }
        let result = try e.embeddingResult(for: text, language: .simplifiedChinese)
        var vec: [Double] = []
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { tokenVec, _ in
            if vec.isEmpty {
                vec = Array(repeating: 0, count: tokenVec.count)
            }
            for i in 0..<min(vec.count, tokenVec.count) {
                vec[i] += tokenVec[i]
            }
            return true
        }
        return vec
    }

    // MARK: - 公共打分

    private func rankByCosine(query: [Double], notes: [Note], limit: Int) -> [Note] {
        var scored: [(Note, Double)] = []
        for note in notes where !note.transcription.isEmpty {
            guard let vec = cache[note.id] else { continue }
            let score = cosine(query, vec)
            if score > 0.3 {
                scored.append((note, score))
            }
        }
        scored.sort { $0.1 > $1.1 }
        return Array(scored.prefix(limit).map { $0.0 })
    }

    private func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Double = 0, normA: Double = 0, normB: Double = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    // MARK: - 引擎变更时清缓存

    private func invalidateCacheIfEngineChanged(to engine: EmbeddingEngine) {
        if lastEngine != engine {
            cache.removeAll()
            lastEngine = engine
        }
    }

    // MARK: - Fallback

    private func fallbackRegexSearch(query: String, notes: [Note]) -> [Note] {
        let lower = query.lowercased()
        return notes.filter { note in
            note.transcription.lowercased().contains(lower)
                || (note.locationAddress?.lowercased().contains(lower) ?? false)
                || (note.siteTag?.lowercased().contains(lower) ?? false)
                || (note.templateName?.lowercased().contains(lower) ?? false)
                || (note.contractClauseRef?.lowercased().contains(lower) ?? false)
        }
    }

    private enum EmbeddingError: Error {
        case unavailable
    }
}

private extension Array {
    /// 按每段 size 切分成子数组。
    func chunked(by size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
