#!/usr/bin/env bash
# 构建校验：生成工程并编译 Debug。req-to-test.sh、req-finish.sh 提测和合入前会自动调用，也可以手动运行。
# 用法：tools/verify.sh [工程目录]，不传就用脚本所在的工程。
# 只编译 Debug（临时签名，不需要证书）。Release 要用团队的自签名证书，见 docs/signing.md。

set -euo pipefail

dir="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$dir"

command -v xcodegen >/dev/null 2>&1 || { echo "错误：没装 xcodegen，先运行 brew install xcodegen" >&2; exit 1; }
command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1 \
  || { echo "错误：没有可用的 Xcode，装好后运行 sudo xcode-select -s /Applications/Xcode.app" >&2; exit 1; }

xcodegen generate --quiet
xcodebuild -project Peek.xcodeproj -scheme Peek -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$dir/DerivedData" -quiet build
echo "校验通过：$dir"
