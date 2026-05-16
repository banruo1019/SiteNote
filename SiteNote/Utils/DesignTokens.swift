//
//  DesignTokens.swift
//  SiteNote
//
//  "极简白 · Linear" (方向 M1) 设计系统令牌。
//  白底 + 纯黑字 + 细线分隔,色彩纪律:90% 画面黑/白/灰,红只用于逾期/REC,
//  蓝(M1 accent)只做 ≤12px 的小圆点点缀。始终浅色,无 dark mode。
//
//  ⚠️ `Ink` 命名保留是为了兼容上一轮"工业仪表"方向留下的大量调用点,
//  但其值已完全重定义到 M1 的浅色调。命名只是历史包袱,不是设计立场。
//

import SwiftUI

// MARK: - Color(hex:) 便捷构造

extension Color {
    /// 从 0xRRGGBB 十六进制构造 Color。
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - M1 极简白调色板

/// M1 "Linear" 调色板。Ink 命名保留作向后兼容,值全部重定义到浅色语义。
enum Ink {
    /// 主背景 — 纯白。
    static let bg = Color(hex: 0xFFFFFF)
    /// 次级背景 — 搜索框、分组底。
    static let card = Color(hex: 0xFAFAF9)
    /// 第三级背景。
    static let card2 = Color(hex: 0xF4F4F2)
    /// 主分隔线(1px)。
    static let line = Color(hex: 0xEAEAE7)
    /// 稍重分隔线。
    static let line2 = Color(hex: 0xE0E0DC)
    /// 禁用 / 极弱描边 / 计数。
    static let dim = Color(hex: 0xB8B8BC)
    /// 主文字 / 激活态。
    static let fg = Color(hex: 0x111113)
    /// 次级文字。
    static let fg2 = Color(hex: 0x3A3A3E)
    /// 辅助文字、非激活图标。
    static let fgDim = Color(hex: 0x8B8B90)

    /// Hazard / Overdue / REC 红。
    static let red = Color(hex: 0xD1453B)
    /// 琥珀色备用(M1 基本不用,保留为避免旧代码炸)。
    static let amber = Color(hex: 0xD1453B)
    /// 绿色备用(M1 基本不用)。
    static let green = Color(hex: 0x8B8B90)

    /// 主色 = 黑。M1 的"强"信号是纯黑,不是蓝。
    static let accent = Color(hex: 0x111113)
    /// 深色变种(保留以防代码引用)。
    static let accentDeep = Color(hex: 0x111113)

    /// **点睛蓝** — 只用在 ≤12px 的小点(mic 右上角等)。
    /// 严禁用作按钮或大面积填充。
    static let accentBlue = Color(hex: 0x1F6FEB)
}

// MARK: - 字体

extension Font {
    /// 等宽数字变体。M1 里用得不多,但偶尔倒计时需要 tabular-nums 节奏。
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - 旧 DesignTokens 兼容保留

enum DesignTokens {
    enum ButtonSize {
        static let minTap: CGFloat = 44
    }

    enum FontSize {
        static let body: CGFloat = 14
        static let large: CGFloat = 18
        static let display: CGFloat = 28
    }

    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }
}
