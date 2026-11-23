#!/usr/bin/env bash
# 打包：分别编译 arm64 与 x86_64 单架构 Release，用固定的自签名证书签名，
# 生成 dist/Peek-<版本>-arm64.{dmg,zip} 和 dist/Peek-<版本>-x86_64.{dmg,zip}。
# 用法：
#   tools/package.sh                    正式打包 arm64 + x86_64 两份单架构包（需 "Peek Self-Signed" 证书）
#   tools/package.sh --arch arm64       只打 Apple Silicon 单架构包
#   tools/package.sh --arch x86_64      只打 Intel 单架构包
#   tools/package.sh --adhoc            临时签名试流程，**不能发给用户**
# 产物在 dist/（不进版本库）。

set -euo pipefail

adhoc=0
arch_mode="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --adhoc) adhoc=1; shift ;;
    --arch)
      [[ $# -ge 2 ]] || { echo "错误：--arch 需要指定 arm64 / x86_64 / all" >&2; exit 2; }
      arch_mode="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

case "$arch_mode" in
  all)    archs=("arm64" "x86_64") ;;
  arm64)  archs=("arm64") ;;
  x86_64) archs=("x86_64") ;;
  *) echo "错误：不支持的架构 $arch_mode（可选：arm64 / x86_64 / all）" >&2; exit 2 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
identity="Peek Self-Signed"

command -v xcodegen >/dev/null 2>&1 || { echo "错误：没装 xcodegen，先运行 brew install xcodegen" >&2; exit 1; }

sign_args=()
if [[ $adhoc -eq 1 ]]; then
  echo "== 注意：临时签名，仅用于试打包，不能发给用户"
  sign_args=("PEEK_SIGN_IDENTITY=-")
else
  if ! security find-identity -p codesigning | grep -q "\"$identity\""; then
    echo "错误：钥匙串里找不到证书 \"$identity\"。" >&2
    echo "先按 docs/signing.md 创建或导入团队的证书；只是试流程可以加 --adhoc。" >&2
    exit 1
  fi
fi

echo "== 生成工程"
xcodegen generate --quiet
mkdir -p dist

artifacts=()

for arch in "${archs[@]}"; do
  echo "== 编译 Release ($arch)"
  derived="build/release-$arch"
  rm -rf "$derived"
  xcodebuild -project Peek.xcodeproj -scheme Peek -configuration Release \
    -destination "platform=macOS,arch=$arch" \
    ARCHS="$arch" ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath "$derived" -quiet ${sign_args[@]+"${sign_args[@]}"} build

  app="$derived/Build/Products/Release/Peek.app"
  [[ -d "$app" ]] || { echo "错误：没有找到编译产物 $app" >&2; exit 1; }

  echo "== 校验架构与签名 ($arch)"
  built_archs="$(lipo -archs "$app/Contents/MacOS/Peek")"
  [[ "$built_archs" == "$arch" ]] \
    || { echo "错误：期望单架构 $arch，实际得到 $built_archs" >&2; exit 1; }

  codesign --verify --deep --strict "$app"
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
  if [[ "$bundle_id" != "cc.yuntianyou.peek" ]]; then
    echo "错误：Bundle ID 是 $bundle_id，正式版必须是 cc.yuntianyou.peek" >&2
    exit 1
  fi
  if [[ $adhoc -eq 0 ]]; then
    authority="$(codesign -dv --verbose=2 "$app" 2>&1 | grep '^Authority=' | head -1)"
    [[ "$authority" == "Authority=$identity" ]] \
      || { echo "错误：签名身份不是 $identity（得到：${authority:-无}）" >&2; exit 1; }
  fi

  echo "== 打包 ($arch · App $(du -sh "$app" | awk '{print $1}'))"
  name="Peek-$version-$arch"
  rm -rf "dist/$name.dmg" "dist/$name.zip" build/dmg
  ditto -c -k --keepParent "$app" "dist/$name.zip"
  mkdir -p build/dmg
  cp -R "$app" build/dmg/Peek.app
  ln -s /Applications build/dmg/Applications
  # macOS 14+ 原生支持 ULMO (LZMA)，比 UDZO 体积更小
  hdiutil create -quiet -volname "Peek" -srcfolder build/dmg -ov -format ULMO "dist/$name.dmg"
  rm -rf build/dmg

  artifacts+=("dist/$name.dmg" "dist/$name.zip")
done

echo "== 完成"
ls -lh "${artifacts[@]}"
shasum -a 256 "${artifacts[@]}"
[[ $adhoc -eq 1 ]] && echo "（这是临时签名的试打包，不要发给用户）"
exit 0
