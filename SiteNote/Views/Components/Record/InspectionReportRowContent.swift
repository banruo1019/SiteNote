//
//  InspectionReportRowContent.swift
//  SiteNote
//
//  EngineerScheduleView 当日报告卡片里的单行视觉。
//  纯渲染:doc.text 蓝色图标 + reportNo(等宽数字)+ projectNo 副标 + chevron。
//
//  parent 负责包 NavigationLink → InspectionFormView。
//

import SwiftUI

struct InspectionReportRowContent: View {
    let report: InspectionReport
    let isLast: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Ink.accentBlue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.reportNo.isEmpty
                     ? String(localized: "(无编号)", locale: AppLanguageManager.currentLocale)
                     : report.reportNo)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                    .lineLimit(1)
                    .monospacedDigit()
                if !report.projectNo.isEmpty {
                    Text(report.projectNo)
                        .font(.system(size: 11))
                        .foregroundStyle(Ink.fgDim)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Ink.dim)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Ink.line).frame(height: 1)
            }
        }
    }
}
