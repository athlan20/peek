# 安装 Peek

Peek 是一个 macOS 菜单栏小工具：看系统状态、清理磁盘、卸载 App。需要 macOS 14 或更高版本。

Peek 没有走苹果的公证，所以**第一次打开会被系统拦一下**，这是正常的，按下面做一次就好。

## 安装

1. 下载 `Peek-<版本>.dmg`，双击打开。
2. 把 `Peek` 拖进旁边的 `Applications`（应用程序）文件夹。
3. 在“应用程序”里双击 `Peek`。

## 第一次打开被拦住

macOS 会弹出“无法打开 Peek，因为 Apple 无法检查其是否包含恶意软件”之类的提示：

1. 点“完成”（不要点“移到废纸篓”）。
2. 打开 **系统设置 → 隐私与安全性**，向下滚动到“安全性”，会看到一行关于 Peek 的提示。
3. 点 **仍要打开**，输入密码或用触控 ID 确认。
4. 再次打开 Peek，在弹窗里点“打开”。

之后就不会再被拦了。

### 没有“仍要打开”按钮时

打开“终端”，运行下面这一行，再双击 Peek：

```bash
xattr -dr com.apple.quarantine /Applications/Peek.app
```

这一行只是去掉下载时系统给文件打的“来自网络”标记，不会改动 Peek 本身。

## 可选：完全磁盘访问

不授权 Peek 照样能用。授权后能多清理：Safari 缓存、沙盒 App 的缓存，并能显示废纸篓的大小。

**系统设置 → 隐私与安全性 → 完全磁盘访问**，点“+”加入 Peek，或把 Peek 的开关打开。第一次启动的引导页里也有按钮直接带你过去。

## 之后会弹的授权

- 第一次让 Peek 查看“下载”文件夹（找安装包）时，系统会请你允许访问“下载”。
- 第一次清空废纸篓时，系统会请你允许 Peek 控制“访达”。

拒绝只会让对应的那一项不可用，别的功能不受影响。

## 升级

直接用新版本替换 `/Applications` 里的 Peek。授权会保留，不用重新给。（前提是新旧版本用的是同一张签名证书，我们会保证这一点。）

## 卸载 Peek

先退出 Peek，把它从“应用程序”拖进废纸篓。Peek 的少量数据在 `~/Library/Application Support/Peek`（清理和卸载的历史记录），想彻底清掉可以一并删除。

---

# Installing Peek (English)

Peek is a small menu bar app for macOS 14 or later: check system health, clean up disk space, uninstall apps. It isn’t notarized by Apple, so macOS blocks it the first time you open it. That’s expected.

1. Open `Peek-<version>.dmg` and drag `Peek` into `Applications`.
2. Open Peek from Applications. If macOS blocks it, click Done.
3. Open **System Settings → Privacy & Security**, scroll to the Security section, and click **Open Anyway** next to the Peek message. Confirm with your password or Touch ID.
4. Open Peek again and click Open.

If there is no “Open Anyway” button, run this in Terminal and open Peek again:

```bash
xattr -dr com.apple.quarantine /Applications/Peek.app
```

**Optional:** Full Disk Access (Privacy & Security → Full Disk Access) lets Peek also clean Safari’s cache and sandboxed apps’ caches, and show the Trash size. Peek works fine without it.

**Updating:** replace Peek in Applications with the new version. Your permissions are kept as long as releases are signed with the same certificate.
