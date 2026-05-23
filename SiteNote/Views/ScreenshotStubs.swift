//
//  ScreenshotStubs.swift
//  SiteNote
//
//  v1.6 (en-v1):App Store 截图专用 stub views。
//  当 `MockDataSeeder.startScreen == "recording" / "floorplan"` 时,
//  AdaptiveRootView 渲染这些 stub 而不是 MainTabView,得到稳定的截图状态。
//
//  仅用于截图,生产用户绝对不会触发(launch arg gated)。
//

import SwiftUI

// MARK: - Recording state stub (录音中)
//
// 复刻 RecordView 在 isRecording=true 时的视觉:顶部录音 banner + 转写文字,
// 中部空,底部大圆 MIC 按钮(红色,表示正在录音)。
//
// 没有真实 audio,只是静态截图。

struct ScreenshotRecordingStub: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            Ink.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部录音 banner
                recordingBanner
                    .padding(.top, 60)

                Spacer(minLength: 0)
            }

            // 底部大圆按钮
            heroButtons
                .padding(.bottom, 80)

            // 底部 tab bar 占位
            VStack {
                Spacer()
                tabBar
            }
        }
    }

    private var isZh: Bool { MockDataSeeder.isChineseLocale }

    private var recordingBanner: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Ink.red)
                    .frame(width: 10, height: 10)
                Text(isZh ? "录音中 · 00:08" : "Recording · 00:08")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                    .monospacedDigit()
                Spacer()
                Text(isZh ? "上滑取消" : "Slide up to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(Ink.fgDim)
            }

            // 转写文字(部分)
            Text(isZh
                 ? "三层东侧楼梯口钢筋外露,用警示带围起来并通知工长……"
                 : "Exposed reinforcement on level three east stair landing. Tape off the area and notify the foreman before…")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Ink.fg)
                .lineSpacing(4)
                .multilineTextAlignment(.leading)

            // 波形占位
            HStack(spacing: 3) {
                ForEach(0..<32, id: \.self) { i in
                    let h: CGFloat = [8, 14, 24, 32, 18, 12, 22, 28, 16, 20, 30, 14, 10, 24, 18, 8, 12, 26, 32, 22, 14, 18, 8, 28, 20, 14, 24, 32, 18, 12, 22, 28][i]
                    Capsule()
                        .fill(Ink.red.opacity(0.6))
                        .frame(width: 3, height: h)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Ink.bg)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        )
        .padding(.horizontal, 16)
    }

    private var heroButtons: some View {
        HStack(spacing: 24) {
            // Camera 圆按钮
            Circle()
                .strokeBorder(Ink.fg, lineWidth: 1.5)
                .background(Circle().fill(Ink.bg))
                .frame(width: 132, height: 132)
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(Ink.fg)
                )

            // Mic 圆按钮(red,录音中)
            Circle()
                .fill(Ink.red)
                .frame(width: 132, height: 132)
                .overlay(
                    Image(systemName: "mic.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .scaleEffect(1.0)
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabItem(isZh ? "记" : "Log", selected: true)
            tabItem(isZh ? "日历" : "Calendar", selected: false)
            tabItem(isZh ? "报告" : "Reports", selected: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Ink.bg
                .overlay(alignment: .top) {
                    Rectangle().fill(Ink.line).frame(height: 1)
                }
        )
    }

    private func tabItem(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 14, weight: selected ? .semibold : .regular))
            .tracking(0.2)
            .foregroundStyle(selected ? Ink.fg : Ink.fgDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
    }
}

// MARK: - Floor plan marking stub (平面图标记)
//
// 复刻 FloorPlanMarkView 的视觉:顶部 toolbar(Cancel / 标题 / Save),
// 中间 平面图 + pin 标记,底部 plan 名 + 提示。
//
// 平面图 = MockDataSeeder 生成的 800x600 architectural placeholder。

struct ScreenshotFloorPlanStub: View {
    let planImage: UIImage?

    private var isZh: Bool { MockDataSeeder.isChineseLocale }

    var body: some View {
        ZStack(alignment: .top) {
            Ink.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                planArea
                bottomBar
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text(isZh ? "取消" : "Cancel")
                .font(.system(size: 16))
                .foregroundStyle(Ink.fg)
            Spacer()
            Text(isZh ? "平面图标记" : "Mark on Plan")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.fg)
            Spacer()
            Text(isZh ? "保存" : "Save")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Ink.fg)
        }
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .padding(.bottom, 16)
        .background(Ink.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    private var planArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(white: 0.97)

                if let img = planImage {
                    let displaySize = aspectFit(image: img.size, in: geo.size)
                    Image(uiImage: img)
                        .resizable()
                        .frame(width: displaySize.width, height: displaySize.height)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    // Pin at normalized (0.62, 0.42) on the displayed image
                    let pinX = (geo.size.width - displaySize.width) / 2 + displaySize.width * 0.62
                    let pinY = (geo.size.height - displaySize.height) / 2 + displaySize.height * 0.42
                    pin
                        .position(x: pinX, y: pinY)
                }
            }
        }
    }

    private var pin: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 26, height: 26)
            Circle()
                .fill(Ink.red)
                .frame(width: 18, height: 18)
            // 十字准星
            ZStack {
                Rectangle().fill(Color.white).frame(width: 8, height: 1.5)
                Rectangle().fill(Color.white).frame(width: 1.5, height: 8)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isZh ? "一层 · 东翼" : "LEVEL 1 — EAST WING")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Ink.fgDim)
            Text(isZh ? "双指缩放 · 拖动平移 · 双击复位" : "Pinch to zoom · Drag to pan · Double-tap to reset")
                .font(.system(size: 12))
                .foregroundStyle(Ink.fgDim)
            HStack(spacing: 6) {
                Circle().fill(Ink.red).frame(width: 8, height: 8)
                Text(isZh ? "隐患图钉 · 比 GPS 精度高 10 倍" : "Hazard pin · 10× more accurate than GPS")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Ink.fg)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Ink.bg)
        .overlay(alignment: .top) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    private func aspectFit(image: CGSize, in container: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let imgAspect = image.width / image.height
        let conAspect = container.width / container.height
        if imgAspect > conAspect {
            return CGSize(width: container.width, height: container.width / imgAspect)
        } else {
            return CGSize(width: container.height * imgAspect, height: container.height)
        }
    }
}

