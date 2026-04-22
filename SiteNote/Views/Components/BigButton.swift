//
//  BigButton.swift
//  SiteNote
//
//  手套友好的大圆按钮。所有"主要动作"按钮都应复用它，保证点击区域不小于 60pt。
//

import SwiftUI

/// 手套友好的圆形大按钮。
///
/// 点击区域宽高固定为 `DesignTokens.ButtonSize.minTap`（60pt），满足
/// "手套友好" 原则——戴手套在嘈杂工地也能准确点击。
///
/// 使用示例：
/// ```swift
/// BigButton(systemImage: "plus", accessibilityLabel: "新增速记") {
///     isShowingCapture = true
/// }
/// ```
struct BigButton: View {
    /// 按钮中心显示的 SF Symbol 名称（如 `"plus"`、`"mic.fill"`）。
    let systemImage: String

    /// VoiceOver 等无障碍技术朗读的按钮名称（中文）。
    let accessibilityLabel: String

    /// 点击按钮的回调。
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: DesignTokens.FontSize.large, weight: .bold))
                .foregroundStyle(.white)
                .frame(
                    width: DesignTokens.ButtonSize.minTap,
                    height: DesignTokens.ButtonSize.minTap
                )
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

#Preview {
    BigButton(systemImage: "plus", accessibilityLabel: "新增速记") {}
        .padding()
}
