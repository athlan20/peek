#!/usr/bin/env bash
# req-*.sh 共用函数。流程说明见 docs/dev-test-workflow.md。
# 兼容 macOS 自带的 bash 3.2：不用关联数组和 mapfile；紧贴中文的变量要写成 ${var}，否则全角字符会被吃进变量名。

set -euo pipefail

REQ_PREFIX="PEEK"
# 工程里可能有 test/ 目录（如 Tests/ 的小写变体），裸写 test 在 git 里有歧义，一律用完整引用名
TEST_REF="refs/heads/test"
DEVELOP_REF="refs/heads/develop"

# 被 gitignore 但开发要用的文件，软链到新 worktree，只维护 develop/ 这一份
LINKED_PATHS="CLAUDE.local.md"

MAIN_DIR="$(git worktree list --porcelain | sed -n '1s/^worktree //p')"
[ -n "$MAIN_DIR" ] || { echo "错误：请在 peek 仓库内运行" >&2; exit 1; }
PARENT_DIR="$(dirname "$MAIN_DIR")"
TEST_DIR="$PARENT_DIR/test"
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { echo "错误：$*" >&2; exit 1; }
info() { echo "== $*"; }

check_req() {
  echo "$1" | grep -Eq "^$REQ_PREFIX-[0-9]+$" || die "需求号格式应为 $REQ_PREFIX-数字，收到：$1"
}

# 短标题：汉字、字母、数字、-、_，1 到 20 字
check_title() {
  perl -CA -e 'exit($ARGV[0] =~ /\A[\p{Han}A-Za-z0-9_-]{1,20}\z/ ? 0 : 1)' -- "$1" \
    || die "短标题只能用汉字、字母、数字、-、_，不超过 20 字，收到：$1"
}

# 需求号对应的分支，不存在时输出空。PEEK-2-* 不会匹配 PEEK-29-*
req_branches() {
  git for-each-ref --format='%(refname:lstrip=2)' "refs/heads/$1-*"
}

req_branch() {
  local found count
  found="$(req_branches "$1")"
  [ -n "$found" ] || die "找不到 $1 的分支，先运行 tools/req-start.sh"
  count="$(echo "$found" | wc -l | tr -d ' ')"
  [ "$count" = 1 ] || die "$1 对应多个分支：$found"
  echo "$found"
}

# 分支所在的 worktree 路径，没有检出时输出空
worktree_of() {
  git worktree list --porcelain | awk -v want="branch refs/heads/$1" '
    /^worktree / { dir = substr($0, 10) }
    $0 == want { print dir; exit }'
}

develop_dir() {
  local dir
  dir="$(worktree_of develop)"
  [ -n "$dir" ] || die "develop 没有检出，先运行：git -C $MAIN_DIR worktree add $PARENT_DIR/develop develop"
  echo "$dir"
}

# 只看已跟踪文件：测试目录里的临时文件等未跟踪文件不挡合并
ensure_clean() {
  [ -z "$(git -C "$1" status --porcelain --untracked-files=no)" ] \
    || die "$1 有未提交的改动，先提交或还原：
$(git -C "$1" status --short --untracked-files=no)"
}

ensure_no_merge() {
  if git -C "$1" rev-parse -q --verify MERGE_HEAD >/dev/null; then
    die "$1 还有未完成的合并，解决冲突并 git commit 后再重跑"
  fi
}

warn_untracked() {
  local files
  files="$(git -C "$1" ls-files --others --exclude-standard)"
  [ -z "$files" ] || { echo "注意：$1 有未跟踪文件，不会进入合并："; echo "$files" | sed 's/^/  /'; }
}

is_ancestor() { git merge-base --is-ancestor "$1" "$2"; }

link_ignored() {
  local dir="$1" src path
  src="$(develop_dir)"
  [ "$dir" != "$src" ] || return 0
  for path in $LINKED_PATHS; do
    [ -e "$src/$path" ] || continue
    [ -e "$dir/$path" ] || [ -L "$dir/$path" ] && continue
    mkdir -p "$(dirname "$dir/$path")"
    ln -s "$src/$path" "$dir/$path"
  done
}

# 有 project.yml 时用 XcodeGen 生成 Peek.xcodeproj（不进版本库，新 worktree 里没有）
gen_project() {
  local dir="$1"
  [ -f "$dir/project.yml" ] || return 0
  if command -v xcodegen >/dev/null 2>&1; then
    (cd "$dir" && xcodegen generate --quiet) || die "$dir 生成工程失败，检查 project.yml"
  else
    echo "注意：没装 xcodegen，$dir 里还没有 Peek.xcodeproj。运行 brew install xcodegen 后在该目录执行 xcodegen generate"
  fi
}

# merge_or_stop 目录 来源引用 合并提交信息 冲突时的下一步说明
merge_or_stop() {
  local dir="$1" ref="$2" message="$3" next="$4"
  git -C "$dir" merge --no-ff -m "$message" "$ref" && return 0
  git -C "$dir" rev-parse -q --verify MERGE_HEAD >/dev/null || die "合并失败，见上方 git 输出"
  echo >&2
  echo "合并冲突，已停在 ${dir}：" >&2
  git -C "$dir" diff --name-only --diff-filter=U | sed 's/^/  /' >&2
  echo "固定冲突文件的解法见 docs/dev-test-workflow.md 的“固定冲突文件”。" >&2
  echo "$next" >&2
  exit 2
}

# 合并后的快速校验：能编译通过。不代替功能测试。
# 校验方式按优先级：目录里的 tools/verify.sh（工程定了构建命令后在这里写）→ Package.swift 时 swift build → 跳过。
verify() {
  local dir="$1" log missing
  info "校验 $dir"

  # 仓库用 git-lfs 时，检查素材是否只有指针没有内容
  if command -v git-lfs >/dev/null 2>&1; then
    missing="$(git -C "$dir" lfs ls-files 2>/dev/null | awk '$2 == "-" { $1 = $2 = ""; print substr($0, 3) }')"
    [ -z "$missing" ] || die "$dir 有 LFS 文件只有指针没有内容，先在该目录运行 git lfs pull：
$(echo "$missing" | sed 's/^/  /')"
  fi

  log="$(mktemp -t peek-verify)"
  if [ -x "$dir/tools/verify.sh" ]; then
    "$dir/tools/verify.sh" "$dir" >"$log" 2>&1 \
      || { tail -40 "$log" >&2; die "$dir 校验失败（tools/verify.sh），完整日志：$log"; }
  elif [ -f "$dir/Package.swift" ]; then
    (cd "$dir" && swift build) >"$log" 2>&1 \
      || { tail -40 "$log" >&2; die "$dir swift build 失败，完整日志：$log"; }
  else
    echo "（还没有可校验的工程：没有 tools/verify.sh 和 Package.swift，跳过构建校验）"
  fi
  rm -f "$log"
}
