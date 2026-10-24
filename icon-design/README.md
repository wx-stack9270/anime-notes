# 工具广场图标风格规范

> 适用场景：AI Agent 平台的「工具广场 / Tool Marketplace」——功能入口、模块标签、状态控件、工具卡片。
> 风格定位：**线性极简**（描边为主、少填充、克制留白），贴合 AI 平台普遍的科技感与轻量观感。

## 1. 基础画布与网格

| 参数 | 值 |
|------|----|
| viewBox | `0 0 24 24`（统一，不可变） |
| 内容安全区 | 内缩 2px，即 `2 ~ 22`（20×20 有效绘制区） |
| 描边宽度 | `1.5px`（16px 档位降为 `2px` 保证清晰） |
| 圆角 | `2px`（小元素 `1.5px`） |
| 端点 / 拐角 | `stroke-linecap="round"` / `stroke-linejoin="round"` |
| 填充规则 | 默认 `fill="none"`，仅选中态/强调态局部填充 |

## 2. 颜色语义

| 语义 | 色值 | 用途 |
|------|------|------|
| 默认（中性） | `#5F5E5A` | 常规图标，跟随 `currentColor` |
| 主色 | `#378ADD` | 已安装、激活、当前项 |
| 成功 | `#639922` | 就绪、通过、可用 |
| 警示 | `#BA7517` | 更新、待处理 |
| 危险 | `#E24B4A` | 失败、停用、删除 |

> 原则：**中性为主，彩色只为状态服务**。图标主体一律 `stroke="currentColor"`，由组件层注入颜色，方便统一换肤与深浅主题适配。

## 3. 尺寸档位

| 档位 | 尺寸 | 场景 |
|------|------|------|
| sm | 16px | 导航、标签内联 |
| md | 20px | 工具卡片、列表行 |
| lg | 24px | 详情页、空状态 |

## 4. 命名约定

kebab-case，前缀 `tool-` 标识「工具广场」命名空间：

```
tool-grid（全部）  tool-search（搜索）   tool-filter（筛选）
tool-sort（排序）   tool-star（收藏）     tool-check（已安装）
tool-clock（最近）  tool-trend（热门）    tool-plugin（工具）
tool-upload（上传） tool-settings（设置） tool-bookmark（收藏夹）
```

## 5. 用法（SVG sprite / symbol）

生产环境推荐 `<use>` 引用，`color` 属性即可控制颜色：

```html
<svg style="display:none">
  <symbol id="tool-search" viewBox="0 0 24 24">
    <g fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">
      <circle cx="10.5" cy="10.5" r="6.5"/><line x1="15.5" y1="15.5" x2="21" y2="21"/>
    </g>
  </symbol>
</svg>

<!-- 使用：默认灰 / 主色蓝 -->
<svg width="20" height="20" style="color:#5F5E5A"><use href="#tool-search"/></svg>
<svg width="20" height="20" style="color:#378ADD"><use href="#tool-search"/></svg>
```

## 6. 批量生成提示词模板

后续用 AI 扩展图标时，统一套用以下模板，保证风格不漂移：

```
A minimal linear UI icon, 24x24 grid, 2px inner padding,
1.5px stroke, rounded caps and joins, 2px corner radius,
outline style with no fill, single solid color, currentColor.
Subject: {图标语义，如 "a magnifying glass"}.
Clean, consistent stroke weight, generous whitespace,
flat modern tech style, suitable for an AI platform toolbar.
No text, no background, no gradient, no shadow.
```

## 7. 交付清单

- `tool-marketplace-icons.svg` —— 12 枚 `<symbol>` 组成的 sprite，可直接引入项目组件库
- 本规范文件（README）

## 8. 审校要点（一致性优先）

1. 所有图标描边宽度必须同为 `1.5`，不得混用 `1`/`2`
2. 路径必须闭合或为单笔连续，避免多余锚点与视觉噪声
3. 同套图标视觉重量均衡：粗看密度一致，不出现某枚过空/过满
4. 语义唯一：一个概念只对应一个图形，不重复造形
