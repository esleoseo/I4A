#!/bin/bash
# I4A 업데이트: 최신 코드를 받아요. 어느 폴더에서 실행해도 레포 맨 위로 이동해서 돌아요.
#
#   bash scripts/mac-update.sh
#
# 1. Xcode가 바꿔 놓은 파일(프로젝트 파일, 스킴)을 되돌려요. 그 전에 그 안에 있던
#    개인 설정(서명 Team, 번들 ID)을 I4A/Config/Local.xcconfig로 옮겨 둬요.
# 2. 그 밖에 직접 고친 파일이 있으면 지우지 않고 멈추고, 되돌리는 방법을 알려 줘요.
# 3. git pull로 최신 코드를 받아요.
# 4. 개인 설정(Local.xcconfig)이 제대로 있는지 보여 줘요.

set -euo pipefail

# git pull below can rewrite this very file while it runs, and bash reads
# scripts as it goes. Wrapping everything in a function makes bash read the
# whole script before running any of it.
main() {

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || fail "I4A 레포 폴더 안에서 실행해 주세요."
cd "$ROOT"
[ -f I4A.xcodeproj/project.pbxproj ] || fail "I4A 레포가 아니에요: $ROOT"

PBXPROJ=I4A.xcodeproj/project.pbxproj
SHARED=I4A.xcodeproj/xcshareddata
ADMIN_SWIFT=I4A/AdminSync.swift
LOCAL=I4A/Config/Local.xcconfig
DEFAULT_BUNDLE_ID=com.esleoseo.i4a

# Sets `KEY = value` in Local.xcconfig, replacing an existing line for KEY.
set_local() {
  local key=$1 value=$2 tmp
  mkdir -p "$(dirname "$LOCAL")"
  if [ ! -f "$LOCAL" ]; then
    printf '%s\n' "// 내 설정. git이 무시하는 파일이라 pull을 막지 않아요. (Local.xcconfig.example 참고)" > "$LOCAL"
  fi
  tmp=$(mktemp)
  awk -v k="$key" -v v="$value" '
    $1 == k && $2 == "=" { if (!done) print k " = " v; done = 1; next }
    { print }
    END { if (!done) print k " = " v }
  ' "$LOCAL" > "$tmp"
  mv "$tmp" "$LOCAL"
  info "개인 설정 저장: $key = $value"
}

modified() { ! git diff --quiet HEAD -- "$1" 2>/dev/null; }

if pgrep -x Xcode >/dev/null 2>&1; then
  info "Xcode가 열려 있어요. 업데이트가 끝나면 Xcode를 닫았다가 다시 열어 주세요."
fi

# ---------------------------------------------------------------------------
say "1/4 Xcode가 바꾼 파일 정리"

if modified "$PBXPROJ"; then
  team=$(sed -n 's/.*DEVELOPMENT_TEAM = "\{0,1\}\([A-Z0-9]\{10\}\)"\{0,1\};.*/\1/p' "$PBXPROJ" | head -n 1 || true)
  bundle=$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = "\{0,1\}\([A-Za-z0-9.-]\{1,\}\)"\{0,1\};.*/\1/p' "$PBXPROJ" \
    | grep -v '\.tests$' | head -n 1 || true)
  [ -n "$team" ] && set_local DEVELOPMENT_TEAM "$team"
  if [ -n "$bundle" ] && [ "$bundle" != "$DEFAULT_BUNDLE_ID" ]; then
    set_local I4A_BUNDLE_ID "$bundle"
  fi
  git checkout HEAD -- "$PBXPROJ"
  info "되돌림: $PBXPROJ"
fi

if [ -d "$SHARED" ] && modified "$SHARED"; then
  git checkout HEAD -- "$SHARED"
  info "되돌림: $SHARED"
fi

# 예전 버전은 관리자 서버 주소를 AdminSync.swift에 직접 적었어요. 그 줄만 바뀌었으면
# 주소를 Local.xcconfig로 옮기고 파일을 되돌려요.
if [ -f "$ADMIN_SWIFT" ] && modified "$ADMIN_SWIFT"; then
  other=$(git diff HEAD -U0 -- "$ADMIN_SWIFT" | grep '^[-+]' | grep -v '^+++' | grep -v '^---' \
    | grep -v 'serverURL' || true)
  if [ -z "$other" ]; then
    url=$(sed -n 's/.*static let serverURL = "\(.*\)".*/\1/p' "$ADMIN_SWIFT" | head -n 1 || true)
    host=$(printf '%s' "$url" | sed -e 's#^[A-Za-z]*://##' -e 's#/*$##')
    [ -n "$host" ] && set_local I4A_ADMIN_HOST "$host"
    git checkout HEAD -- "$ADMIN_SWIFT"
    info "되돌림: $ADMIN_SWIFT"
  fi
fi

# ---------------------------------------------------------------------------
say "2/4 직접 고친 파일 확인"

changed=$(git diff --name-only HEAD)
if [ -n "$changed" ]; then
  printf '\n\033[33m%s\033[0m\n' "아래 파일에 고친 내용이 남아 있어요. 지우지 않고 여기서 멈출게요."
  printf '%s\n' "$changed" | while IFS= read -r file; do info "- $file"; done
  echo
  info "고친 내용이 필요 없으면 아래처럼 되돌린 뒤 다시 실행하세요."
  printf '%s\n' "$changed" | while IFS= read -r file; do info "git checkout -- \"$file\""; done
  echo
  info "무엇이 바뀌었는지 보려면: git diff"
  exit 1
fi
info "없어요."

# ---------------------------------------------------------------------------
say "3/4 최신 코드 받기 (git pull)"

git pull --ff-only || fail "pull 하지 못했어요. 위의 git 메시지를 확인해 주세요."

# ---------------------------------------------------------------------------
say "4/4 개인 설정 확인 ($LOCAL)"

if [ -f "$LOCAL" ] && grep -q '^[A-Z0-9_]* = ' "$LOCAL"; then
  grep '^[A-Z0-9_]* = ' "$LOCAL" | while IFS= read -r line; do info "$line"; done
else
  info "아직 없어요. Xcode의 Signing & Capabilities에서 Team을 고르면 다음 업데이트 때 자동으로 옮겨져요."
  info "직접 쓰려면: cp I4A/Config/Local.xcconfig.example $LOCAL 후 값을 고치세요."
fi

say "업데이트 완료. Xcode에서 ▶(⌘R)로 다시 설치하세요."
}

main "$@"
exit
