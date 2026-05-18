//
//  NoteDetailView+Photos.swift
//  SiteNote
//
//  NoteDetailView 的照片/缩略图/加照片相关 section。
//  从主文件抽出,纯展示性 view,依赖 main struct 的 @State / @Bindable。
//

import SwiftUI
import UIKit

extension NoteDetailView {

    // MARK: - 3. 照片区

    @ViewBuilder
    var photosBlock: some View {
        if !note.photoPaths.isEmpty {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.small) {
                HStack {
                    Text("照片")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(note.photoPaths.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                photoLayout
                    .id(galleryRefreshID)
            }
        }
    }

    /// 第一张大图占满宽度,其余小图水平滚动。单张就只有大图。
    @ViewBuilder
    var photoLayout: some View {
        if let firstPath = note.photoPaths.first,
           let url = PhotoStorage.absoluteURL(forRelative: firstPath),
           let firstImage = UIImage(contentsOfFile: url.path) {
            VStack(spacing: DesignTokens.Spacing.small) {
                bigPhoto(path: firstPath, image: firstImage)

                if note.photoPaths.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: DesignTokens.Spacing.small) {
                            ForEach(note.photoPaths.dropFirst(), id: \.self) { path in
                                photoThumbnail(for: path)
                            }
                        }
                    }
                }
            }
        }
    }

    func bigPhoto(path: String, image: UIImage) -> some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.08))
                .frame(height: 240)
                .overlay(
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipped()
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture {
                    fullscreenPhoto = FullscreenPhoto(image: image, path: path)
                }

            Button {
                editingDetailPhoto = DetailPhotoEdit(path: path, image: image)
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.white, Color.black.opacity(0.6))
                    .padding(8)
            }
            .accessibilityLabel(String(localized: "标注此照片"))
        }
    }

    // MARK: - 4. 加照片按钮(独立一行)

    var addPhotoRow: some View {
        Button {
            showsPhotoSourceDialog = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text("加照片")
                    .font(.system(size: DesignTokens.FontSize.body, weight: .semibold))
                Spacer()
                Image(systemName: "camera.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.accentColor)
            .padding(DesignTokens.Spacing.medium)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "添加照片"))
    }

    // MARK: - 缩略图

    @ViewBuilder
    func photoThumbnail(for path: String) -> some View {
        if let url = PhotoStorage.absoluteURL(forRelative: path),
           let image = UIImage(contentsOfFile: url.path) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.08))
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 120)
                            .clipped()
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        fullscreenPhoto = FullscreenPhoto(image: image, path: path)
                    }
                Button {
                    editingDetailPhoto = DetailPhotoEdit(path: path, image: image)
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, Color.black.opacity(0.6))
                        .padding(4)
                }
                .accessibilityLabel(String(localized: "标注此照片"))
            }
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 120, height: 120)
                .overlay(Image(systemName: "photo").font(.title))
        }
    }
}
