#!/bin/bash
# 빌드 번호 올리기: App Store Connect에 올릴 때마다 한 번 실행해요.
#
#   bash scripts/bump-build.sh            빌드 번호 +1
#   bash scripts/bump-build.sh 1.1        버전을 1.1로 바꾸고 빌드 번호 +1
#   bash scripts/bump-build.sh --build 7  빌드 번호를 7로 맞추기 (이미 더 큰 번호를 올렸을 때)
#
# 번호는 git이 무시하는 I4A/Config/Local.xcconfig에 저장돼서 git pull을 막지 않아요.
# 지금까지 쓴 번호는 I4A/Config/build-history.txt에 남아서, 다음에도 그다음 번호부터 이어가요.
# 빌드 번호는 버전이 바뀌어도 줄이지 않고 계속 올려요(App Store Connect는 같은 번호를 다시 받지 않아요).

set -euo pipefail

main() {

info() { printf '  %s\n' "$*"; }
fail() { printf '\n\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || fail "I4A 레포 폴더 안에서 실행해 주세요."
cd "$ROOT"

LOCAL=I4A/Config/Local.xcconfig
BASE=I4A/Config/Base.xcconfig
HISTORY=I4A/Config/build-history.txt
PBXPROJ=I4A.xcodeproj/project.pbxproj

new_version=""
forced_build=""
case "${1:-}" in
  "") ;;
  --build)
    forced_build=${2:-}
    [[ "$forced_build" =~ ^[0-9]+$ ]] || fail "빌드 번호는 숫자로 주세요. 예: bash scripts/bump-build.sh --build 7"
    ;;
  -h|--help)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  *)
    new_version=$1
    [[ "$new_version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || fail "버전은 1.1이나 1.2.3처럼 주세요."
    ;;
esac

# The last value of KEY in a file, or nothing.
value_of() {
  [ -f "$2" ] || return 0
  sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\";]*\)\"\{0,1\};\{0,1\}[[:space:]]*$/\1/p" "$2" | tail -n 1
}

# Sets `KEY = value` in Local.xcconfig, replacing an existing line for KEY.
set_local() {
  local key=$1 value=$2 tmp
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
}

max() { if [ "${1:-0}" -ge "${2:-0}" ]; then echo "${1:-0}"; else echo "${2:-0}"; fi; }
number_or_zero() { [[ "${1:-}" =~ ^[0-9]+$ ]] && echo "$1" || echo 0; }

version=$(value_of MARKETING_VERSION "$LOCAL")
[ -n "$version" ] || version=$(value_of MARKETING_VERSION "$BASE")

# The highest build number known anywhere: Local.xcconfig, the shared
# default, the history, and a number typed into Xcode's General tab.
current=$(number_or_zero "$(value_of CURRENT_PROJECT_VERSION "$LOCAL")")
current=$(max "$current" "$(number_or_zero "$(value_of CURRENT_PROJECT_VERSION "$BASE")")")
if [ -f "$HISTORY" ]; then
  last=$(awk '{ n = $NF; gsub(/[()]/, "", n); if (n ~ /^[0-9]+$/ && n + 0 > m) m = n + 0 } END { print m + 0 }' "$HISTORY")
  current=$(max "$current" "$last")
fi
xcode_build=$(number_or_zero "$(value_of CURRENT_PROJECT_VERSION "$PBXPROJ")")
current=$(max "$current" "$xcode_build")
xcode_version=$(value_of MARKETING_VERSION "$PBXPROJ")

# A version or build typed into Xcode's General tab goes into the project
# file and would override Local.xcconfig. Take it over and drop it there.
if [ "$xcode_build" != 0 ] || [ -n "$xcode_version" ]; then
  [ -n "$xcode_version" ] && [ -z "$new_version" ] && version=$xcode_version
  perl -i -ne 'print unless /^\s*(CURRENT_PROJECT_VERSION|MARKETING_VERSION) = /' "$PBXPROJ"
  info "Xcode에서 직접 바꾼 버전/빌드 번호를 Local.xcconfig로 옮겼어요."
fi

if [ -n "$forced_build" ]; then
  build=$forced_build
  if [ "$build" -le "$current" ]; then
    info "주의: $build 은(는) 지금까지 쓴 번호($current)보다 크지 않아요. App Store Connect에 이미 있는 번호면 업로드가 거절돼요."
  fi
else
  build=$((current + 1))
fi
[ -n "$new_version" ] && version=$new_version

set_local MARKETING_VERSION "$version"
set_local CURRENT_PROJECT_VERSION "$build"
printf '%s  %s (%s)\n' "$(date '+%Y-%m-%d %H:%M')" "$version" "$build" >> "$HISTORY"

printf '\n\033[1m%s\033[0m\n' "버전 $version, 빌드 $build"
info "이전 빌드 번호: $current"
info "저장: $LOCAL"
if [ "$(wc -l < "$HISTORY" | tr -d ' ')" -gt 1 ]; then
  info "최근 기록 ($HISTORY):"
  tail -n 5 "$HISTORY" | while IFS= read -r line; do info "  $line"; done
fi
echo
info "Xcode에서 Product → Archive 하면 이 번호로 만들어져요."
}

main "$@"
exit
