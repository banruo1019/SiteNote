//
//  OnboardingView.swift
//  SiteNote
//
//  首次启动 5 步引导(v2 — 加了 profile 选择)。
//  - Step 0:欢迎 + 隐私
//  - Step 1:**选择角色**(PM / Engineer),Settings 后续可改
//  - Step 2:建第一个工地(可跳过)
//  - Step 3:介绍录音 + 保存后的 UndoToast 4 按钮
//  - Step 4:试录第一条(引导式,不内嵌录音 — 关闭引导后用户在 RecordView 真录)
//
//  完成后 UserDefaults 标记 dismissed,不再出现。
//  老用户已经 dismiss v1 的不会重新走(默认 PM,可在 Settings 里改 profile)。
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isShown: Bool

    @State private var step: Int = 0
    @State private var selectedProfile: ProfileKind = .siteTeam

    private static let dismissedKey = "settings.onboarding.dismissed.v1"
    private static let totalSteps = 5

    static var needsToShow: Bool {
        !UserDefaults.standard.bool(forKey: dismissedKey)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 12)

                // 步骤指示 + 后退按钮
                HStack(spacing: 10) {
                    // 后退按钮:step > 0 时显示。step == 0 留 32pt 占位,避免点指示器横向跳动。
                    if step > 0 {
                        Button {
                            goBackStep()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 32, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "上一步", locale: AppLanguageManager.currentLocale))
                    } else {
                        Color.clear.frame(width: 32, height: 28)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<Self.totalSteps, id: \.self) { i in
                            Capsule()
                                .fill(i == step ? Color.white : Color.white.opacity(0.25))
                                .frame(width: i == step ? 28 : 8, height: 4)
                        }
                    }
                    Color.clear.frame(width: 32, height: 28) // 平衡左侧后退按钮宽度
                }

                // 步骤内容
                ScrollView(showsIndicators: false) {
                    Group {
                        switch step {
                        case 0: welcomeStep
                        case 1: profileStep
                        case 2: firstSiteStep
                        case 3:
                            // step 3 按角色分支:PM 讲录音手势,Engineer 讲 session 工作流
                            if selectedProfile == .engineer {
                                engineerSessionStep
                            } else {
                                gestureStep
                            }
                        default:
                            // step 4 按角色分支:PM 试录速记,Engineer 试开一次巡检
                            if selectedProfile == .engineer {
                                engineerTryItStep
                            } else {
                                tryItStep
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)

                // Action 按钮
                VStack(spacing: 8) {
                    Button {
                        advanceStep()
                    } label: {
                        Text(actionTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)

                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: 380)
        }
        .transition(.opacity)
    }

    private var actionTitle: String {
        switch step {
        case 0: return String(localized: "下一步", locale: AppLanguageManager.currentLocale)
        case 1: return String(localized: "用 \(selectedProfile.displayName) 模式", locale: AppLanguageManager.currentLocale)
        case 2: return String(localized: "下一步", locale: AppLanguageManager.currentLocale)
        case 3: return String(localized: "下一步", locale: AppLanguageManager.currentLocale)
        default:
            return selectedProfile == .engineer
                ? String(localized: "开始巡检", locale: AppLanguageManager.currentLocale)
                : String(localized: "开始试录", locale: AppLanguageManager.currentLocale)
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "mic.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white)
                .padding(28)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text("欢迎用 SiteNote")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)

            Text("一个按钮录音 · AI 帮你整理 · 一键导出日报")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("录音和语音识别都在设备本地处理,不上传任何云端 AI。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
    }

    private var profileStep: some View {
        VStack(spacing: 14) {
            Text("你是?")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 8)

            Text("选个角色,App 会按你的需求显示界面")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("以后可在 设置 → 我是 ... 随时切换")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 4)

            ProfileSelectorView(selection: $selectedProfile, mode: .onboarding)
                .padding(.horizontal, 14)
        }
    }

    /// v1.5 改:不再在 onboarding 里现场创建工地 —— 真实工地需要补地址 / 客户 /
    /// 平面图 / 巡检模板等大量信息,onboarding 输个名字反而让用户以为「够了」。
    /// 改成纯教育页:告诉用户工地在哪建 + 引导路径,onboarding 完成后用户自己去补。
    private var firstSiteStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white)
                .padding(24)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text("工地等会儿建")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            Text("一个工地要填地址、客户、平面图、巡检模板,信息比较多 —— 不适合在引导里草草填。")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            // 路径指引胶囊:设置 → 工地 → 新建
            HStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text("设置")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "building.2.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Text("工地")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text("新建")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
            )
            .padding(.top, 4)

            Text("没建工地也能开始录 —— 录音会先进「未分类」,工地建好后再归类。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
    }

    private var gestureStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white)
                .padding(24)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text("按一下说 · 5 秒内可改")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 14) {
                gestureLine(icon: "mic.fill", color: Ink.red, title: "按住说话", sub: "松开 = 立即保存")
                gestureLine(icon: "exclamationmark.triangle.fill", color: Ink.red, title: "标隐患", sub: "安全问题,推送更密")
                gestureLine(icon: "book.fill", color: Ink.accentBlue, title: "存为日记", sub: "每日工种/机械,不提醒")
                gestureLine(icon: "pencil", color: Ink.fg, title: "细记 / 撤销", sub: "进详情页改字段 / 删掉重录")
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, 28)
    }

    private var tryItStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white)
                .padding(24)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text("现在试一条")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                tryLine(num: "1", text: "下一屏底部 红色大麦克风")
                tryLine(num: "2", text: "按住 不放 · 说一句话")
                tryLine(num: "3", text: "松开 自动保存")
                tryLine(num: "4", text: "5 秒内可点 撤销 / 改归类")
            }
            .padding(.horizontal, 24)

            Text("第一条会先进「未分类」收件箱,之后随时归类。")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Engineer 路径(step 3/4)

    /// Engineer step 3 — Session 工作流心智(4 行讲 4 个状态:开始 / 录音 / 完成 / 草稿)。
    /// 用相同的 gestureLine 组件保持视觉一致性,只是 icon + 配色不同。
    private var engineerSessionStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white)
                .padding(24)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text("巡检以 session 为单位")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            Text("不是零散记录 — 一次巡检从开始到完成自动汇成一份 PDF。")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 14) {
                gestureLine(
                    icon: "play.fill",
                    color: Ink.accentBlue,
                    title: "开始巡检",
                    sub: "选工地 · 顶部出现「正在巡检」"
                )
                gestureLine(
                    icon: "mic.fill",
                    color: Ink.red,
                    title: "期间录音自动归并",
                    sub: "每条都属于这次巡检,不用手动选"
                )
                gestureLine(
                    icon: "checkmark.circle.fill",
                    color: Ink.amber,
                    title: "完成 · 一键出 PDF",
                    sub: "Inspection report + 邮件给业主"
                )
                gestureLine(
                    icon: "tray.fill",
                    color: Color.gray.opacity(0.5),
                    title: "草稿可暂存",
                    sub: "日历里点「继续巡检」接着录"
                )
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, 28)
    }

    /// Engineer step 4 — 现场试一次巡检的 4 步骤。
    /// 引导用户走完整 session 而不是单条录音,符合工程师工作流心智。
    private var engineerTryItStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white)
                .padding(24)
                .background(Circle().fill(Color.white.opacity(0.1)))

            Text("开一次试试")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                tryLine(num: "1", text: "主屏大「开始巡检」按钮")
                tryLine(num: "2", text: "选工地 → 按住麦录一条")
                tryLine(num: "3", text: "顶部 banner「✓ 完成巡检」")
                tryLine(num: "4", text: "自动出 PDF + 弹邮件")
            }
            .padding(.horizontal, 24)

            Text("PDF 存进 设置 → 我的报告,可随时再发。")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .padding(.horizontal, 28)
    }

    private func tryLine(num: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            Text(num)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.15)))
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private func gestureLine(icon: String, color: Color, title: LocalizedStringKey, sub: LocalizedStringKey) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color).frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    // MARK: - Logic

    /// 回到上一步。step == 0 时无操作。
    /// 不回滚 step 1 已经写入的 profile / step 2 已经存的工地——这些副作用是幂等的(重写覆盖),
    /// 用户回去再前进会用最新选择再次覆盖。
    private func goBackStep() {
        guard step > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            step -= 1
        }
    }

    private func advanceStep() {
        if step == 1 {
            // 用户在 profile step 选了角色
            UserProfileManager.shared.select(selectedProfile)
        }
        // v1.5:step == 2 不再现场存工地(改成教育页,用户引导去 设置 → 工地 自己补)
        if step >= Self.totalSteps - 1 {
            UserDefaults.standard.set(true, forKey: Self.dismissedKey)
            withAnimation(.easeOut(duration: 0.25)) {
                isShown = false
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                step += 1
            }
        }
    }
}
