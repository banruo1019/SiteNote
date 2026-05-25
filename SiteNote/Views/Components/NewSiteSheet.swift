//
//  NewSiteSheet.swift
//  SiteNote
//
//  新建工地 sheet — v1.5 改造:**直接用 AddressAutocompleteField 选真实地址**,
//  siteTag 隐式 = address(和 SitePresetEditor 新建模式行为一致)。
//
//  设计动机:
//  - 老版让用户手输地址 + 启发式派生工地短名,字符串拼起来后续容易混淆,
//    且没用 MKLocalSearch 真实地址校验,导致用户的地址被当成普通字符串。
//  - 新版直接 MKLocalSearch autocomplete → 选中后 enrich 拉全字段
//    (Street, Suburb STATE Postcode, Country)→ 写入 address,
//    siteTag 同步 = address。一处输入,后续 PDF Header + 报告项目名都直接拿到完整地址。
//
//  保存逻辑:
//  1. SiteTagsStorage.add(siteTag = address) — 工地标签去重列表
//  2. SitePresetStorage.add(SitePreset(siteTag: address, address: address))
//     — 同 siteTag 已有预设会更新 address(SitePresetStorage.add 的语义)
//  3. 回调把 (siteName=address, address) 给调用方(签名保持向后兼容)
//

import SwiftUI

struct NewSiteSheet: View {
    /// 保存成功回调。返回 (工地名, 地址),v1.5 起两者相等;
    /// 签名保持以兼容旧 caller。
    var onSaved: (_ siteName: String, _ address: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var address: String = ""

    private var locale: Locale { AppLanguageManager.currentLocale }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedAddress.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    addressSection
                    hintCard
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(Ink.bg)
            .navigationTitle(String(localized: "新建工地", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消", locale: locale)) { dismiss() }
                        .foregroundStyle(Ink.fg)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Text(String(localized: "保存", locale: locale))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(canSave ? Ink.bg : Ink.fgDim)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(canSave ? Ink.fg : Ink.card)
                            )
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    /// 地址 section:icon + label + AddressAutocompleteField(MKLocalSearchCompleter)。
    /// 选中候选后异步 enrich 拉完整 Street, Suburb STATE Postcode, Country。
    private var addressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                Text(String(localized: "工地地址", locale: locale))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.fg)
            }
            .padding(.horizontal, 4)

            AddressAutocompleteField(
                text: $address,
                placeholder: "如 123 Sample St, Sydney NSW 2000"
            )
        }
    }

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(Ink.fgDim)
                .padding(.top, 1)
            Text(String(
                localized: "地址会作为工地标识,后续录音、报告项目名都用它。导出 Inspection PDF 时 Header 自动填,不用再录一遍。",
                locale: locale
            ))
            .font(.system(size: 12))
            .foregroundStyle(Ink.fg2)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Ink.card)
        )
    }

    private func save() {
        let addr = trimmedAddress
        guard !addr.isEmpty else { return }

        // v1.5:siteTag = address(隐式相等)
        let siteTag = addr

        // 1) 工地标签去重列表
        SiteTagsStorage.add(siteTag)
        // 2) preset 同 siteTag 已存在则更新 address,否则新建
        if let existing = SitePresetStorage.find(siteTag: siteTag) {
            var updated = existing
            updated.address = addr
            SitePresetStorage.add(updated)
        } else {
            SitePresetStorage.add(SitePreset(siteTag: siteTag, address: addr))
        }

        onSaved(siteTag, addr)
        dismiss()
    }
}
