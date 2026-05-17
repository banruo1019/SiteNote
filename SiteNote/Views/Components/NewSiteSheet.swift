//
//  NewSiteSheet.swift
//  SiteNote
//
//  新建工地 sheet:**先输入地址 → 自动派生工地名 → 保存**。
//
//  设计动机:
//  - 真实工地的"名字"几乎都从地址里来(街名 + suburb)。让用户先输地址,
//    工地名自动派生,既省事又能在保存时把地址直接挂到 SitePreset 上,
//    后续导出 Inspection 报告 Header 自动有地址,工程师不再为同一信息重复输入。
//  - 用户随时可以手改工地名,改了之后地址再变也不会覆盖(userEditedName 锁)。
//
//  保存逻辑:
//  1. SiteTagsStorage.add(siteName) — 加入工地标签列表(去重)
//  2. SitePresetStorage.add(SitePreset(siteTag: siteName, address: address))
//     — 同 siteTag 已有预设会被自动更新地址(SitePresetStorage.add 的语义)
//  3. 回调把 (siteName, address) 给调用方
//

import SwiftUI

struct NewSiteSheet: View {
    /// 保存成功回调。返回 (工地名, 地址),调用方按需用。
    /// 旧调用方只关心工地名的,address 可忽略。
    var onSaved: (_ siteName: String, _ address: String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var address: String = ""
    @State private var siteName: String = ""
    /// 用户手动改过工地名后,后续地址变化不再覆盖。
    @State private var userEditedName: Bool = false

    private var locale: Locale { AppLanguageManager.currentLocale }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedName: String {
        siteName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedAddress.isEmpty && !trimmedName.isEmpty
    }

    /// 当前 focus 的字段(决定 input box 是否高亮 Ink.fg 描边)。
    @FocusState private var focusedField: FocusField?
    private enum FocusField: Hashable { case address, name }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    addressSection
                    nameSection
                    hintCard
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            // 键盘弹起时拖动滚动收起键盘,hint card 可见
            .scrollDismissesKeyboard(.interactively)
            // ScrollView 内部 contentInset 跟随 keyboard,让被遮的部分能滚出来
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
            .onAppear {
                // 进入页面默认 focus 地址,光标可见。
                focusedField = .address
            }
        }
    }

    /// 地址 section:icon + label + input box(可多行)+ footer hint。
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

            TextField(
                String(localized: "如 38 FORSYTH ST NORTH WILLOUGHBY", locale: locale),
                text: $address,
                axis: .vertical
            )
            .focused($focusedField, equals: .address)
            .font(.system(size: 15))
            .tint(Ink.fg)
            .lineLimit(2...4)
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .onChange(of: address) { _, newAddr in
                guard !userEditedName else { return }
                siteName = Self.extractSiteName(from: newAddr)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Ink.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        focusedField == .address ? Ink.fg : Ink.line,
                        lineWidth: focusedField == .address ? 1.5 : 1
                    )
            )
        }
    }

    /// 工地名 section:label + "从地址自动生成" hint chip + input + footer。
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "tag")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                Text(String(localized: "工地名", locale: locale))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                Spacer()
                if !userEditedName && !siteName.isEmpty {
                    Text(String(localized: "从地址自动生成", locale: locale))
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                }
            }
            .padding(.horizontal, 4)

            TextField(
                String(localized: "自动从地址生成", locale: locale),
                text: $siteName
            )
            .focused($focusedField, equals: .name)
            .font(.system(size: 15))
            .tint(Ink.fg)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .onChange(of: siteName) { _, newValue in
                let derived = Self.extractSiteName(from: address)
                if newValue != derived {
                    userEditedName = true
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Ink.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        focusedField == .name ? Ink.fg : Ink.line,
                        lineWidth: focusedField == .name ? 1.5 : 1
                    )
            )

            Text(String(
                localized: "后续录音、打标签都用这个名字 · 可随时改",
                locale: locale
            ))
            .font(.system(size: 11))
            .foregroundStyle(Ink.fgDim)
            .padding(.horizontal, 4)
        }
    }

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text")
                .font(.system(size: 13))
                .foregroundStyle(Ink.fgDim)
                .padding(.top, 1)
            Text(String(
                localized: "地址会一起存到工地预设,导出 Inspection PDF 时 Header 自动填项目地址,不用再录一遍。",
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
        let name = trimmedName
        let addr = trimmedAddress
        guard !name.isEmpty, !addr.isEmpty else { return }

        // 1) 加入工地标签列表(去重)
        SiteTagsStorage.add(name)
        // 2) 写一条 preset,把地址挂上。同 siteTag 已存在则自动更新(保留其它字段)。
        if let existing = SitePresetStorage.find(siteTag: name) {
            var updated = existing
            updated.address = addr
            SitePresetStorage.add(updated)
        } else {
            SitePresetStorage.add(SitePreset(siteTag: name, address: addr))
        }

        onSaved(name, addr)
        dismiss()
    }

    // MARK: - 工地名派生算法
    //
    // 目标:从澳洲式地址 "38 FORSYTH ST NORTH WILLOUGHBY" / "38 Forsyth St, North Willoughby NSW 2068"
    // 提取一个 6-25 字符的、人能记住的工地短名。
    //
    // 策略:
    //  1. 取逗号分隔的前两段(街道行 + suburb)。
    //  2. 街道行:去掉首部门牌号/单元号,取首个非数字 token 作为"街名"。
    //  3. suburb 行:去掉 state(NSW/VIC/QLD/...)/postcode,保留前 2 个 token。
    //  4. 拼成 "Forsyth - North Willoughby"(title-cased)。
    //  5. 拼不出来就 fallback 到地址前 24 字符 title-case。
    //
    static func extractSiteName(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // 把逗号 / 多空格 / 换行都规整成"段"
        // 优先按逗号分段;没逗号就当作一整段。
        let parts: [String] = trimmed
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let streetLine = parts.first ?? trimmed
        let suburbLine = parts.count >= 2 ? parts[1] : ""

        let streetWord = streetName(from: streetLine)
        let suburbWord = suburbName(from: suburbLine.isEmpty ? streetLine : suburbLine,
                                    skipStreetTokens: !suburbLine.isEmpty)

        let pieces = [streetWord, suburbWord].filter { !$0.isEmpty }
        let combined = pieces.joined(separator: " - ")

        if !combined.isEmpty {
            return combined
        }

        // Fallback:取前 24 字符,title case
        let head = String(trimmed.prefix(24))
        return titleCase(head)
    }

    /// 从街道行提取"街名"(去掉门牌号、Unit 号)。
    private static func streetName(from line: String) -> String {
        let tokens = line
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }

        // 跳过门牌号 token(纯数字 / 数字+字母 / "Unit"/"Lot"/"Apt"+数字)
        var idx = 0
        let unitWords: Set<String> = ["UNIT", "LOT", "APT", "APARTMENT", "FLAT", "NO", "NO."]
        while idx < tokens.count {
            let t = tokens[idx].uppercased()
            if t.allSatisfy({ $0.isNumber }) { idx += 1; continue }
            if t.first?.isNumber == true { idx += 1; continue }  // "12A", "3/45"
            if unitWords.contains(t) { idx += 1; continue }
            if t.contains("/") { idx += 1; continue }
            break
        }
        guard idx < tokens.count else { return "" }

        // 取首个非"街道后缀"的 token 作为街名
        let suffixes: Set<String> = [
            "ST", "STREET", "RD", "ROAD", "AVE", "AVENUE", "DR", "DRIVE",
            "LN", "LANE", "CT", "COURT", "PL", "PLACE", "BLVD", "BOULEVARD",
            "HWY", "HIGHWAY", "PDE", "PARADE", "CRES", "CRESCENT", "WAY",
            "CL", "CLOSE", "TCE", "TERRACE", "CIR", "CIRCUIT"
        ]
        let raw = tokens[idx]
        // 如果第一个 token 就是后缀(罕见),退一步用整段
        if suffixes.contains(raw.uppercased()) {
            return titleCase(line)
        }
        return titleCase(raw)
    }

    /// 从 suburb 行提取 "Suburb Name"(去掉 state / postcode)。
    /// skipStreetTokens=false 时表示这段里既有街道也有 suburb(没逗号的情况),
    /// 此时尽量从尾部往前找连续的字母 token 当 suburb。
    private static func suburbName(from line: String, skipStreetTokens: Bool) -> String {
        let states: Set<String> = ["NSW", "VIC", "QLD", "WA", "SA", "TAS", "NT", "ACT"]
        let streetSuffixes: Set<String> = [
            "ST", "STREET", "RD", "ROAD", "AVE", "AVENUE", "DR", "DRIVE",
            "LN", "LANE", "CT", "COURT", "PL", "PLACE", "BLVD", "BOULEVARD",
            "HWY", "HIGHWAY", "PDE", "PARADE", "CRES", "CRESCENT", "WAY",
            "CL", "CLOSE", "TCE", "TERRACE", "CIR", "CIRCUIT"
        ]
        let tokens = line
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0) }
            .filter { !$0.isEmpty }

        // 过滤掉 state / postcode(纯 4 位数字)
        var filtered = tokens.filter { tok in
            let up = tok.uppercased()
            if states.contains(up) { return false }
            if tok.count == 4, tok.allSatisfy({ $0.isNumber }) { return false }
            if tok.allSatisfy({ $0.isNumber }) { return false }
            return true
        }

        if skipStreetTokens {
            // suburb 段里偶尔也会带街道残片,理论上不会;保险起见原样用
        } else {
            // 没逗号:从尾部找"街道后缀"之后的 token 当 suburb
            if let lastSuffixIdx = filtered.lastIndex(where: { streetSuffixes.contains($0.uppercased()) }) {
                if lastSuffixIdx + 1 < filtered.count {
                    filtered = Array(filtered[(lastSuffixIdx + 1)...])
                } else {
                    return ""
                }
            } else {
                return ""
            }
        }

        // 取前 2 个 token(如 "NORTH WILLOUGHBY")
        let head = filtered.prefix(2).joined(separator: " ")
        return titleCase(head)
    }

    /// 简单 title case:首字母大写,其余小写,按空格分词。保持连字符。
    private static func titleCase(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace })
            .map { token -> String in
                let t = String(token).lowercased()
                guard let first = t.first else { return "" }
                return String(first).uppercased() + t.dropFirst()
            }
            .joined(separator: " ")
    }
}
