//
//  AddressAutocompleteField.swift
//  SiteNote
//
//  地址输入框 + 实时联想(MKLocalSearchCompleter)。
//
//  设计原则:
//  - 纯展示组件,只管 text binding 和"出现 / 隐藏"联想列表。
//  - 选中候选 → 写回 binding,并清空候选列表(避免列表挡住后续 section)。
//  - 不解析坐标,不调 MKLocalSearch。需要 GPS 锚点的场景请用 SiteAddressPicker。
//  - 把 MKLocalSearchCompleter 的 delegate 包成 @Observable AddressCompleter
//    (实现在 SiteAddressPicker.swift 内,这里复用同一个 class)。
//
//  用法:
//    AddressAutocompleteField(
//      text: $address,
//      placeholder: "地址(如 123 SAMPLE ST...)"
//    )
//
//  视觉:
//  - 内嵌 TextField(继承外层 Form 的样式),下方紧贴一个 inline 候选 list。
//  - 候选最多 6 条,每条 title + subtitle,点击写入 binding。
//

import SwiftUI
import MapKit

struct AddressAutocompleteField: View {
    @Binding var text: String
    var placeholder: LocalizedStringKey

    /// 用户从候选 list 里选过一次后,要把列表收掉,
    /// 避免点击后列表还挂着挡住下一段。
    @State private var suppressNextUpdate: Bool = false
    @State private var completer = AddressCompleter()
    /// 上一次 enrich 任务。用户连点不同候选时取消前一个,避免老结果覆盖新结果。
    @State private var enrichTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onChange(of: text) { _, newValue in
                    if suppressNextUpdate {
                        suppressNextUpdate = false
                        return
                    }
                    completer.update(query: newValue)
                }

            if !completer.results.isEmpty {
                suggestionList
            }
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(completer.results.prefix(6).enumerated()), id: \.offset) { idx, item in
                Button {
                    pick(item)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin")
                            .font(.system(size: 12))
                            .foregroundStyle(Ink.fgDim)
                            .frame(width: 16)
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

    /// 用户点联想项:
    /// 1. 先立即写入 title+subtitle 占位(响应感),并把列表收掉。
    /// 2. 后台跑 MKLocalSearch 把 placemark 拼成
    ///    `"<street>, <suburb> <STATE> <postcode>, <country>"`,回来后覆盖。
    /// 3. 用户连点不同候选时,取消上一次 enrich 避免老结果盖新结果。
    private func pick(_ item: AddressCompleter.Suggestion) {
        // 立即先写 title+subtitle 占位 → 用户立刻看到反馈,列表收掉。
        let placeholderFull = AddressEnrichment.fallback(for: item.completion)
        suppressNextUpdate = true
        text = placeholderFull
        completer.update(query: "")

        // 取消上一次未完成的 enrich,避免老结果覆盖新选择。
        enrichTask?.cancel()
        let completion = item.completion
        enrichTask = Task { @MainActor in
            let detailed = await AddressEnrichment.resolve(completion: completion)
            if Task.isCancelled { return }
            // 用户在 enrich 期间又改了输入(text 已不是占位)就别覆盖。
            guard text == placeholderFull else { return }
            // 同样先 suppress,避免覆盖触发 completer 重新弹列表。
            suppressNextUpdate = true
            text = detailed
        }
    }
}
