//
//  SiteAddressPicker.swift
//  SiteNote
//
//  地址联想搜索 + 选定锚点。Apple Maps 标准模式:用户输入"悉尼 Olympic Park",
//  下面弹自动联想列表(MKLocalSearchCompleter,无网时退化为本地缓存),点选后
//  后台跑 MKLocalSearch 拿到精确坐标,显示在 picker 下方。
//
//  对外:
//  - 双向绑定 `selectedAddress: String?` 和 `selectedCoordinate: CLLocationCoordinate2D?`
//  - 用户清除地址时两个都置 nil
//
//  对工地一线的考量:
//  - 输入框够大(56pt),手套点得中
//  - 联想列表每项 56pt 高,字号 15
//  - 没网仍能输入(只是没联想),用户保存时 geocode 失败提示
//

import SwiftUI
import MapKit
import Combine

struct SiteAddressPicker: View {
    @Binding var selectedAddress: String?
    @Binding var selectedCoordinate: CLLocationCoordinate2D?

    @State private var query: String = ""
    @State private var completer = AddressCompleter()
    @State private var resolvingFor: String? = nil
    @State private var resolveError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 已选定:展示卡片 + 清除按钮
            if let addr = selectedAddress, let coord = selectedCoordinate {
                selectedCard(addr: addr, coord: coord)
            } else {
                searchField
                if !completer.results.isEmpty {
                    suggestionList
                }
                if let err = resolveError {
                    Text(err)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.red)
                }
                Text("可选。填了之后这个工地就有 GPS 锚点,以后在这附近录的速记会自动建议归到这里。")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .foregroundStyle(Ink.fgDim)
            TextField("搜索地址(如 Sydney Olympic Park)", text: $query)
                .font(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: query) { _, new in
                    completer.update(query: new)
                    resolveError = nil
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Ink.line, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(completer.results.prefix(6).enumerated()), id: \.offset) { idx, item in
                Button {
                    pick(item)
                } label: {
                    HStack(spacing: 10) {
                        if resolvingFor == item.title {
                            ProgressView().scaleEffect(0.8)
                                .frame(width: 16)
                        } else {
                            Image(systemName: "mappin")
                                .font(.system(size: 12))
                                .foregroundStyle(Ink.fgDim)
                                .frame(width: 16)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Ink.fg)
                                .lineLimit(1)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Ink.fgDim)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(resolvingFor != nil)
                if idx < min(5, completer.results.count - 1) {
                    Divider().overlay(Ink.line)
                }
            }
        }
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Ink.line, lineWidth: 0.5)
        )
    }

    private func selectedCard(addr: String, coord: CLLocationCoordinate2D) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Ink.accentBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text(addr)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Ink.fg)
                    .lineLimit(2)
                Text(String(format: "%.5f, %.5f", coord.latitude, coord.longitude))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Ink.fgDim)
            }
            Spacer()
            Button {
                selectedAddress = nil
                selectedCoordinate = nil
                query = ""
                completer.update(query: "")
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Ink.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Ink.accentBlue.opacity(0.4), lineWidth: 1)
        )
    }

    /// 用户点联想项 → MKLocalSearch 拿到精确坐标 + 完整地址(街道/suburb/STATE/postcode/country)。
    private func pick(_ item: AddressCompleter.Suggestion) {
        resolveError = nil
        resolvingFor = item.title
        let request = MKLocalSearch.Request(completion: item.completion)
        let search = MKLocalSearch(request: request)
        search.start { response, err in
            DispatchQueue.main.async {
                resolvingFor = nil
                if let placemark = response?.mapItems.first?.placemark {
                    let full = AddressEnrichment.format(placemark: placemark)
                        ?? AddressEnrichment.fallback(for: item.completion)
                    selectedAddress = full
                    selectedCoordinate = placemark.coordinate
                    query = ""
                    completer.update(query: "")
                } else {
                    resolveError = "解析地址失败:\(err?.localizedDescription ?? "请检查网络")"
                }
            }
        }
    }
}

// MARK: - MKLocalSearchCompleter 的 SwiftUI 友好包装

@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let completion: MKLocalSearchCompletion
    }

    var results: [Suggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        results = completer.results.map { c in
            Suggestion(title: c.title, subtitle: c.subtitle, completion: c)
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        results = []
    }
}

// MARK: - 详细地址解析

/// 把一个 MKLocalSearchCompletion enrich 成 `Street, Suburb STATE Postcode, Country`
/// 格式的完整地址(澳洲场景:e.g. "123 Sample St, Sydney NSW 2000, Australia")。
///
/// 设计:
/// - 跑一次 MKLocalSearch 拿 top1 mapItem,从 placemark 提取字段。
/// - 任一字段缺失就跳过(用 compactMap + filter),不会出现 ", , NSW, "。
/// - 失败 / 超时 / 取消时 fallback 用 completion.title + completion.subtitle 拼。
/// - 调用方负责 Task cancellation(连按时取消上一次)。
enum AddressEnrichment {
    /// 拉详细地址。失败时返回 fallback(title+subtitle)而不是 throw。
    static func resolve(completion: MKLocalSearchCompletion) async -> String {
        let request = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: request)
        do {
            let response = try await search.start()
            if Task.isCancelled { return fallback(for: completion) }
            if let placemark = response.mapItems.first?.placemark {
                return format(placemark: placemark) ?? fallback(for: completion)
            }
            return fallback(for: completion)
        } catch {
            return fallback(for: completion)
        }
    }

    /// 用 placemark 字段拼:`"<street>, <suburb> <STATE> <postcode>, <country>"`。
    /// 任一段为空就 skip 整段,不留尾巴逗号。
    static func format(placemark: MKPlacemark) -> String? {
        let street = [placemark.subThoroughfare, placemark.thoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let suburb = (placemark.subLocality ?? placemark.locality)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let state = placemark.administrativeArea?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let postcode = placemark.postalCode?
            .trimmingCharacters(in: .whitespaces) ?? ""

        let line2 = [suburb, state, postcode]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let country = placemark.country?
            .trimmingCharacters(in: .whitespaces) ?? ""

        let segments = [street, line2, country]
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return nil }
        return segments.joined(separator: ", ")
    }

    static func fallback(for completion: MKLocalSearchCompletion) -> String {
        [completion.title, completion.subtitle]
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
