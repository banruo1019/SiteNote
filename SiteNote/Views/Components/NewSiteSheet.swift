//
//  NewSiteSheet.swift
//  SiteNote
//
//  新建工地 sheet:工地名 + (可选)地址锚点。
//
//  保存逻辑:
//  1. 工地名进 SiteTagsStorage(去重)
//  2. 如果选了地址坐标,写 SiteCentroidsStorage.set(...)——绕过"用户跑过去 AI 自学"
//     路径,**新建后立刻**有 GPS 锚点供下次录音匹配。
//  3. 关 sheet,父级把更新后的 list 拿回去。
//

import SwiftUI
import CoreLocation

struct NewSiteSheet: View {
    /// 父级把"保存成功"的 site name 拿回去用,通常用来刷新列表 + 选中新工地。
    var onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedAddress: String? = nil
    @State private var selectedCoordinate: CLLocationCoordinate2D? = nil

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("工地名") {
                    TextField("如 悉尼 Olympic Park", text: $name)
                        .font(.system(size: 15))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("地址(可选)") {
                    SiteAddressPicker(
                        selectedAddress: $selectedAddress,
                        selectedCoordinate: $selectedCoordinate
                    )
                }
            }
            .industrialForm()
            .navigationTitle("新建工地")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        SiteTagsStorage.add(trimmed)
        if let coord = selectedCoordinate {
            // 用户主动选了地址 = 给一个比较高的初始权重,避免后续少数零散样本快速漂走。
            SiteCentroidsStorage.set(
                siteName: trimmed,
                latitude: coord.latitude,
                longitude: coord.longitude,
                sampleCount: 10
            )
        }
        onSaved(trimmed)
        dismiss()
    }
}
