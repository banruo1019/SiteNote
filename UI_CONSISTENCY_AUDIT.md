# UI 一致性审计报告 (2026-05-16 overnight #21)

**扫描范围**:`SiteNote/Views/**/*.swift`
**目标**:发现 UI token 使用不一致 → 视觉碎片化

---

## 1. 字号分布(20+ 种)

| 字号 | 出现次数 | 备注 |
|---|---|---|
| 12 | **129** | 副标题 / 小字主力,合理 |
| 11 | **100** | label / metadata,合理 |
| 14 | **62** | 正文主力 |
| 13 | **61** | 正文次主力 |
| 15 | **40** | Button label / 中等强调 |
| 10 | **36** | 极小字,合理 |
| 18 | 23 | 段落标题 |
| 22 | 16 | 主标题 |
| 17 | 10 | ⚠️ 跟 18 重叠,可能不必要 |
| 9 | 9 | 极极小 |
| 16 | 9 | ⚠️ 跟 15/17 重叠 |
| 24 / 28 | 8 / 6 | 大标题 |
| 48 / 36 | 7 / 7 | hero number(stat 大数字) |
| 26 / 20 / 44 / 56 / 40 | 各 2-4 次 | ⚠️ 孤例,可统一 |

### 不一致点

| 等级 | 现象 | 影响 |
|---|---|---|
| 🔴 高 | 16 / 17 / 18 / 20 共 50+ 处用法,但语义模糊(同样的"标题"用 3 种字号) | 视觉碎片化 |
| 🟡 中 | 26 / 28 / 36 / 40 / 44 / 48 / 56 各只用 2-7 次,**没有清晰的"hero number"标准** | hero 大数字一会大一会小 |
| 🟢 低 | 9 与 10 / 11 与 12 / 13 与 14 重叠 | 1pt 差异肉眼难分,但显得不严谨 |

### 建议字号体系(8 档)

```
caption    11pt  — metadata、label、辅助小字
body       13pt  — 正文、列表内容
emphasis   15pt  — 选中态、强调
title-S    18pt  — 段落标题
title-M    22pt  — 视图主标题
title-L    28pt  — 主屏大标题
hero       40pt  — stat 大数字
display    56pt  — record 计时器
```

(可以引入 `SiteFont.caption / .body / ...` enum 替代硬编码)

---

## 2. 圆角分布

| cornerRadius | 次数 | 用途推断 |
|---|---|---|
| 8 | **39** | 小卡片 / button |
| 10 | **32** | 中卡片 |
| 12 | **31** | 大卡片 / disclosure |
| 6 | 14 | 小 capsule / icon container |
| 4 | 7 | thumbnail |
| 2 / 14 / 16 | 1-2 次 | ⚠️ 孤例 |

### 不一致点
- 🔴 cornerRadius 8 / 10 / 12 三档**各占 1/3**,但语义模糊 — 同样大小的卡片为啥有 3 种圆角
- 🟡 14 / 16 各 2 次,孤例

### 建议
3 档:`small=6 / medium=10 / large=12`(已有 DesignTokens 的话先用)

---

## 3. 颜色 token 覆盖率

| 类型 | 次数 |
|---|---|
| `Ink.*` 使用 | **638 次** ✅ 主力 |
| `Color.red/orange/green/...` 硬编码 | 30 次 |

**覆盖率**:638 / (638+30) ≈ **95%** ✅ 非常好

详见 [DESIGN_TOKEN_AUDIT.md](./DESIGN_TOKEN_AUDIT.md)。

---

## 4. Button 样式

| 样式 | 次数 |
|---|---|
| `.buttonStyle(.plain)` | **100** ✅ 主力 |
| `.buttonStyle(.borderless)` | 5 |
| `.buttonStyle(.bordered)` | 3 |

**95% 用 .plain**(自定义视觉),5% 用 system Button — 偶发不一致(同样"轻量按钮"5 种实现混合)。

### 不一致点
- 🟡 `.borderless` 5 处和 `.plain` 实际视觉接近,可统一 `.plain`

---

## 5. Section 写法

| 写法 | 次数 |
|---|---|
| `SectionHeader(...)` / `SectionFooter(...)` helper | 35 |
| 裸 `Section("...")` | 27 |

### 不一致点
- 🟡 同一个文件混用两种写法(EngineerSettingsRoot 用 SectionHeader,某些子页用裸 Section)
- 视觉效果有差异:helper 用 Ink 设计 token,裸 Section 用 SwiftUI 默认样式

---

## 6. padding 分布

grep 没匹配到(语法和我想的不一样),改用人工浏览:常用 padding 数字看 source 是 8 / 10 / 12 / 14 / 16 / 20 / 24 混用。**没有清晰的 spacing token**(DesignTokens.Spacing.* 存在但用得不全)。

---

## 最大不一致点(给 task #78 修)

按"用户能视觉感知 + 改动小"排序:

### 🥇 polish #1:字号 17 → 18(10 处)
- 17pt 是 UIKit `large` 标签默认,SwiftUI 用得少。统一 17 → 18 让段落标题档清晰。
- 改动文件:5-7 个 view

### 🥈 polish #2:字号 16 → 15 或 18(9 处)
- 16 跟 15 / 17 / 18 重叠,选 closest 合并

### 🥉 polish #3:cornerRadius 14 / 16(各 2 处)合并到 12
- 孤例统一,代码改 4 处

### polish #4:`.borderless` 5 处 → `.plain`
- 视觉接近,改 5 处

### polish #5:**Section** 裸 27 处统一改 SectionHeader/Footer
- 影响 5-8 个文件,但视觉提升明显(token 统一)

---

## 整体评估

| 维度 | 等级 |
|---|---|
| 颜色 token | 🟢 95% 覆盖 |
| Button 样式 | 🟢 95% .plain |
| 字号 | 🟡 20+ 种孤例,需收敛到 8 档 |
| 圆角 | 🟡 3 档主流 + 孤例 |
| Section | 🟡 2 种写法混用 |
| Spacing token | 🔴 DesignTokens.Spacing 用得不全 |

**主问题**:**字号 + Section 写法**,polish 一晚就能完成主要部分。
**次要**:Spacing token 推广(v1.2 重构一波)。

---

## 修复优先级(给 task #78)

`#78 fix: UI 一致性 polish 5 处`,**按此顺序**:

1. 字号 17 → 18(10 处)
2. 字号 16 → 15 或 18(9 处,case-by-case)
3. cornerRadius 14 / 16 → 12(4 处)
4. `.borderless` → `.plain`(5 处)
5. 裸 Section → SectionHeader(选 3-5 处最显眼的)

每步独立 commit + build verify。
