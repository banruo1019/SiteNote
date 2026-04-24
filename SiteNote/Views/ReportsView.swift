//
//  ReportsView.swift
//  SiteNote
//
//  M1 "Linear 极简白"报告页:
//  - 大标题 "报告" (28pt 600)
//  - 本周 sparkline + 本月汇总 + 本月细分
//  - P0-4 合并后的 3 入口:出 PDF / AI 发现 / 平面图查看
//    · 数据备份已移到设置页
//

import SwiftUI
import SwiftData

struct ReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Note> { $0.deletedAt == nil },
        sort: \Note.createdAt
    ) private var allNotes: [Note]

    @Query(
        filter: #Predicate<LogEntry> { $0.deletedAt == nil },
        sort: [SortDescriptor(\LogEntry.startAt)]
    ) private var allEntries: [LogEntry]

    var body: some View {
        NavigationStack {
            ZStack {
                Ink.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    AIStatusBar()
                    titleRow
                    ScrollView {
                        VStack(spacing: 0) {
                            weeklyArea
                            monthSummaryArea
                            monthBreakdownArea
                            outputList
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(for: ReportDestination.self) { dest in
                destinationView(for: dest)
            }
            .navigationDestination(for: SettingsDestination.self) { _ in
                SettingsView()
            }
            .navigationDestination(for: AIStatusDestination.self) { _ in
                InputAISettingsView()
            }
            .navigationDestination(for: Note.self) { note in
                NoteRouter(note: note)
            }
        }
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("报告")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.8)
                .foregroundStyle(Ink.fg)
            Spacer()
            SearchBarButton()
            TodayBriefButton()
            NavigationLink(value: SettingsDestination()) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Ink.fgDim)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Weekly sparkline

    private var weeklyArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本周")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Ink.fgDim)
                    Text("\(weekNotesCount)")
                        .font(.system(size: 36, weight: .medium))
                        .tracking(-1.2)
                        .foregroundStyle(Ink.fg)
                        .monospacedDigit()
                }
                Spacer()
                Text(weekRangeLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.fgDim)
            }

            // 本周有记录才画折线。全 0 的直线没信息量,改显示提示。
            if weekNotesCount > 0 {
                sparkline
                    .frame(height: 40)

                HStack {
                    ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { d in
                        Text(d)
                            .font(.system(size: 10))
                            .foregroundStyle(Ink.dim)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Text("本周还没有记录,去「记」tab 按住 mic 开始。")
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    private var sparkline: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let counts = weekDayCounts
            let maxCount = max(counts.max() ?? 1, 1)
            let points: [CGPoint] = counts.enumerated().map { (idx, c) in
                let x = w * CGFloat(idx) / 6
                let y = h - (h * CGFloat(c) / CGFloat(maxCount))
                return CGPoint(x: x, y: y)
            }

            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for p in points.dropFirst() {
                    path.addLine(to: p)
                }
            }
            .stroke(Ink.fg, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // 终点小蓝点 — M1 唯一的蓝
            if let last = points.last {
                Circle()
                    .fill(Ink.accentBlue)
                    .frame(width: 6, height: 6)
                    .position(last)
            }
        }
    }

    private var weekDayCounts: [Int] {
        let cal = Calendar.current
        let today = Date()
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        var counts = Array(repeating: 0, count: 7)
        for note in allNotes {
            if let days = cal.dateComponents([.day], from: startOfWeek, to: note.createdAt).day,
               days >= 0 && days < 7 {
                counts[days] += 1
            }
        }
        return counts
    }

    private var weekNotesCount: Int {
        weekDayCounts.reduce(0, +)
    }

    private var weekRangeLabel: String {
        let cal = Calendar.current
        let today = Date()
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else {
            return ""
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "d MMM"
        let endOfWeek = cal.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let weekNum = cal.component(.weekOfYear, from: today)
        return "W\(weekNum) · \(f.string(from: interval.start))–\(f.string(from: endOfWeek))"
    }

    // MARK: - 本月汇总(PM 视角看板)

    /// 本月日历区间 [start, end)。
    private var monthRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let end = cal.date(byAdding: .month, value: 1, to: start) ?? now
        return (start, end)
    }

    private var thisMonthEntries: [LogEntry] {
        allEntries.filter { $0.startAt >= monthRange.start && $0.startAt < monthRange.end }
    }

    private var thisMonthNotes: [Note] {
        allNotes.filter { $0.createdAt >= monthRange.start && $0.createdAt < monthRange.end }
    }

    /// 本月人员到场总人日(quantity 累计,nil 算 1)。
    private var monthHeadcount: Int {
        thisMonthEntries
            .filter { $0.kind == .person && !$0.isAbsent }
            .map { $0.quantity ?? 1 }
            .reduce(0, +)
    }

    /// 本月机械工时合计(已闭合 session 的小时数)。
    private var monthPlantHours: Double {
        thisMonthEntries
            .filter { $0.kind == .plant }
            .compactMap { $0.duration }
            .reduce(0, +) / 3600
    }

    /// 本月隐患条数。
    private var monthHazardCount: Int {
        thisMonthNotes.filter { $0.isHazard }.count
    }

    private var monthSummaryArea: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("本月汇总")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)

            HStack(spacing: 10) {
                summaryCell(value: "\(monthHeadcount)", label: "人日合计", color: Ink.fg)
                summaryCell(
                    value: monthPlantHours > 0 ? String(format: "%.0fh", monthPlantHours) : "—",
                    label: "机械工时",
                    color: Ink.fg
                )
                summaryCell(
                    value: "\(monthHazardCount)",
                    label: "隐患",
                    color: monthHazardCount > 0 ? Ink.red : Ink.fgDim
                )
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    /// 本月细分:工种 Top 5 / 机械 Top 5 / 隐患列表。
    /// 给 PM 看哪几个工种来得最多、哪几台机械工时最长、最近哪些 note 标了隐患。
    private var monthBreakdownArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 工种 Top 5(按人日)
            if !topPersonSubjects.isEmpty {
                breakdownSection(title: "工种 Top \(topPersonSubjects.count)", items: topPersonSubjects, suffix: "人日")
            }
            // 机械 Top 5(按工时)
            if !topPlantSubjects.isEmpty {
                breakdownSection(title: "机械 Top \(topPlantSubjects.count)", items: topPlantSubjects, suffix: "h")
            }
            // 隐患列表(最近 5 条)
            if !recentHazardNotes.isEmpty {
                hazardListSection
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    private func breakdownSection(title: String, items: [(name: String, value: Double)], suffix: String) -> some View {
        let maxV = items.map(\.value).max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
            ForEach(items, id: \.name) { item in
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.fg)
                        .frame(width: 70, alignment: .leading)
                        .lineLimit(1)
                    GeometryReader { geo in
                        let w = geo.size.width * CGFloat(item.value / maxV)
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Ink.line)
                            Rectangle().fill(Ink.fg).frame(width: max(2, w))
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .frame(height: 6)
                    Text(item.value == floor(item.value)
                         ? "\(Int(item.value))\(suffix)"
                         : String(format: "%.1f%@", item.value, suffix))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Ink.fgDim)
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
            }
        }
    }

    /// 本月人员到场 Top 5(按总人日)。
    private var topPersonSubjects: [(name: String, value: Double)] {
        let persons = thisMonthEntries.filter { $0.kind == .person && !$0.isAbsent }
        let grouped = Dictionary(grouping: persons, by: { $0.subject })
        return grouped
            .map { (name: $0.key, value: Double($0.value.map { $0.quantity ?? 1 }.reduce(0, +))) }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0 }
    }

    /// 本月机械工时 Top 5(按总小时数,只统计已闭合 session)。
    private var topPlantSubjects: [(name: String, value: Double)] {
        let plants = thisMonthEntries.filter { $0.kind == .plant }
        let grouped = Dictionary(grouping: plants, by: { $0.subject })
        return grouped
            .map { (name: $0.key, value: $0.value.compactMap { $0.duration }.reduce(0, +) / 3600) }
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0 }
    }

    private var recentHazardNotes: [Note] {
        thisMonthNotes
            .filter { $0.isHazard }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .map { $0 }
    }

    private var hazardListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.red)
                Text("本月隐患 \(recentHazardNotes.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Ink.red)
            }
            ForEach(recentHazardNotes) { note in
                NavigationLink(value: note) {
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Ink.red).frame(width: 5, height: 5).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.transcription.isEmpty ? "(仅录音/照片)" : note.transcription)
                                .font(.system(size: 13))
                                .foregroundStyle(Ink.fg)
                                .lineLimit(2)
                            HStack(spacing: 6) {
                                if let s = note.siteTag {
                                    Text(s).font(.system(size: 10)).foregroundStyle(Ink.fgDim)
                                }
                                Text(monthDayLabel(note.createdAt))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Ink.dim)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func monthDayLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M 月 d 日"
        return f.string(from: d)
    }

    private func summaryCell(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Ink.fgDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Output list(3 入口:出 PDF / AI 发现 / 平面图查看)

    private var outputList: some View {
        VStack(spacing: 0) {
            outputRow(icon: "doc.text", title: "出 PDF", sub: "巡检日志 · 本周报告 · EOT 索赔", dest: .pdfHub)
            outputRow(icon: "sparkles", title: "AI 发现", sub: "日记叙事 · 积压/静默/隐患洞察", dest: .aiHub)
            outputRow(icon: "map", title: "平面图查看", sub: "按工地和楼层看图钉分布", dest: .floorPlan)
            outputRow(icon: "minus.circle", title: "我们刻意不做", sub: "管理预期 · 想要的功能可能在这里", dest: .principles)
        }
    }

    private func outputRow(icon: String, title: String, sub: String, dest: ReportDestination) -> some View {
        NavigationLink(value: dest) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Ink.fg2)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .tracking(-0.2)
                        .foregroundStyle(Ink.fg)
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Ink.fgDim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Ink.dim)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Ink.line).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destinationView(for dest: ReportDestination) -> some View {
        switch dest {
        case .pdfHub: PDFHubView()
        case .aiHub: AIInsightsHubView()
        case .floorPlan: FloorPlanLookupView()
        case .principles: ProductPrinciplesView()
        }
    }
}

