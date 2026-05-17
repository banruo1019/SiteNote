//
//  RecordView+StagedPhoto.swift
//  SiteNote
//
//  拍照"专注模式"UI:用户拍完后,主屏整个上方区域只显示大图预览 + 缩略图行 + 主操作按钮
//  (直接存 / AI 分析)。从 RecordView 抽出,纯展示性 view。
//

import SwiftUI

extension RecordView {

    @ViewBuilder
    var stagedPhotoFocusArea: some View {
        VStack(spacing: 0) {
            // 顶部栏:标题 + "丢弃"
            HStack {
                Text("刚拍 \(viewModel.stagedPhotos.count) 张")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(Ink.fg)
                Spacer()
                Button {
                    viewModel.clearStagedPhotos()
                } label: {
                    Text("丢弃")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Ink.red)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)

            if let last = viewModel.stagedPhotos.last {
                let lastIdx = viewModel.stagedPhotos.count - 1
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: last)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 380)
                        .background(Ink.card)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editingStagedIndex = EditingStagedIndex(value: lastIdx, image: last)
                        }

                    deletePhotoButton {
                        viewModel.removeStagedPhoto(at: lastIdx)
                    }
                    .padding(10)
                }
                .padding(.horizontal, 24)
            }

            if viewModel.stagedPhotos.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(viewModel.stagedPhotos.dropLast().enumerated()), id: \.offset) { idx, image in
                            ZStack(alignment: .topTrailing) {
                                Button {
                                    editingStagedIndex = EditingStagedIndex(value: idx, image: image)
                                } label: {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(Ink.line, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)

                                deletePhotoButton(size: 18) {
                                    viewModel.removeStagedPhoto(at: idx)
                                }
                                .offset(x: 6, y: -6)
                            }
                            .frame(width: 62, height: 62, alignment: .topTrailing)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 6)
                }
                .padding(.top, 8)
            }

            Spacer(minLength: 12)

            // 主操作行:[+ 继续拍] [✓ 直接存]
            // 工程师巡检场景一次现场常拍多张,"继续拍" 让用户连续触发 camera
            // 不用绕回 hero 按钮。"直接存" 保存所有 staged → Engineer 巡检中自动跳详情(RecordView.onChange 监听)
            HStack(spacing: 10) {
                Button {
                    isShowingCamera = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("继续拍")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(Ink.fg)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Ink.fg, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.savePhotosOnly()
                } label: {
                    Text("直接存")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Ink.fg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    /// 删除按钮:黑圆底白色减号,右上角悬浮。
    func deletePhotoButton(size: CGFloat = 24, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus")
                .font(.system(size: size * 0.55, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: size, height: size)
                .background(Ink.fg)
                .clipShape(Circle())
                .overlay(
                    Circle().strokeBorder(Color.white, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("删除这张照片")
    }
}