// MARK: - Note detail stub (note 详情 — 信息 + 平面图 + 派发)
//
// 复刻 NoteDetailView 的核心信息密度:顶部 hazard banner + 时间 + 转写,
// 工地 / 派发 / 天气元信息,floor plan 缩略图 + pin,照片缩略图。
// 一屏内尽量塞 4 个 feature 的视觉证据。

struct ScreenshotNoteDetailStub: View {
    let planImage: UIImage?

    private var isZh: Bool { MockDataSeeder.isChineseLocale }

    var body: some View {
        ZStack(alignment: .top) {
            Ink.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 56)  // nav bar 空间
                    hazardBanner
                    headerBlock
                    metaBlock
                    Divider().padding(.vertical, 4)
                    floorPlanBlock
                    Divider().padding(.vertical, 4)
                    photosBlock
                    Spacer(minLength: 40)
                }
            }
            navBar
        }
    }

    private var navBar: some View {
        HStack {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.fg)
            Spacer()
            Text(isZh ? "速记" : "Note")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Ink.fg)
            Spacer()
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17))
                .foregroundStyle(Ink.fg)
        }
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .padding(.bottom, 12)
        .background(Ink.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Ink.line).frame(height: 1)
        }
    }

    private var hazardBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Ink.red)
            Text(isZh ? "隐患" : "HAZARD")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(Ink.red)
            Spacer()
            Text(isZh ? "安全" : "Safety")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Ink.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(isZh ? "今天" : "Today")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Ink.fg)
                Text("· 09:21")
                    .font(.system(size: 14))
                    .foregroundStyle(Ink.fgDim)
                Spacer()
                Text(isZh ? "今日到期" : "Due today")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Ink.fg)
                    .clipShape(Capsule())
            }
            Text(isZh
                 ? "三层东侧楼梯口钢筋外露,11 点前用警示带围起来并通知工长。"
                 : "Exposed reinforcement on level 3 east stair landing. Tape off the area and notify the foreman before 11 am.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Ink.fg)
                .lineSpacing(3)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var metaBlock: some View {
        VStack(spacing: 8) {
            if isZh {
                metaRow(icon: "building.2",  label: "工地",   value: "悉尼 CBD 塔楼")
                metaRow(icon: "location",    label: "位置",   value: "悉尼 NSW · 0.04 km")
                metaRow(icon: "cloud.sun",   label: "天气",   value: "晴 · 18°C")
                metaRow(icon: "person.fill", label: "派发给", value: "小李 · 现场监督")
            } else {
                metaRow(icon: "building.2",  label: "Site",      value: "Sydney CBD Tower")
                metaRow(icon: "location",    label: "Location",  value: "Sydney, NSW · 0.04 km")
                metaRow(icon: "cloud.sun",   label: "Weather",   value: "Sunny · 18°C")
                metaRow(icon: "person.fill", label: "Assigned",  value: "Jamie · Site supervisor")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func metaRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Ink.fgDim)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.3)
                .textCase(.uppercase)
                .foregroundStyle(Ink.fgDim)
                .frame(width: 88, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Ink.fg)
            Spacer()
        }
    }

    private var floorPlanBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isZh ? "平面图" : "FLOOR PLAN")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Ink.fgDim)

            if let img = planImage {
                ZStack(alignment: .topLeading) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color(white: 0.97))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Ink.line, lineWidth: 1)
                        )
                    // Pin overlay (approximate position)
                    GeometryReader { geo in
                        ZStack {
                            Circle().fill(Color.white).frame(width: 22, height: 22)
                            Circle().fill(Ink.red).frame(width: 16, height: 16)
                        }
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .position(x: geo.size.width * 0.62, y: geo.size.height * 0.42)
                    }
                }
            }

            Text(isZh ? "一层 · 东翼 · 图钉位置 (62%, 42%)" : "Level 1 — East Wing · Pin at (62%, 42%)")
                .font(.system(size: 11))
                .foregroundStyle(Ink.fgDim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private var photosBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isZh ? "照片(2 张)" : "PHOTOS (2)")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Ink.fgDim)
            HStack(spacing: 8) {
                photoPlaceholder(label: isZh ? "安全" : "Safety", color: UIColor.systemOrange)
                photoPlaceholder(label: isZh ? "细节" : "Detail", color: UIColor.systemGray)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    private func photoPlaceholder(label: String, color: UIColor) -> some View {
        let isSafety = label == "Safety" || label == "安全"
        return ZStack {
            LinearGradient(
                colors: [Color(uiColor: color), Color(uiColor: color).opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 6) {
                Image(systemName: isSafety ? "exclamationmark.triangle.fill" : "wrench.and.screwdriver.fill")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.white.opacity(0.75))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