enum ReportDestination: Hashable {
    case pdfHub, aiHub, floorPlan, principles
}

// MARK: - 子菜单:出 PDF

/// P0-4 合并后:把 PDF 巡检日志 / 本周报告 / EOT 索赔 三个 PDF 导出集中在一个视图。
struct PDFHubView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    PDFExportView()
                } label: {
                    pdfRow(icon: "doc.text", title: "PDF 巡检日志", sub: "按日期或工地导出")
                }
                NavigationLink {
                    WeeklySummaryView()
                } label: {
                    pdfRow(icon: "chart.bar", title: "本周报告", sub: "可复制的周总结文本")
                }
                NavigationLink {
                    EOTReportView()
                } label: {
                    pdfRow(icon: "cloud.rain", title: "EOT 工期延误", sub: "基于天气的索赔 · AI")
                }
            }
        }
        .navigationTitle("出 PDF")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pdfRow(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Ink.fg2)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(sub).font(.system(size: 12)).foregroundStyle(Ink.fgDim)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 子菜单:AI 发现

/// P0-4 合并后:AI 日记叙事 + AI 洞察。
struct AIInsightsHubView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    DailyNarrativeView()
                } label: {
                    aiRow(icon: "text.alignleft", title: "AI 日记叙事", sub: "把一天的记录拼成可读日志")
                }
                NavigationLink {
                    InsightsView()
                } label: {
                    aiRow(icon: "sparkles", title: "AI 洞察", sub: "逾期 · 静默 · 隐患积压")
                }
            }
        }
        .navigationTitle("AI 发现")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func aiRow(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Ink.fg2)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                Text(sub).font(.system(size: 12)).foregroundStyle(Ink.fgDim)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Backup export (保留原样)

