# 动漫笔记（AnimeTracker）

一个用 SwiftUI 编写的 macOS 动漫记录应用，用于追番打卡和收藏管理。

## 功能

- 在看 / 看完的动漫记录管理
- 剧集进度追踪
- 封面图片自动抓取与本地缓存（基于 Bangumi API）
- 数据本地存储，原子写入保证安全

## 构建与运行

```bash
git clone https://github.com/wx-stack9270/anime-notes.git
cd anime-notes
./build.sh
open build/动漫记录本.app
```

无第三方依赖，纯 SwiftUI 实现。

### 系统要求

- **Apple Silicon Mac（M 系列芯片）**：编译目标为 `arm64-apple-macosx26.0`
- **macOS 26.0 或更高版本**：界面使用了 Liquid Glass（`glassEffect`）新 API
- **Xcode 或 Command Line Tools**（含 macOS 26 SDK）：未安装可执行 `xcode-select --install`
- 首次打开如遇 Gatekeeper 提示，右键 App →「打开」即可（ad-hoc 签名，未做公证）

> 注意：本仓库只提供源码，不提供编译好的 .app。从源码在本机构建不会触发 Gatekeeper 限制。

## 数据存储

数据保存在 `~/Library/Application Support/AnimeTracker/` 下：

- `library.json` — 动漫记录
- `covers/` — 封面缓存
