//
//  SiteCentroidsStorage.swift
//  SiteNote
//
//  每个工地的"习得中心点"(经纬度均值)。**不是手动配置的,是从实际使用中学来的**。
//
//  工作原理:
//  - 用户在某工地录第一条带工地 tag 的 note → 落库时 observe(site, lat, lng) → 记成初始点
//  - 后续每条 note 都参与加权平均,样本越多中心越准
//  - 新录 note 没有 tag 但有 GPS 时,查最近的中心点 → 作为"AI 建议"给用户
//
//  优势 vs 让用户手动标工地坐标:
//    - 零额外配置
//    - 用户走到哪标到哪,app 自己学
//    - 工地搬了也能自适应(随样本漂移)
//

import Foundation

struct SiteCentroid: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    /// 目前累计观测到的样本数。指数加权时越大越稳。
    var sampleCount: Int
    /// 最近一次更新时间。给未来"几个月没更新的数据降权"留钩子。
    var lastUpdated: Date
}

enum SiteCentroidsStorage {
    private static let key = "settings.siteCentroids.v1"

    static func load() -> [String: SiteCentroid] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: SiteCentroid].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func save(_ dict: [String: SiteCentroid]) {
        guard let data = try? JSONEncoder().encode(dict) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 把一条新的 (site, lat, lng) 样本融进去。
    /// 用简单样本加权平均:newMean = (oldMean * n + sample) / (n + 1)。
    /// 对前 5 条样本影响最大,之后趋于稳定。
    static func observe(siteName: String, latitude: Double, longitude: Double) {
        let name = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        var all = load()
        if let existing = all[name] {
            let n = Double(existing.sampleCount)
            let newLat = (existing.latitude * n + latitude) / (n + 1)
            let newLng = (existing.longitude * n + longitude) / (n + 1)
            all[name] = SiteCentroid(
                latitude: newLat,
                longitude: newLng,
                sampleCount: existing.sampleCount + 1,
                lastUpdated: Date()
            )
        } else {
            all[name] = SiteCentroid(
                latitude: latitude,
                longitude: longitude,
                sampleCount: 1,
                lastUpdated: Date()
            )
        }
        save(all)
    }

    /// **手动设定**某工地的锚定坐标(用户在新建工地时输入地址用,而非 observe 学习)。
    /// 用 `sampleCount` 控制初始权重——传 10 ≈ "已经积累 10 个样本",这样
    /// 后续 observe 不会快速漂移走;真实位置不准时用户去工地几次自然会修正。
    static func set(siteName: String, latitude: Double, longitude: Double, sampleCount: Int = 10) {
        let name = siteName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var all = load()
        all[name] = SiteCentroid(
            latitude: latitude,
            longitude: longitude,
            sampleCount: max(1, sampleCount),
            lastUpdated: Date()
        )
        save(all)
    }

    /// 清掉某工地的中心点(工地删除时调用)。
    static func forget(siteName: String) {
        var all = load()
        all.removeValue(forKey: siteName)
        save(all)
    }

    /// 全清(一键清空软件内容功能用)。
    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
