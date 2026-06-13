# UnjailTheos

iOS 本地 Theos 编译器 GUI，面向 TrollStore（巨魔）侧载环境（iOS 15.0+）。支持手机端本地编译、GitHub Actions 云端编译，以及国内网络 gh-proxy 加速。

## 功能概览

| 模块 | 功能 |
|------|------|
| **环境** | 自动安装 Theos、下载/导入 iPhoneOS SDK、gh-proxy 加速 |
| **编辑器** | Tweak 项目文件树 + Logos/Makefile 语法高亮 |
| **构建** | Root Helper 执行 `make package`，实时日志 |
| **云端构建** | 一键 push 到 GitHub，触发 Actions 编译用户 Tweak（.deb） |

## 项目结构

```
TrollTheos/
├── .github/workflows/build.yml   # CI：编译 UnjailTheos.tipa
├── Scripts/build-tipa.sh         # 本地/CI 打包 TIPA 脚本
├── UnjailTheos.xcodeproj/
├── UnjailTheos/                  # 主应用源码
└── RootHelper/                   # Root Helper 二进制
```

---

## 一、GitHub Actions：自动构建 TrollTheos.tipa

本仓库（[cduang/TrollTheos](https://github.com/cduang/TrollTheos)）的 CI **编译 UnjailTheos 应用本身**，产出 **`.tipa`**（TrollStore 侧载包），**不是** Tweak 的 `.deb`。

每次 push 到 `main` 或手动 `workflow_dispatch` 触发后：

```
xcodebuild (Release, iphoneos)
    ↓
ldid 注入 TrollStore entitlements
    ↓
打包 Payload → UnjailTheos.tipa
    ↓
上传 Artifact + GitHub Release
```

### 下载与安装

1. 打开仓库 **Actions** → 最新 Run → Artifacts → `UnjailTheos-tipa-*`
2. 或 **Releases** → 下载 `UnjailTheos.tipa`
3. 用 **TrollStore** 安装到设备

### 本地构建 TIPA

```bash
chmod +x Scripts/build-tipa.sh
./Scripts/build-tipa.sh
# 产物: dist/UnjailTheos.tipa
```

---

## 二、手机端「云端构建」：编译用户 Tweak（.deb）

App 内 **云端构建** Tab 面向 **你的 Tweak 项目**，与上述 TIPA CI **无关**：

1. 在 GitHub 新建 Tweak 仓库
2. 在 App 中填写仓库 URL + PAT（需 `repo` + `workflow` 权限）
3. 点击 **Push to GitHub & Build**
4. App 自动生成 Theos `build.yml` 并 push，云端编译出 `.deb`

PAT 申请：[GitHub Settings → Tokens](https://github.com/settings/tokens)

---

## 三、国内网络加速（gh-proxy）

App 默认开启 **GitHub 加速模式**，通过 `https://v4.gh-proxy.org/` 代理 Theos/SDK 下载。

可在 **环境** Tab 或 **云端构建** Tab 关闭。

实现位置：`NetworkConfig.swift` → `TheosInstaller.swift` / `SDKGitFetcher.swift`

---

## 四、本地 Tweak 编译（设备端）

若设备已安装 Theos 和 SDK，可在 **构建** Tab 执行 `make package`：

```
Documents/theos/          ← THEOS 根目录
Documents/theos/sdks/     ← iPhoneOS SDK
```

---

## 闭环开发流程

```
TrollStore 安装 UnjailTheos.tipa（本仓库 CI 产物）
    ↓
手机编写 Tweak (.xm / Makefile)
    ↓
本地 make package 或 云端构建 push → .deb
    ↓
安装 Tweak → 测试 → 迭代
```

## 许可证

MIT
