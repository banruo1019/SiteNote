//
//  Fonts.swift
//  SiteNote
//
//  Inter 变量字体的便捷接入。Inter 没加进 Xcode 工程时自动回退系统字。
//
//  ## 接入 Inter 字体(一次性)
//
//  1. 下载 Inter 的可变字体文件 `InterVariable.ttf` 和 `InterVariable-Italic.ttf`
//     (https://rsms.me/inter/ 或 Google Fonts)
//  2. 拖进 Xcode 工程的 `SiteNote/` 目录,勾选 target
//  3. 打开 `Info.plist`(或在 target 的 Info 里)加:
//     ```xml
//     <key>UIAppFonts</key>
//     <array>
//         <string>InterVariable.ttf</string>
//         <string>InterVariable-Italic.ttf</string>
//     </array>
//     ```
//  4. 启动 App,`Font.inter(_:weight:)` 会自动命中。没做上面的步骤也不会崩,只会回退。
//
//  Inter 支持变量 axis `wght`(100–900),SwiftUI 在 iOS 17+ 可以直接通过 `.weight()` 调。
//

import SwiftUI
import UIKit

extension Font {
    /// 主字体。优先 Inter,没装上时回退系统字。
    /// 和 `Font.system(size:weight:)` 完全等效签名。
    static func inter(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if interAvailable {
            return .custom("Inter", size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    /// 检查 Inter 是否安装在当前 bundle(lazy 检测,只跑一次)。
    static let interAvailable: Bool = {
        // UIFont 会返回一个合成的 fallback,但 `fontNamesForFamilyName` 只有真装了才返回非空。
        !UIFont.fontNames(forFamilyName: "Inter").isEmpty
    }()
}
