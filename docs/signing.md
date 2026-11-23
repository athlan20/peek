# 签名

Peek 不走 Apple 开发者账号和公证，用一张团队固定的**自签名证书**签名，证书名称固定为 `Peek Self-Signed`。

## 为什么必须固定一张证书

系统按"Bundle ID + 签名证书"认 App。用户给 Peek 的"完全磁盘访问"等授权，记在这个身份上：

- 换一张证书（哪怕名字一样）签出来的新版本，在系统眼里就是另一个 App，用户升级后授权全部丢失
- 临时签名（ad-hoc）每次构建身份都会变，所以正式版不能用

因此正式版（Release）**永远只用同一张证书**，证书和私钥要妥善备份。

## 各构建用什么签名

| 构建 | Bundle ID | 签名 | 配置 |
|---|---|---|---|
| Debug（开发） | `cc.yuntianyou.peek.dev` | 默认临时签名，没有证书也能编译 | `Config/Debug.xcconfig` |
| Release（发给用户） | `cc.yuntianyou.peek` | `Peek Self-Signed` | `Config/Release.xcconfig` |

`tools/verify.sh` 只编译 Debug，所以没有证书也能通过校验。

## 第一次创建证书（只做一次，由负责人做）

1. 打开"钥匙串访问"，菜单选"钥匙串访问 → 证书助理 → 创建证书…"
2. 名称填 `Peek Self-Signed`，身份类型选"自签名根证书"，证书类型选"代码签名"
3. **勾选"让我覆盖这些默认值"**，有效期改长，比如 7300 天（20 年）。默认只有 365 天，过期后换证书会让所有用户的授权丢失
4. 其余页面保持默认，钥匙串选"登录"，完成
5. 检查能不能用：

   ```bash
   security find-identity -p codesigning   # 能看到 "Peek Self-Signed"
   ```

   如果后面签名时提示证书不受信任，在钥匙串里双击这张证书，"信任 → 代码签名"改成"始终信任"。

## 备份和交接

- 在钥匙串里右键证书 → 导出，存成 `.p12`，设一个强密码
- `.p12` 和密码放进团队的密码管理器，**不要提交到仓库，不要发群里**
- 负责打包正式版的人，双击 `.p12` 导入自己的"登录"钥匙串即可
- 证书丢了就无法再发能保留授权的更新，必须备份

## 开发时想让授权不丢

Debug 默认是临时签名，每次构建后"完全磁盘访问"等授权都会失效。开发要反复测授权相关功能时：

1. 钥匙串里要有一张叫 `Peek Self-Signed` 的证书：导入团队的 `.p12`，或按上面步骤自己建一张同名的（只用于本机开发）
2. 新建 `Config/Signing.local.xcconfig`（已在 `.gitignore` 里，不进版本库），写一行：

   ```
   PEEK_SIGN_IDENTITY = Peek Self-Signed
   ```

3. 重新运行 `xcodegen generate` 再构建

Debug 和 Release 的 Bundle ID 不同，开发版拿到的授权和正式版互不影响。

## 检查签名

```bash
codesign -dv --verbose=2 Peek.app 2>&1 | grep -E 'Identifier|Authority|Signature'
```

正式版应该看到 `Authority=Peek Self-Signed`；Debug 默认显示 `Signature=adhoc`。

## 打包

```bash
tools/package.sh            # 正式打包：需要 "Peek Self-Signed" 证书，产物在 dist/
tools/package.sh --adhoc    # 临时签名试流程，产物不能发给用户
```

脚本会编译 Release、校验签名身份和 Bundle ID（必须是 `cc.yuntianyou.peek`）、生成 `.dmg` 和 `.zip`，并打印 SHA-256。给用户的安装说明见 `docs/install.md`。

## 发版前的验收（需要真机，脚本替代不了）

1. 在**另一台 Mac 或新建的用户账户**上，从下载 dmg 开始，按 `docs/install.md` 走一遍，确认能正常打开。
2. 给 Peek 授权“完全磁盘访问”，再装一个**同证书签名的新版本**覆盖，确认授权仍然有效。
3. `codesign -dv --verbose=2 /Applications/Peek.app` 里看到 `Authority=Peek Self-Signed`。
