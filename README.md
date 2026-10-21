# 简约翻译（KISS Translator for Safari）

**把开源双语翻译扩展 [KISS Translator](https://github.com/fishjar/kiss-translator) 打包成 macOS 原生 Safari 扩展，应用名为「简约翻译」。**

[![许可证 GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-green.svg)](LICENSE)
[![平台](https://img.shields.io/badge/platform-macOS%2014%2B%20%C2%B7%20Safari%2017%2B-lightgrey)](https://github.com/ftzahao/kiss-translator-safari)

> **非官方项目。** 本项目是社区为 Safari 做的打包版本，并非上游作者的官方产品。
> 详见[许可证与署名](#许可证与署名)。

本仓库只做一件事：**克隆代码，在自己的 Mac 上本地构建**。不提供预编译下载，
也没有 CI 与发布流程——本地用免费的 Apple Development 证书签名构建的包，
在自己机器上就是完整可用的。

---

## 截图

<!-- docs/images/hero.png 由维护者补充；在此之前显示的是替代文字。 -->
<picture>
  <source srcset="docs/images/截屏2026-10-21 09.50.59 - Safari浏览器.png" type="image/png">
  <img src="docs/images/截屏2026-10-21 09.50.59 - Safari浏览器.png" alt="KISS Translator 在 Safari 中展示网页双语对照翻译">
</picture>
<picture>
  <source srcset="docs/images/截屏2026-10-21 09.51.04 - Safari浏览器.png" type="image/png">
  <img src="docs/images/截屏2026-10-21 09.51.04 - Safari浏览器.png" alt="KISS Translator 在 Safari 中展示网页双语对照翻译">
</picture>

---

## 功能

以下能力全部来自上游扩展。本仓库只负责 macOS 容器 App、构建流程和打包，
不会改变翻译行为。

- **网页双语对照翻译**：逐段翻译网页，并在原文下方（或上方）插入译文，保留富文本格式；
  也可以切换为「只显示译文」模式。
- **划词翻译与查词**：选中文字即弹出译文气泡；英文单词可查词典并加入生词本。
- **悬浮翻译**：鼠标悬停时按需翻译当前段落，也支持长按鼠标触发（可配置）。
- **多种翻译引擎**：Google、Microsoft/Azure、DeepL 与 DeepLX、百度、腾讯、火山、
  Yandex 等传统接口；以及 OpenAI、Gemini、Claude、DeepSeek、Ollama、OpenRouter 等
  AI 接口。还提供**自定义 / OpenAI 兼容接口**，可自行填写端点、密钥、模型和请求模板。
- **网站规则与自动翻译**：按网站配置翻译规则，配合可视化元素选择器精确圈定翻译范围；
  指定站点自动翻译，不需要的站点排除在外。
- **朗读（TTS）**：对翻译结果进行语音朗读。
- **YouTube 双语字幕**：在播放器中合并并翻译字幕轨道。
- **译文样式预设**：下划线、荧光笔、模糊、引用块等多种样式，让双语排版更易读。
- **配置同步**：通过自建的 [KISS-Worker](https://github.com/fishjar/kiss-worker)
  或 WebDAV 在多台设备之间同步设置。

Safari 的 Web Extension 运行时与 Chromium / Firefox 并不完全一致（例如离屏文档的
处理方式不同），因此文件翻译、端侧 AI 等进阶功能可能会受限甚至缺失，具体取决于上游版本和
Safari 版本。遇到疑问时请以对应上游版本的发布说明为准。

---

## 安装

克隆仓库后本地构建。构建产物（`build/App/简约翻译.app`）只在构建它的
那台 Mac 上可用。

### (a) 从源码构建

**环境要求**

| 工具     | 版本                                                                               |
| -------- | ---------------------------------------------------------------------------------- |
| macOS    | 14 (Sonoma) 或更高                                                                 |
| Xcode    | 16 或更高（已通过 `xcode-select` 选中命令行工具）；要启用液态玻璃外观需 Xcode 26+  |
| Node.js  | 20 或更高                                                                          |
| pnpm     | **9.14.4**，必须是这个版本。pnpm 10+ 会因 `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH` 失败 |
| XcodeGen | 最新版（`brew install xcodegen`）                                                  |

**开始构建**

```sh
git clone https://github.com/ftzahao/kiss-translator-safari.git
cd kiss-translator-safari

make deps        # 拉取并校验锁定版本的上游源码，安装其依赖
make all         # 扩展 → Xcode 工程 → 通用二进制 App → DMG + ZIP
```

**签名——Safari 认这个构建的前提**

Safari 只列出包含 App 代码签名中带真实 **Team Identifier** 的 Web 扩展。没有它
（ad-hoc 或未签名），无论 onboarding 怎么提示，扩展都不会出现在
**Safari → 设置 → 扩展** 里。

1. 在 Xcode 中登录 Apple ID（**Xcode → Settings → Accounts → +**），Xcode 会
   自动为你签发 _Apple Development_ 证书——**免费**账号即可，构建的 App 只在
   自己的 Mac 上运行。
2. `make all` 会自动检测该证书所属的团队并用它签名。需要显式指定（或自动检测
   为空）时——Team ID 是证书的 **OU** 字段（不要相信证书名称括号里的后缀）：

   ```sh
   security find-certificate -c "Apple Development" -p \
     | openssl x509 -noout -subject -nameopt sep_multiline | awk -F= '/OU=/{print $2}'
   make all DEVELOPMENT_TEAM=<TEAMID>
   ```

3. 验证结果：`make verify` 输出 `Safari will accept this build`，且 onboarding
   窗口不再显示橙色的 ad-hoc 警告。
4. 启动一次 `build/App/简约翻译.app`——这一步会把扩展注册给 Safari——然后
   在 **Safari → 设置 → 扩展** 中勾选 **简约翻译** 并授予网站访问权限
   （逐站点授权，或「始终允许在所有网站」）。

> 这种构建只能在你自己的 Mac 上运行：Apple Development 证书不可再分发。本地构建的
> App 没有 quarantine 属性，首次打开也不会触发 Gatekeeper 警告。

中途也想单独执行也可以：

| 目标             | 作用                                                             |
| ---------------- | ---------------------------------------------------------------- |
| `make deps`      | 拉取锁定的上游版本到 `.build/upstream` 并安装依赖                |
| `make extension` | 构建 MV3 Web Extension 到 `extension/`                           |
| `make project`   | 用 XcodeGen 生成 `KISSTranslator.xcodeproj`                      |
| `make build`     | 构建 `build/App/简约翻译.app`（arm64 + x86_64 通用二进制）        |
| `make sign`      | 签名（需要你自己的签名证书）                                     |
| `make dmg`       | 生成 `build/dist/简约翻译-<版本>.dmg` 与 `.zip`                  |
| `make all`       | 依次执行 `extension` + `project` + `build` + `dmg`               |
| `make verify`    | 校验锁定的上游版本/提交以及产物完整性                            |
| `make clean`     | 清理构建产物                                                     |

### (b) 在 Xcode 中调试

```sh
make project
open KISSTranslator.xcodeproj
```

在 Xcode 里点 **Run** 运行容器 App。此时 Safari 会拒绝加载扩展，因为它没有可信签名。

允许未签名的扩展：

1. 打开 Safari **设置 → 高级**，勾选 **显示网页开发者功能**。
   （这是当前 Safari 的正确入口；旧教程里的 `defaults write com.apple.Safari IncludeDevelopMenu -bool true` 已过时。）
2. 菜单栏会出现 **开发** 菜单，点击 **开发 → 允许未签名的扩展**，按提示输入密码。
   该设置**在每次重启 Safari 后失效**，需要重新勾选。
3. 再从 Xcode 运行一次 App，让 Safari 重新识别扩展，然后在 **设置 → 扩展** 中启用。

如果 Safari 仍然找不到扩展，可以执行 `safaridriver --enable`（需要管理员权限）开启与
自动化相关的开发者开关，用来辅助排查。

---

## 系统要求

|              |                                                                                                 |
| ------------ | ----------------------------------------------------------------------------------------------- |
| 系统         | macOS 14 Sonoma 或更高                                                                          |
| 浏览器       | Safari 17 或更高                                                                                |
| 架构         | 通用二进制：Apple Silicon（`arm64`）与 Intel（`x86_64`）                                        |
| 构建工具     | Xcode 16+、Node 20+（与 `upstream.nodeMajor` 一致）、pnpm 9.14.4、XcodeGen                      |
| 外观         | 用 macOS 26 SDK（Xcode 26+）构建时，在 macOS 26+ 上启用液态玻璃（Liquid Glass）；否则为经典外观 |
| iOS / iPadOS | 暂不支持                                                                                        |

---

## 工作原理

```
  上游发布 v<版本>（锁定在 config/build.config.mjs）
         │
         │  make deps —— 按锁定 commit 拉取源码包、校验 SHA、pnpm install (9.14.4)
         ▼
  .build/upstream/                （上游源码树，不在原地修改）
         │
         │  make extension —— 构建 MV3 Web Extension
         ▼
  extension/                      （manifest.json、background.js、content.js 等）
         │
         │  make project —— XcodeGen 读取 project.yml（配合 config/build.config.mjs）
         ▼
  KISSTranslator.xcodeproj        （生成物，已 git 忽略）
         │
         │  make build —— xcodebuild，Release 配置，通用二进制
         ▼
  build/App/简约翻译.app
    └── Contents/PlugIns/KISSTranslatorExtension.appex
          └── Contents/Resources/manifest.json 及扩展资源
         │
         │  make dmg
         ▼
  build/dist/简约翻译-<版本>.dmg  +  .zip   （本地安装使用）
```

几点说明：

- Xcode 工程是**生成**出来的，不要手工修改；要改就改 XcodeGen 的配置后再执行 `make project`。
- Web Extension 是从**锁定的上游提交**构建的，不跟随分支推进。`make verify` 会复核这个锁定。
- SwiftUI 容器 App 刻意保持极简：只负责承载 `.appex` 并提示如何启用。所有翻译逻辑都在扩展里。

---

## 如何更新

本仓库不再发布 Release，应用内的更新检查不会再提示新版本。更新方式是重新构建：

```sh
git pull
make clean && make deps && make all
```

然后把新的 `build/App/简约翻译.app` 重新拖入「应用程序」覆盖旧版即可，
Safari 中的扩展配置（翻译源、站点规则等）会保留。

---

## 如何跟进上游

上游版本锁定在 `config/build.config.mjs`：

```js
export const upstream = {
  version: "2.1.1",
  commit: "a1279f2517bd478ef1dd93b941f9177094486cd4",
  pnpmVersion: "9.14.4",
  ...
};
```

升级步骤：

1. 在 [fishjar/kiss-translator/releases](https://github.com/fishjar/kiss-translator/releases)
   找到上游发布 tag 及其对应提交。
2. 更新 `upstream.version` 与 `upstream.commit`，同时同步 `app.marketingVersion`。
3. 执行 `make clean && make deps && make verify`，复核提交并重新构建。
4. 在 `CHANGELOG.md` 里补一条记录并提交。

**版本号沿用上游版本号。** 本项目没有独立的打包版本号，`2.1.1` 的含义就是
「上游 KISS Translator 2.1.1 的 Safari 打包版」。只涉及打包层的修复会并入同一条更新日志，
随下一次上游升级一起记录，以保证版本号始终对应清晰的上游版本。

---

## 许可证与署名

**本项目以 GNU GPL v3.0 发布。** 见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。

- **原始项目：** [KISS Translator](https://github.com/fishjar/kiss-translator)，
  作者 **fishjar**（Gabe），GPL-3.0。
- 本仓库是**衍生作品**：它分发上游 Web Extension 的构建产物，并额外提供 macOS 原生封装
  （SwiftUI 容器 App、构建脚本、工程生成配置）。这部分封装代码同样以 GPL-3.0 授权。
- 本仓库构建的每一个二进制，其对应源码都可以在本仓库以及 [NOTICE](NOTICE) 中列出的上游提交里获取。
- **不提供任何担保。** 软件按「现状」提供，不附带任何形式的保证，详见 GPL 第 15、16 条。

### 商标与捐赠声明

- 「KISS Translator」名称与 Logo 归上游作者所有。本仓库**不是官方扩展，也不代表官方**，
  除继承 GPL 代码之外与 fishjar 没有隶属关系。
- 如果想在经济上支持这个项目，请通过[上游 README 的赞助链接](https://github.com/fishjar/kiss-translator#appreciation)
  捐赠给**上游作者**。本仓库不接受捐赠。

---

## 常见问题

**Safari 的「设置 → 扩展」里看不到这个扩展。**
请确认容器 App 已经从 `/Applications` 至少启动过一次——只有被安装并运行过的 App 注册的扩展，
Safari 才能发现。之后再退出并重新打开 Safari。如果是自己从源码构建的，请参照
[在 Xcode 中调试](#b-在-xcode-中调试)开启 **开发 → 允许未签名的扩展**；用 Apple
Development 证书签名的构建则不需要这一步，直接在 **设置 → 扩展** 中勾选即可。

**Safari 提示「Safari 无法验证扩展」。**
这是未签名 / 临时签名的构建触发了 Gatekeeper，属于预期行为。本地用 Apple Development
证书构建的 App 没有 quarantine 属性，不会出现这个提示；从别处拷贝来的 App 可以
右键 → **打开**，或执行
`xattr -dr com.apple.quarantine "/Applications/简约翻译.app"`。

**能在 iOS / iPadOS 上用吗？**
暂时不行。项目目前只面向 macOS。要支持 iOS/iPadOS 需要额外的构建目标和 App Store 分发，
会在后续单独处理。

**支持 Safari Technology Preview 吗？**
通常可以，但不在测试范围内。反馈问题时请附上具体的 Safari / STP 版本。

**翻译本身出错该去哪里反馈？**
如果问题出在翻译结果、翻译服务或网页排版，请反馈到
[上游](https://github.com/fishjar/kiss-translator/issues)。如果是安装、签名、容器 App 或构建问题，
可以查看 [docs/BUILDING.md](docs/BUILDING.md) 的故障排查章节。

**我的数据会被发送到哪里？**
扩展只会把你待翻译的文本发送给**你自己配置的**翻译服务，行为与上游一致。
本项目不收集任何遥测，也不架设任何服务器。见 [SECURITY.md](SECURITY.md)。

---

## 相关链接

- 上游项目：<https://github.com/fishjar/kiss-translator>
- 上游配套服务：[KISS-Worker](https://github.com/fishjar/kiss-worker)（同步）、
  [kiss-rules](https://github.com/fishjar/kiss-rules)（社区规则）
- 构建细节：[docs/BUILDING.md](docs/BUILDING.md)
