//
//  OpenAIClient.swift
//  SiteNote
//
//  底层 OpenAI Chat Completions + Vision API 客户端。自带 JSON 序列化 / 错误映射。
//  上层 AIService 决定什么时候调它(引擎设置 + fallback 策略)。
//

import Foundation
import UIKit

enum OpenAIClient {

    enum OpenAIError: LocalizedError {
        case missingKey
        case network(String)
        case api(status: Int, body: String)
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .missingKey: return "没有配置 OpenAI API Key。请到「设置 → AI 辅助」填入。"
            case .network(let d): return "网络错误:\(d)"
            case .api(let s, let b): return "OpenAI API 错误(\(s)):\(b.prefix(200))"
            case .decodeFailed: return "OpenAI 响应解析失败。"
            }
        }
    }

    struct Config {
        let apiKey: String
        var textModel: String = "gpt-4o-mini"
        var visionModel: String = "gpt-4o-mini"
        var embeddingModel: String = "text-embedding-3-small"
        var baseURL: URL = URL(string: "https://api.openai.com/v1")!
        /// 请求超时秒数。
        var timeout: TimeInterval = 60
    }

    /// 从 Keychain + AppStorage 组装当前 config。API Key 缺失会抛错。
    static func currentConfig() throws -> Config {
        guard let key = KeychainStorage.load(for: KeychainKeys.openAIAPIKey),
              !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw OpenAIError.missingKey
        }
        let textModel = UserDefaults.standard.string(forKey: "settings.openAITextModel") ?? "gpt-4o-mini"
        let visionModel = UserDefaults.standard.string(forKey: "settings.openAIVisionModel") ?? "gpt-4o-mini"
        let embeddingModel = UserDefaults.standard.string(forKey: "settings.openAIEmbeddingModel") ?? "text-embedding-3-small"
        return Config(
            apiKey: key,
            textModel: textModel,
            visionModel: visionModel,
            embeddingModel: embeddingModel
        )
    }

    /// 是否配置了 API Key(静态查,不测连通性)。
    static var hasAPIKey: Bool {
        guard let key = KeychainStorage.load(for: KeychainKeys.openAIAPIKey) else {
            return false
        }
        return !key.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 纯文本对话

    /// 对话补全。输入 messages,返回 assistant 的一段 content。
    static func chat(
        system: String? = nil,
        user: String,
        config: Config? = nil
    ) async throws -> String {
        let cfg = try config ?? currentConfig()
        var messages: [[String: Any]] = []
        if let system {
            messages.append(["role": "system", "content": system])
        }
        messages.append(["role": "user", "content": user])

        let body: [String: Any] = [
            "model": cfg.textModel,
            "messages": messages,
            "temperature": 0.3
        ]

        return try await post(path: "chat/completions", body: body, config: cfg)
    }

    // MARK: - 视觉对话(图片分析)

    /// 图像 + prompt 对话。img 会被压缩成 JPEG 并 base64 编码。
    static func chatVision(
        prompt: String,
        image: UIImage,
        config: Config? = nil
    ) async throws -> String {
        let cfg = try config ?? currentConfig()
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else {
            throw OpenAIError.network("图片编码失败")
        }
        let base64 = jpeg.base64EncodedString()
        let dataURL = "data:image/jpeg;base64,\(base64)"

        let content: [[String: Any]] = [
            ["type": "text", "text": prompt],
            ["type": "image_url", "image_url": ["url": dataURL]]
        ]
        let body: [String: Any] = [
            "model": cfg.visionModel,
            "messages": [
                ["role": "user", "content": content]
            ],
            "temperature": 0.3,
            "max_tokens": 300
        ]

        return try await post(path: "chat/completions", body: body, config: cfg)
    }

    // MARK: - Embeddings

    /// 单条文本的 embedding。
    static func embed(_ text: String, config: Config? = nil) async throws -> [Double] {
        let results = try await embedBatch([text], config: config)
        return results.first ?? []
    }

    /// 批量 embedding。OpenAI 一次调用就能处理一批,比循环调快得多。
    /// - Parameter texts: 要嵌入的文本,顺序对应返回数组。
    /// - Returns: 每条对应的 embedding 向量。
    static func embedBatch(_ texts: [String], config: Config? = nil) async throws -> [[Double]] {
        guard !texts.isEmpty else { return [] }
        let cfg = try config ?? currentConfig()

        let body: [String: Any] = [
            "model": cfg.embeddingModel,
            "input": texts
        ]

        let url = cfg.baseURL.appendingPathComponent("embeddings")
        var request = URLRequest(url: url, timeoutInterval: cfg.timeout)
        request.httpMethod = "POST"
        request.addValue("Bearer \(cfg.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw OpenAIError.network("请求体编码失败:\(error.localizedDescription)")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenAIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("响应不是 HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.api(status: http.statusCode, body: bodyText)
        }

        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArr = parsed["data"] as? [[String: Any]] else {
            throw OpenAIError.decodeFailed
        }

        // OpenAI 按 index 排序返回,一般已有序。稳妥起见排一下。
        var indexed: [(Int, [Double])] = []
        for item in dataArr {
            guard let idx = item["index"] as? Int,
                  let vec = item["embedding"] as? [Double] else {
                throw OpenAIError.decodeFailed
            }
            indexed.append((idx, vec))
        }
        indexed.sort { $0.0 < $1.0 }
        return indexed.map { $0.1 }
    }

    // MARK: - 共用网络底座

    private static func post(
        path: String,
        body: [String: Any],
        config: Config
    ) async throws -> String {
        let url = config.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url, timeoutInterval: config.timeout)
        request.httpMethod = "POST"
        request.addValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw OpenAIError.network("请求体编码失败:\(error.localizedDescription)")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OpenAIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.network("响应不是 HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.api(status: http.statusCode, body: bodyText)
        }

        guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = parsed["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw OpenAIError.decodeFailed
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
