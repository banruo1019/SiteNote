//
//  MockDataSeeder.swift
//  SiteNote
//
//  仅供 App Store 截图用 — launch arg `-ScreenshotMode YES` 触发时,
//  在 SwiftData 容器里塞一份"看起来真实"的悉尼工地数据 + 占位照片。
//  非 release build 也只在 launch arg 存在时跑,正常用户绝对碰不到。
//
//  生成的内容:
//  - 1 个 site "Sydney CBD Tower"
//  - 6 条 Note(含 1 隐患、2 张照片、1 已逾期、1 已完成、3 待办)
//  - 2-3 张 Core Graphics 画的工地占位照片
//  - profile = siteTeam(默认 — 主屏看起来内容最丰富)
//  - onboarding dismissed flag = true(不弹 5 步引导)
//
//  Photo: 用渐变色 + SF Symbol 拼出"看起来像照片"的占位 — 不是真实照片,
//  但缩略图大小下读起来是"工地图"。
//

import Foundation
import SwiftData
import UIKit

@MainActor
enum MockDataSeeder {

    /// 是否启用截图模式 — launch arg `-ScreenshotMode YES`。
    static var isActive: Bool {
        UserDefaults.standard.string(forKey: "ScreenshotMode") == "YES"
            || CommandLine.arguments.contains("-ScreenshotMode")
            || ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "1"
    }

