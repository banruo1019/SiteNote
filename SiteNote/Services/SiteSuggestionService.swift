//
//  SiteSuggestionService.swift
//  SiteNote
//
//  Phase A:**规则**判断当前位置属于哪个已知工地。
//  不走 AI——坐标是硬事实,距离算一下就行,AI 反而更慢更错更贵。
//
//  决策表:
//    距离 < 50m  → confidence 0.95(几乎肯定)
//    50 – 100m   → confidence 0.85
//    100 – 200m  → confidence 0.70
//    > 200m      → 不建议(返回 nil)
//
//  为什么 200m 阈值:
//    大工地(地铁站、体育馆)工区可能横跨 100-150m。
//    300m 开始容易跨越到隔壁楼盘误判。200m 是经验值。
//

import Foundation

enum SiteSuggestionService {

    /// 距离阈值:超过这个距离不推荐任何工地。
    static let maxMatchMeters: Double = 200

    /// 给一组坐标,找最近的已知工地中心点。超过 `maxMatchMeters` 返回 nil。
    /// - Returns: (工地名, 到中心点的米数, 置信度)
    static func nearestSite(latitude: Double, longitude: Double) -> (name: String, distanceMeters: Double, confidence: Double)? {
        let centroids = SiteCentroidsStorage.load()
        guard !centroids.isEmpty else { return nil }

        var best: (name: String, distance: Double)?
        for (name, c) in centroids {
            let d = haversineDistance(
                lat1: latitude, lng1: longitude,
                lat2: c.latitude, lng2: c.longitude
            )
            if best == nil || d < best!.distance {
                best = (name, d)
            }
        }

        guard let b = best, b.distance <= maxMatchMeters else { return nil }

        let confidence: Double
        switch b.distance {
        case ..<50:   confidence = 0.95
        case ..<100:  confidence = 0.85
        default:      confidence = 0.70
        }

        return (b.name, b.distance, confidence)
    }

    /// 球面大圆距离(米)。工地场景 <1km,Haversine 精度足够。
    private static func haversineDistance(
        lat1: Double, lng1: Double,
        lat2: Double, lng2: Double
    ) -> Double {
        let earthRadiusMeters: Double = 6_371_000
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }
}
