//
//  AppHeaderProvider.swift
//  SiteNote
//
//  Chrome(顶部元信息条)要显示的共享数据:当前位置短名 + 天气摘要。
//  不频繁抓(30 分钟一次),所有 Tab 共享一份,避免每切 tab 重新抓。
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AppHeaderProvider {
    static let shared = AppHeaderProvider()

    /// 天气摘要。如 "22°C 晴"。首次加载完成前是 nil。
    private(set) var weatherSummary: String?
    /// 位置短名(取地址的前一段)。如 "Olympic Park" 或 "Sydney"。
    private(set) var locationShort: String?

    /// 上次成功抓的时间,用于节流。
    private var lastFetched: Date?

    /// 数据有效期:30 分钟。
    private let ttl: TimeInterval = 30 * 60

    private let location = LocationService()
    private let weather = WeatherService()

    private init() {}

    /// Chrome onAppear 调一次。已新鲜则直接返回,否则后台刷新。
    func ensureFresh() {
        if let last = lastFetched, Date().timeIntervalSince(last) < ttl {
            return
        }
        Task { await refresh() }
    }

    private func refresh() async {
        // 先用缓存的位置避免拖 UI;有的话立刻刷,没有再去实时问。
        var loc: LocationService.Location? = LocationService.lastSuccessfulLocation()
        if loc == nil {
            loc = try? await location.getCurrentLocation()
        }
        guard let loc else { return }

        // 更新位置短名
        if let addr = loc.address {
            locationShort = Self.shorten(address: addr)
        }

        // 抓天气
        if let w = try? await weather.fetch(
            latitude: loc.latitude,
            longitude: loc.longitude
        ) {
            weatherSummary = w.summary
            lastFetched = Date()
        }
    }

    /// 地址转短名:取逗号前第一个段,超过 12 字截断。
    /// 例 "123 Olympic Blvd, Homebush, NSW" → "123 Olympic Blvd"
    private static func shorten(address: String) -> String {
        let firstPart = address.split(separator: ",").first.map(String.init) ?? address
        let trimmed = firstPart.trimmingCharacters(in: .whitespaces)
        if trimmed.count > 18 {
            return String(trimmed.prefix(16)) + "…"
        }
        return trimmed
    }
}