    /// 截图模式下要渲染哪个特殊屏幕 — `-StartScreen recording|floorplan|<default>`。
    /// default = 走 MainTabView,根据 -StartTab 显示 Log/Calendar/Reports。
    static var startScreen: String {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-StartScreen"), i + 1 < args.count {
            return args[i + 1]
        }
        return UserDefaults.standard.string(forKey: "StartScreen") ?? ""
    }

    /// 截图模式下 seed 哪种语言的 mock content — `-SeedLang zh|en`。
    /// default = en。zh 时塞中文笔记 + stub 显示中文文案。
    static var seedLanguage: String {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-SeedLang"), i + 1 < args.count {
            return args[i + 1]
        }
        return UserDefaults.standard.string(forKey: "SeedLang") ?? "en"
    }

    static var isChineseLocale: Bool {
        return seedLanguage == "zh"
    }

    /// 入口 — 在 ModelContainer 创建成功后调用。
    /// 把已有 Note / SitePreset 清掉,塞一组演示数据。
    static func seedIfNeeded(_ container: ModelContainer) {
        guard isActive else { return }
        print("[MockDataSeeder] active — seeding mock content for screenshots")

        // 跳过 onboarding
        UserDefaults.standard.set(true, forKey: "settings.onboarding.dismissed.v1")
        // 默认角色 siteTeam(可被 -ProfileMode 覆盖)
        let role = CommandLine.arguments.contains("-ProfileMode") ? "engineer" : "siteTeam"
        UserDefaults.standard.set(role, forKey: "settings.userProfile.role")

        // 用户名 + 公司名 — 看语言切换
        let isZh = isChineseLocale
        UserDefaults.standard.set(isZh ? "陈山" : "Sam Chen", forKey: "settings.userProfile.displayName")
        UserDefaults.standard.set(isZh ? "亚美建筑" : "Acme Construction", forKey: "settings.engineerCompanyName")
        UserDefaults.standard.set("12 345 678 901", forKey: "settings.engineerABN")

        // 锁定 app 内语言切换器到中文,让 SwiftUI catalog 渲染中文 UI
        if isZh {
            UserDefaults.standard.set("zh-Hans", forKey: "settings.appLanguage")
            UserDefaults.standard.set(["zh-Hans"], forKey: "AppleLanguages")
        }

        // 截图模式 — 假装有缓存的位置数据,避免 AppHeaderProvider 调 location 触发 dialog。
        UserDefaults.standard.set(-33.8688, forKey: "lastLocation.latitude")
        UserDefaults.standard.set(151.2093, forKey: "lastLocation.longitude")
        UserDefaults.standard.set("Sydney, NSW", forKey: "lastLocation.address")
        // 把 ScreenshotMode 持久化进 UserDefaults,让 isActive 在所有路径都返回 true。
        UserDefaults.standard.set("YES", forKey: "ScreenshotMode")

        let ctx = container.mainContext

        // 清掉旧数据
        wipeExisting(ctx: ctx)

        // 生成 + 保存占位照片
        let photoPaths = makePlaceholderPhotos()

        // Seed notes
        seedNotes(ctx: ctx, photoPaths: photoPaths, role: role)

        // Seed sites (SitePreset via SwiftData @Model)
        seedSites(ctx: ctx)

        // Seed fake archived PDFs so Reports tab shows recent reports
        seedMockArchives()

        do {
            try ctx.save()
            print("[MockDataSeeder] seed complete")
        } catch {
            print("[MockDataSeeder] save failed: \(error)")
        }
    }

    // MARK: - Wipe

    private static func wipeExisting(ctx: ModelContext) {
        // Notes
        if let notes = try? ctx.fetch(FetchDescriptor<Note>()) {
            for n in notes { ctx.delete(n) }
        }
        // InspectionDraft
        if let drafts = try? ctx.fetch(FetchDescriptor<InspectionReport>()) {
            for d in drafts { ctx.delete(d) }
        }
        // SitePreset
        if let sites = try? ctx.fetch(FetchDescriptor<SitePreset>()) {
            for s in sites { ctx.delete(s) }
        }
    }

    // MARK: - Notes

    private static func seedNotes(ctx: ModelContext, photoPaths: [String], role: String) {
        let cal = Calendar.current
        let now = Date()
        let today9am = cal.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        let yesterday = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let yesterday11 = cal.date(bySettingHour: 11, minute: 0, second: 0, of: yesterday) ?? yesterday
        let twoDaysAgo = cal.date(byAdding: .day, value: -2, to: now) ?? now
        let twoDaysAgo3pm = cal.date(bySettingHour: 15, minute: 0, second: 0, of: twoDaysAgo) ?? twoDaysAgo

        let isZh = isChineseLocale
        let siteTag = isZh ? "悉尼 CBD 塔楼" : "Sydney CBD Tower"

        let entries: [(String, Deadline, Date, Bool, [String], [String], String?)] = isZh ? [
            (
                "三层东侧楼梯口钢筋外露,11 点前用警示带围起来并通知工长。",
                .today, today9am.addingTimeInterval(60 * 60 * 0), true,
                Array(photoPaths.prefix(2)), ["安全"], "小李"
            ),
            (
                "北立面窗顶切口要对照图纸 A-201 rev C 复核,周五前班组划线。",
                .thisWeek, today9am.addingTimeInterval(60 * 60 * 1), false,
                [], ["质检"], nil
            ),
            (
                "5 层楼梯扶手缺安全栏,班组当天处理完成。",
                .today, today9am.addingTimeInterval(60 * 60 * 2), false,
                [photoPaths.count > 2 ? photoPaths[2] : photoPaths[0]], ["缺陷"], "老张"
            ),
            (
                "4 层楼板浇筑顺序 — 周一 7 点前跟总包确认泵车位置。",
                .threeDays, today9am.addingTimeInterval(60 * 60 * 3), false,
                [], ["工序"], nil
            ),
            (
                "2 层机房贯穿处泡沫需要修整平齐,上次清单漏了。",
                .threeDays, yesterday11, false,
                [], ["返工"], "小李"
            ),
            (
                "大堂地插布局已与电工复核确认。",
                .today, twoDaysAgo3pm, false,
                [], ["大堂"], nil
            )
        ] : [
            // (transcription, deadline, createdAt, isHazard, photoPaths, otherTags, assignedTo)
            (
                "Exposed reinforcement on level 3 east stair landing. Tape off the area and notify the foreman before 11 am.",
                .today, today9am.addingTimeInterval(60 * 60 * 0), true,
                Array(photoPaths.prefix(2)), ["safety"], "Jamie"
            ),
            (
                "Confirm rebate detail at window heads on north elevation matches drawing A-201 rev C. Trade to mark out by Friday.",
                .thisWeek, today9am.addingTimeInterval(60 * 60 * 1), false,
                [], ["QA"], nil
            ),
            (
                "Stair handrail missing on landing 5. Trade to fix end of day.",
                .today, today9am.addingTimeInterval(60 * 60 * 2), false,
                [photoPaths.count > 2 ? photoPaths[2] : photoPaths[0]], ["defect"], "Sam"
            ),
            (
                "Pour sequence for level 4 slab — confirm pump location with builder before 7 am Monday.",
                .threeDays, today9am.addingTimeInterval(60 * 60 * 3), false,
                [], ["sequence"], nil
            ),
            (
                "Foam at penetration in level 2 mech room needs trimming flush. Trade missed on prev punch list.",
                .threeDays, yesterday11, false,
                [], ["punch"], "Jamie"
            ),
            (
                "Floor box layout in lobby reviewed and approved with electrician.",
                .today, twoDaysAgo3pm, false,
                [], ["lobby"], nil
            )
        ]

        for (i, e) in entries.enumerated() {
            let (text, deadline, created, isHazard, photos, tags, assigned) = e
            let due = deadline.dueDate(from: created)
            let n = Note(
                transcription: text,
                createdAt: created,
                deadline: deadline,
                dueDate: due,
                isDone: i == entries.count - 1, // 最后一条已完成
                photoPaths: photos,
                siteTag: siteTag,
                assignedTo: assigned,
                isHazard: isHazard
            )
            n.otherTags = tags
            n.createdByRoleRaw = role
            ctx.insert(n)
        }
    }

    // MARK: - Sites

    // MARK: - Mock floor plan image (for ScreenshotFloorPlanStub)

    /// 渲染一张"看起来像建筑平面图"的占位图 — Core Graphics 画的房间 + 墙 + 标注。
    static func makeMockFloorPlan() -> UIImage {
        let size = CGSize(width: 1600, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let cg = ctx.cgContext

            // 浅米色底
            UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // 网格线(淡灰)
            cg.setStrokeColor(UIColor(white: 0.85, alpha: 1).cgColor)
            cg.setLineWidth(0.5)
            for x in stride(from: 0, to: size.width, by: 50) {
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, to: size.height, by: 50) {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
            }
            cg.strokePath()

            // 外墙 + 内墙 — 黑粗线
            cg.setStrokeColor(UIColor(white: 0.2, alpha: 1).cgColor)
            cg.setLineWidth(8)
            // 外墙
            let outer = CGRect(x: 100, y: 100, width: 1400, height: 1000)
            cg.stroke(outer)
            cg.setLineWidth(5)
            // 内部分隔墙(L 形 + 几个房间)
            // 横墙(中间偏上)
            cg.move(to: CGPoint(x: 100, y: 500))
            cg.addLine(to: CGPoint(x: 900, y: 500))
            cg.strokePath()
            // 竖墙
            cg.move(to: CGPoint(x: 600, y: 100))
            cg.addLine(to: CGPoint(x: 600, y: 500))
            cg.strokePath()
            // 右下房间分隔
            cg.move(to: CGPoint(x: 900, y: 500))
            cg.addLine(to: CGPoint(x: 900, y: 1100))
            cg.strokePath()
            // 楼梯井(右上)
            cg.stroke(CGRect(x: 1100, y: 150, width: 350, height: 300))
            // 楼梯踏步
            cg.setLineWidth(1.5)
            for i in 1..<10 {
                let y = 150 + CGFloat(i) * 30
                cg.move(to: CGPoint(x: 1100, y: y))
                cg.addLine(to: CGPoint(x: 1450, y: y))
            }
            cg.strokePath()

            // 门口缺口(在墙上画一个小白条)
            UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1).setFill()
            cg.fill(CGRect(x: 350, y: 497, width: 60, height: 8))   // 横墙上的门
            cg.fill(CGRect(x: 597, y: 300, width: 8, height: 60))   // 竖墙上的门
            cg.fill(CGRect(x: 897, y: 700, width: 8, height: 60))   // 右下墙上的门

            // 房间标签
            let labelFont = UIFont.systemFont(ofSize: 22, weight: .medium)
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: UIColor(white: 0.35, alpha: 1)
            ]
            ("OFFICE 01" as NSString).draw(at: CGPoint(x: 250, y: 270), withAttributes: labelAttrs)
            ("OFFICE 02" as NSString).draw(at: CGPoint(x: 720, y: 270), withAttributes: labelAttrs)
            ("CORRIDOR" as NSString).draw(at: CGPoint(x: 400, y: 760), withAttributes: labelAttrs)
            ("PLANT ROOM" as NSString).draw(at: CGPoint(x: 1050, y: 760), withAttributes: labelAttrs)
            ("STAIR" as NSString).draw(at: CGPoint(x: 1230, y: 280), withAttributes: labelAttrs)

            // 尺寸标注(顶部)
            let dimFont = UIFont.systemFont(ofSize: 16, weight: .regular)
            let dimAttrs: [NSAttributedString.Key: Any] = [
                .font: dimFont,
                .foregroundColor: UIColor(white: 0.5, alpha: 1)
            ]
            // 顶部尺寸线
            cg.setStrokeColor(UIColor(white: 0.5, alpha: 1).cgColor)
            cg.setLineWidth(1)
            cg.move(to: CGPoint(x: 100, y: 60))
            cg.addLine(to: CGPoint(x: 1500, y: 60))
            cg.strokePath()
            // 标注两端的小竖线
            cg.move(to: CGPoint(x: 100, y: 50)); cg.addLine(to: CGPoint(x: 100, y: 70))
            cg.move(to: CGPoint(x: 1500, y: 50)); cg.addLine(to: CGPoint(x: 1500, y: 70))
            cg.strokePath()
            ("14.0 m" as NSString).draw(at: CGPoint(x: 770, y: 30), withAttributes: dimAttrs)

            // 左侧尺寸
            cg.move(to: CGPoint(x: 60, y: 100)); cg.addLine(to: CGPoint(x: 60, y: 1100))
            cg.strokePath()
            ("10.0 m" as NSString).draw(at: CGPoint(x: 20, y: 580), withAttributes: dimAttrs)

            // 标题块右下
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
                .foregroundColor: UIColor(white: 0.2, alpha: 1)
            ]
            let titleBlock = CGRect(x: 1000, y: 1130, width: 480, height: 60)
            cg.setStrokeColor(UIColor(white: 0.2, alpha: 1).cgColor)
            cg.setLineWidth(1)
            cg.stroke(titleBlock)
            ("LEVEL 1 — EAST WING" as NSString).draw(
                at: CGPoint(x: 1018, y: 1145),
                withAttributes: titleAttrs
            )
            ("Scale 1:100 · Sydney CBD Tower" as NSString).draw(
                at: CGPoint(x: 1018, y: 1168),
                withAttributes: dimAttrs
            )
        }
    }

    // MARK: - Mock PDF archives (for Reports tab screenshot)

    /// 写几个空 PDF 到 Reports 文件夹,让 Reports tab "RECENT" 段有数据看。
    /// 文件名格式对齐 ReportArchiveService 的输出 — 它扫这个目录列出文件。
    private static func seedMockArchives() {
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return }
        let reportsDir = support.appendingPathComponent("Reports", isDirectory: true)
        let siteDir = reportsDir.appendingPathComponent("Sydney CBD Tower", isDirectory: true)
        try? fm.createDirectory(at: siteDir, withIntermediateDirectories: true)

        let cal = Calendar.current
        let now = Date()
        let mockReports: [(name: String, daysAgo: Int)] = [
            ("Sydney-CBD-Tower-Diary-\(yyyymmdd(now)).pdf", 0),
            ("Sydney-CBD-Tower-Diary-\(yyyymmdd(cal.date(byAdding: .day, value: -1, to: now)!)).pdf", 1),
            ("Sydney-CBD-Tower-Diary-\(yyyymmdd(cal.date(byAdding: .day, value: -2, to: now)!)).pdf", 2),
            ("Sydney-CBD-Tower-Diary-\(yyyymmdd(cal.date(byAdding: .day, value: -4, to: now)!)).pdf", 4)
        ]
        let placeholderPDF = makePlaceholderPDFData()
        for (name, daysAgo) in mockReports {
            let url = siteDir.appendingPathComponent(name)
            try? placeholderPDF.write(to: url)
            // 设置文件创建时间以匹配预期日期
            if let created = cal.date(byAdding: .day, value: -daysAgo, to: now) {
                try? fm.setAttributes([.creationDate: created], ofItemAtPath: url.path)
            }
        }
    }

    private static func yyyymmdd(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// Minimal 1-page PDF — 用 UIGraphicsPDFRenderer 画一张 A4 白纸 + "Sample PDF" 字样。
    private static func makePlaceholderPDFData() -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            ctx.beginPage()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .bold),
                .foregroundColor: UIColor.darkGray
            ]
            let title = "Daily Site Diary" as NSString
            let titleSize = title.size(withAttributes: attrs)
            title.draw(
                at: CGPoint(x: (pageRect.width - titleSize.width) / 2, y: 100),
                withAttributes: attrs
            )
        }
    }

    private static func seedSites(ctx: ModelContext) {
        let isZh = isChineseLocale
        let s1 = SitePreset()
        s1.siteTag = isZh ? "悉尼 CBD 塔楼" : "Sydney CBD Tower"
        s1.projectName = isZh ? "悉尼 CBD 塔楼 · 第二期" : "Sydney CBD Tower - Stage 2"
        s1.projectNo = "25159"
        s1.clientName = isZh ? "亚美建筑" : "Acme Construction"
        s1.defaultAttn = isZh ? "陈山" : "Sam Chen"
        s1.address = isZh ? "悉尼 NSW 2000 样品街 123 号" : "123 Sample St, Sydney NSW 2000"
        ctx.insert(s1)

        let s2 = SitePreset()
        s2.siteTag = isZh ? "邦迪综合体" : "Bondi Mixed-Use"
        s2.projectName = isZh ? "邦迪综合体开发项目" : "Bondi Mixed-Use Development"
        s2.projectNo = "26041"
        s2.clientName = isZh ? "海岸建造" : "Coastal Builders"
        s2.defaultAttn = isZh ? "朴大" : "Alex Park"
        s2.address = isZh ? "邦迪 NSW 2026 样品大道 55 号" : "55 Sample Ave, Bondi NSW 2026"
        ctx.insert(s2)
    }

    // MARK: - Placeholder photos

    /// 用 Core Graphics 画 3 张"看起来像工地照片"的 PNG,保存到 PhotoStorage,
    /// 返回相对路径数组。失败返回空。
    private static func makePlaceholderPhotos() -> [String] {
        var images: [UIImage] = []
        // 三种风格 — 不同主色 + 不同 SF Symbol
        let configs: [(top: UIColor, bottom: UIColor, symbol: String, label: String)] = [
            (UIColor(red: 0.46, green: 0.52, blue: 0.58, alpha: 1),
             UIColor(red: 0.20, green: 0.24, blue: 0.28, alpha: 1),
             "building.2.fill", "Site overview"),
            (UIColor(red: 0.85, green: 0.65, blue: 0.30, alpha: 1),
             UIColor(red: 0.50, green: 0.35, blue: 0.15, alpha: 1),
             "exclamationmark.triangle.fill", "Hazard"),
            (UIColor(red: 0.40, green: 0.48, blue: 0.55, alpha: 1),
             UIColor(red: 0.20, green: 0.28, blue: 0.34, alpha: 1),
             "wrench.and.screwdriver.fill", "Detail")
        ]

        for cfg in configs {
            if let img = renderPlaceholderPhoto(
                topColor: cfg.top,
                bottomColor: cfg.bottom,
                symbolName: cfg.symbol,
                label: cfg.label
            ) {
                images.append(img)
            }
        }

        return PhotoStorage.save(images)
    }

    private static func renderPlaceholderPhoto(
        topColor: UIColor,
        bottomColor: UIColor,
        symbolName: String,
        label: String
    ) -> UIImage? {
        let size = CGSize(width: 1024, height: 768)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            // 渐变
            let colors = [topColor.cgColor, bottomColor.cgColor] as CFArray
            let space = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else { return }
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )

            // 微弱噪点 — 让纯渐变看起来不像纯色
            cg.setAlpha(0.05)
            cg.setFillColor(UIColor.white.cgColor)
            for _ in 0..<2000 {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: 2, height: 2))
            }
            cg.setAlpha(1)

            // 几何感构图线 — 像建筑结构
            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            cg.setLineWidth(2)
            for i in 0..<6 {
                let y = CGFloat(i) * size.height / 6
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
                cg.strokePath()
            }
            for i in 0..<8 {
                let x = CGFloat(i) * size.width / 8
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x, y: size.height))
                cg.strokePath()
            }

            // SF Symbol 居中,白色半透明
            let config = UIImage.SymbolConfiguration(pointSize: 180, weight: .light)
            if let symbolImg = UIImage(systemName: symbolName, withConfiguration: config)?
                .withTintColor(UIColor.white.withAlphaComponent(0.75), renderingMode: .alwaysOriginal) {
                let rect = CGRect(
                    x: (size.width - symbolImg.size.width) / 2,
                    y: (size.height - symbolImg.size.height) / 2 - 30,
                    width: symbolImg.size.width,
                    height: symbolImg.size.height
                )
                symbolImg.draw(in: rect)
            }

            // 文字标签
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85)
            ]
            let str = label as NSString
            let strSize = str.size(withAttributes: attrs)
            str.draw(
                at: CGPoint(
                    x: (size.width - strSize.width) / 2,
                    y: size.height / 2 + 100
                ),
                withAttributes: attrs
            )
        }
        return img
    }
}