struct BackupExportView: View {
    @State private var shareURL: URL?
    @State private var errorMessage: String?
    @State private var isBuilding = false

    var body: some View {
        Form {
            Section {
                Text("生成一个包含所有录音 + 照片 + 平面图的 ZIP 文件,可通过分享面板存到 iCloud Drive / 邮件 / AirDrop。")
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.fgDim)
            }
            Section {
                Button {
                    exportZip()
                } label: {
                    HStack {
                        if isBuilding {
                            ProgressView()
                            Text("正在打包...")
                        } else {
                            Image(systemName: "externaldrive.fill.badge.timemachine")
                            Text("生成 ZIP 并分享")
                        }
                        Spacer()
                    }
                    .font(.system(size: 14, weight: .medium))
                }
                .disabled(isBuilding)
            }
        }
        .industrialForm()
        .navigationTitle("备份导出")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { shareURL.map { BackupShareURL(url: $0) } },
            set: { _ in shareURL = nil }
        )) { item in
            ShareSheet(items: [item.url])
        }
        .alert("出错了", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func exportZip() {
        isBuilding = true
        Task {
            do {
                let url = try BackupService.createBackupZip()
                shareURL = url
                isBuilding = false
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                isBuilding = false
            }
        }
    }
}

private struct BackupShareURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - 我们刻意不做(管理预期)

