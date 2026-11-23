#!/usr/bin/env bash
# 开工：从 develop 拉需求分支，建同名 worktree，软链被忽略的文件。
# 用法：tools/req-start.sh PEEK-12 短标题

source "$(dirname "$0")/req-lib.sh"

[ $# = 2 ] || die "用法：tools/req-start.sh $REQ_PREFIX-12 短标题"
req="$1"
title="$2"
check_req "$req"
check_title "$title"

branch="$req-$title"
dir="$PARENT_DIR/$req"
[ -z "$(req_branches "$req")" ] || die "$req 已有分支：$(req_branches "$req")"
[ ! -e "$dir" ] || die "目录已存在：$dir"

git worktree add -b "$branch" "$dir" "$DEVELOP_REF"
link_ignored "$dir"
gen_project "$dir"

info "已就绪：${dir}（分支 ${branch}）"
echo "提交信息以 $req 开头。完成后运行 tools/req-to-test.sh $req"
