//
//  CompanyInfoSettingsView.swift
//  SiteNote
//
//  设置 → "我和公司" 子页。
//  把公司名 / ABN / Logo 上传管理从 settings 主页搬过来,主页就一行入口。
//

import SwiftUI
import PhotosUI
import UIKit

struct CompanyInfoSettingsView: View {
    @AppStorage("settings.engineerCompanyName") private var companyName: String = ""
    @AppStorage("settings.engineerABN") private var abn: String = ""

    @State private var logoPickerItem: PhotosPickerItem?
    @State private var currentLogo: UIImage? = BrandingStorage.loadLogo()

    private var locale: Locale { AppLanguageManager.currentLocale }

    var body: some View {
        Form {
            // 公司基本信息
            Section {
                HStack {
                    Text(String(localized: "公司名", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                        .frame(width: 80, alignment: .leading)
                    TextField(
                        String(localized: "如 ABC Engineering Pty Ltd", locale: locale),
                        text: $companyName
                    )
                    .font(.system(size: DesignTokens.FontSize.body))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                }

                HStack {
                    Text(String(localized: "ABN", locale: locale))
                        .font(.system(size: DesignTokens.FontSize.body))
                        .frame(width: 80, alignment: .leading)
                    TextField(
                        String(localized: "11 位 ABN(可留空)", locale: locale),
                        text: $abn
                    )
                    .font(.system(size: DesignTokens.FontSize.body))
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                }
            } header: {
                SectionHeader(String(localized: "公司信息", locale: locale))
            } footer: {
                SectionFooter(String(localized: "出现在 PDF 报告封面。", locale: locale))
            }

            // 公司 Logo
            Section {
                HStack {
                    if let logo = currentLogo {
                        Image(uiImage: logo)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 50, height: 50)
                            .background(Ink.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 24))
                            .foregroundStyle(Ink.fgDim)
                            .frame(width: 50, height: 50)
                            .background(Ink.bg)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "公司 Logo", locale: locale))
                            .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                        Text(currentLogo != nil
                            ? String(localized: "已上传", locale: locale)
                            : String(localized: "未上传", locale: locale)
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                PhotosPicker(selection: $logoPickerItem, matching: .images) {
                    Label(
                        String(localized: "上传 / 替换 Logo", locale: locale),
                        systemImage: "photo.badge.plus"
                    )
                    .font(.system(size: DesignTokens.FontSize.body))
                }

                if currentLogo != nil {
                    Button(role: .destructive) {
                        BrandingStorage.clearLogo()
                        currentLogo = nil
                    } label: {
                        Label(
                            String(localized: "移除 Logo", locale: locale),
                            systemImage: "trash"
                        )
                        .font(.system(size: DesignTokens.FontSize.body))
                    }
                }
            } header: {
                SectionHeader(String(localized: "Logo", locale: locale))
            } footer: {
                SectionFooter(String(localized: "PDF 报告封面左上角显示。建议透明背景 PNG。", locale: locale))
            }
        }
        .industrialForm()
        .navigationTitle(String(localized: "我和公司", locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: logoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   BrandingStorage.saveLogo(img) {
                    await MainActor.run {
                        currentLogo = BrandingStorage.loadLogo()
                    }
                }
                await MainActor.run {
                    logoPickerItem = nil
                }
            }
        }
        .onAppear {
            currentLogo = BrandingStorage.loadLogo()
        }
    }
}