/// 把"用户可能想要但产品决策不做"的功能集中列出,避免反馈渠道反复收同一类请求。
/// 每条都有简短理由,这样老板/同事/家人也能理解为什么不做。
struct ProductPrinciplesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                ForEach(items) { item in
                    row(item)
                }
                footer
            }
        }
        .background(Ink.bg.ignoresSafeArea())
        .navigationTitle("我们刻意不做")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        Text("SiteNote 信「减法比加法重要」。下面是常被问到、但我们决定**不做**的功能,以及不做的原因。")
            .font(.system(size: 13))
            .foregroundStyle(Ink.fgDim)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
    }

    private func row(_ item: PrincipleItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Ink.red)
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.fg)
            }
            Text(item.reason)
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
                .padding(.leading, 21)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    private var footer: some View {
        Text("如果你想要的功能不在这里,欢迎反馈。我们也可能改主意 — 但默认前提是:**对工地一线最有价值的事先做完**。")
            .font(.system(size: 12))
            .foregroundStyle(Ink.fgDim)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
    }

    private struct PrincipleItem: Identifiable {
        let id = UUID()
        let title: String
        let reason: String
    }

    private let items: [PrincipleItem] = [
        PrincipleItem(
            title: "iCloud / 多设备同步",
            reason: "纯本地 = 0 网络依赖 = 工地信号死角也能用。同步的崩盘成本远高于收益。要换机,用「数据 → 备份 ZIP」导出。"
        ),
        PrincipleItem(
            title: "通知里的「快速完成」按钮",
            reason: "锁屏一键完成会让人误触,工地手套/雨水/汗水都是误触源。必须打开 App 看清楚再点完成。"
        ),
        PrincipleItem(
            title: "iPad 分栏 / Mac Catalyst",
            reason: "现场就是 iPhone。iPad/Mac 上的「管理视图」会拖慢真正用户的迭代节奏。"
        ),
        PrincipleItem(
            title: "自定义 App 图标 / 主题色",
            reason: "工地不需要个性化。统一红黑高对比 = 强光下也认得出。"
        ),
        PrincipleItem(
            title: "推送内容显示原文",
            reason: "锁屏对路人/同事/家人都是公开面。工地业务文本(造价/事故/纠纷)不该泄露。原文交给点开 App 看。"
        ),
        PrincipleItem(
            title: "复杂的标签层级 / 颜色 / 优先级",
            reason: "戴手套点不准小目标。一个工地 tag + 一个隐患 toggle 已覆盖 90% 场景,其余靠 AI 自动归类。"
        ),
        PrincipleItem(
            title: "实时多人协作 / 评论",
            reason: "需要后端 + 账号体系 + 权限模型 = 巨大复杂度。工地协作走微信/电话已经够用,SiteNote 只做「我」的速记。"
        ),
        PrincipleItem(
            title: "Apple Watch / CarPlay",
            reason: "戴 Watch 的工地 PM 太少;CarPlay 录音不如 iPhone 直接按。投入产出比低。"
        )
    ]
}

#Preview("ProductPrinciples") {
    NavigationStack { ProductPrinciplesView() }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Note.self, LogEntry.self, ShareLog.self, configurations: config)
    return ReportsView().modelContainer(container)
}
