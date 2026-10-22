# 动漫笔记（AnimeTracker）

一个用 SwiftUI 编写的 macOS 动漫记录应用，用于追番打卡和收藏管理。

## 功能

- 在看 / 看完的动漫记录管理
- 剧集进度追踪
- 封面图片自动抓取与本地缓存（基于 Bangumi API）
- 数据本地存储，原子写入保证安全

## 构建与运行

```bash
./build.sh
open build/动漫记录本.app
```

无第三方依赖，纯 SwiftUI 实现。

## 数据存储

数据保存在 `~/Library/Application Support/AnimeTracker/` 下：

- `library.json` — 动漫记录
- `covers/` — 封面缓存
