# UnjailTheos

iOS 本地 Theos 编译器 GUI，面向 TrollStore（巨魔）侧载环境（iOS 15.0+）。支持手机端本地编译、GitHub Actions 云端编译，以及国内网络 gh-proxy 加速。

## 功能概览

| 模块 | 功能 |
|------|------|
| **环境** | 自动安装 Theos、下载/导入 iPhoneOS SDK、gh-proxy 加速 |
| **编辑器** | Tweak 项目文件树 + Logos/Makefile 语法高亮 |
| **构建** | Root Helper 执行 `make package`，实时日志 |
| **云端构建** | 一键 push 到 GitHub，触发 Actions 编译并发布 Release |

## 项目结构

```
UnjailTheos/
├── .github/workflows/build.yml   # 云端编译 workflow（arm64 + arm64e 双架构）
├── UnjailTheos.xcodeproj/
├── UnjailTheos/                  # 主应用源码
└── RootHelper/                  # Root Helper 二进制
```

---

## 一、申请 GitHub PAT（个人访问令牌）

云端构建需要 GitHub Personal Access Token (PAT)，用于 git push 和触发 Actions。

### 步骤

1. 登录 [GitHub Settings → Developer settings → Personal access tokens](https://github.com/settings/tokens)
2. 点击 **Generate new token (classic)** 或 **Fine-grained token**
3. 勾选以下权限：

**Classic Token 所需 scope：**

| 权限 | 用途 |
|------|------|
| `repo` | 推送代码到私有/公开仓库 |
| `workflow` | 触发 `workflow_dispatch` |

**Fine-grained Token 所需权限：**

- Repository access: 选择你的 Tweak 仓库
- Permissions → Contents: **Read and write**
- Permissions → Actions: **Read and write**
- Permissions → Workflows: **Read and write**

4. 生成后**立即复制 Token**（只显示一次），妥善保存

> 安全提示：不要将 Token 提交到公开仓库。UnjailTheos 仅在本地内存中使用 Token，不会上传至第三方服务器。

---

## 二、手机端配置与云端编译

### 1. 准备 GitHub 仓库

在 GitHub 新建一个空仓库，例如：

```
https://github.com/你的用户名/MyTweak
```

### 2. 在 UnjailTheos 中配置

1. 打开 **云端构建** Tab
2. 选择本地 Tweak 项目文件夹
3. 填写：
   - **仓库 URL**：`https://github.com/你的用户名/MyTweak`
   - **分支**：`main`（或 `master`）
   - **Personal Access Token**：粘贴上一步申请的 PAT
4. （可选）开启 **GitHub 加速模式**（影响 Theos/SDK 下载，不影响 git push）

### 3. 一键推送 → 云端编译

点击 **Push to GitHub & Build**，App 将自动：

```
生成 .github/workflows/build.yml
    ↓
git init + commit 本地更改
    ↓
HTTPS + PAT 推送到 GitHub
    ↓
REST API 触发 workflow_dispatch
    ↓
GitHub Actions (macos-latest) 编译
    ↓
上传 Artifact + 创建 Release
```

### 4. 下载 .deb 包

编译成功后，有两种下载方式：

- **GitHub Releases**：仓库 → Releases → 最新 `UnjailTheos Build YYYY-MM-DD_HH-MM-SS`
- **GitHub Actions Artifacts**：仓库 → Actions → 最新 Run → Artifacts → `tweak-packages-*`

### 5. 安装到设备

- **arm64e / rootless `.deb`**：使用 TrollStore 或 Sileo（rootless）安装
- **arm64 传统 `.deb`**：适用于传统越狱环境

---

## 三、云端编译架构说明

`.github/workflows/build.yml` 会自动：

1. 在 `macos-latest` 克隆 Theos，并通过 git sparse-checkout 拉取 `iPhoneOS14.5.sdk`
2. 读取 Tweak 项目 `Makefile` 中的 `ARCHS` 字段
3. 分别编译：
   - `arm64` → `THEOS_PACKAGE_SCHEME=deb`（传统越狱）
   - `arm64e` → `THEOS_PACKAGE_SCHEME=rootless`（巨魔 / Rootless）
4. 上传 `.deb` 到 Artifact 并创建带时间戳的 Release

Makefile 示例：

```makefile
ARCHS = arm64 arm64e
TARGET = iphone:clang:14.5:14.5
```

---

## 四、国内网络加速（gh-proxy）

首次启动时，App 默认开启 **GitHub 加速模式**，通过 `https://v4.gh-proxy.org/` 代理 GitHub 下载：

| 原始 URL | 加速后 |
|---------|--------|
| `https://github.com/theos/theos/...` | `https://v4.gh-proxy.org/https://github.com/theos/theos/...` |
| `https://raw.githubusercontent.com/...` | `https://v4.gh-proxy.org/https://raw.githubusercontent.com/...` |

可在 **环境** Tab 或 **云端构建** Tab 关闭加速模式。

实现位置：`NetworkConfig.swift` → `TheosInstaller.swift` / `SDKGitFetcher.swift`

---

## 五、本地编译（可选）

若设备已安装 Theos 和 SDK，可在 **构建** Tab 直接执行 `make package`，日志通过 Root Helper Pipe 实时输出。

Theos 目录：

```
Documents/theos/          ← THEOS 根目录
Documents/theos/sdks/     ← iPhoneOS SDK
```

---

## 六、开发者构建 App

1. macOS + Xcode 15+
2. 打开 `UnjailTheos.xcodeproj`
3. 配置签名，Deployment Target iOS 15.0
4. Release 构建后通过 TrollStore 侧载

---

## 闭环开发流程总结

```
手机编写 Tweak (.xm / Makefile)
    ↓
本地编译（构建 Tab）或 云端编译（云端构建 Tab）
    ↓
GitHub Actions 自动编译 arm64 + arm64e
    ↓
手机浏览器打开 GitHub Releases 下载 .deb
    ↓
TrollStore 安装 → 测试 → 迭代
```

全程无需 Mac 电脑、无需传统越狱。

## 许可证

MIT
