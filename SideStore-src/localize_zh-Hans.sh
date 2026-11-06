#!/bin/bash
# localize_zh-Hans.sh — 编译后用 ibtool 把中文 storyboard/xib 字符串烘焙进 nib
#
# 背景: Xcode 的 PBXVariantGroup 在这个项目里只走了"提取"阶段
# (ibtool 收到了 --companion-strings-file, 但只生成了 Base.lproj 的
# storyboardc, 没有生成 zh-Hans.lproj 的本地化编译产物)。
# 这里在 make build 之后、make ipa 之前, 直接调用 ibtool --compile
# --strings-file, 为每个 storyboard/xib 生成 zh-Hans.lproj 下的本地化
# storyboardc/nib, 再删掉散落在包里的 .strings(已烘焙进 nib, 留着无用)。
# 在 SideStore-src/ 目录下运行。任一步失败即退出, 不让坏包继续打包。
set -euo pipefail

APP="SideStore.xcarchive/Products/Applications/SideStore.app"
[ -d "$APP" ] || { echo "ERROR: $APP not found (run after make build)"; exit 1; }

compile_storyboard() { # $1=base storyboard, $2=strings file
  local name; name="$(basename "$1" .storyboard)"
  ibtool --errors --warnings --notices --module SideStore \
    --target-device iphone --target-device ipad \
    --minimum-deployment-target 15.0 --output-format human-readable-text \
    --compile "$APP/zh-Hans.lproj/$name.storyboardc" \
    --strings-file "$2" "$1"
}

compile_xib() { # $1=base xib, $2=strings file
  local name; name="$(basename "$1" .xib)"
  ibtool --errors --warnings --notices --module SideStore \
    --target-device iphone --target-device ipad \
    --minimum-deployment-target 15.0 --output-format human-readable-text \
    --compile "$APP/zh-Hans.lproj/$name.nib" \
    --strings-file "$2" "$1"
}

mkdir -p "$APP/zh-Hans.lproj"

compile_storyboard "AltStore/iOS/Base.lproj/Main.storyboard"           "AltStore/iOS/zh-Hans.lproj/Main.strings"
compile_storyboard "AltStore/Settings/Base.lproj/Settings.storyboard"   "AltStore/Settings/zh-Hans.lproj/Settings.strings"
compile_storyboard "AltStore/Authentication/Base.lproj/Authentication.storyboard" "AltStore/Authentication/zh-Hans.lproj/Authentication.strings"
compile_storyboard "AltStore/Sources/Base.lproj/Sources.storyboard"     "AltStore/Sources/zh-Hans.lproj/Sources.strings"
compile_xib "AltStore/Components/Base.lproj/AppBannerView.xib"                          "AltStore/Components/zh-Hans.lproj/AppBannerView.strings"
compile_xib "AltStore/My Apps/Base.lproj/InstalledAppsCollectionHeaderView.xib"         "AltStore/My Apps/zh-Hans.lproj/InstalledAppsCollectionHeaderView.strings"
compile_xib "AltStore/Settings/Base.lproj/SettingsHeaderFooterView.xib"                 "AltStore/Settings/zh-Hans.lproj/SettingsHeaderFooterView.strings"
compile_xib "AltStore/Settings/Base.lproj/AboutPatreonHeaderView.xib"                   "AltStore/Settings/zh-Hans.lproj/AboutPatreonHeaderView.strings"

# 删掉已烘焙的 storyboard/xib .strings 散文件, 只留 Localizable.strings
rm -f "$APP/zh-Hans.lproj"/Main.strings "$APP/zh-Hans.lproj"/Settings.strings \
      "$APP/zh-Hans.lproj"/Authentication.strings "$APP/zh-Hans.lproj"/Sources.strings \
      "$APP/zh-Hans.lproj"/AppBannerView.strings \
      "$APP/zh-Hans.lproj"/InstalledAppsCollectionHeaderView.strings \
      "$APP/zh-Hans.lproj"/SettingsHeaderFooterView.strings \
      "$APP/zh-Hans.lproj"/AboutPatreonHeaderView.strings

# 严格校验: 本地化 nib 里必须出现中文, 否则失败, 不打包坏包
check() { # $1=中文串 $2=位置
  grep -rl "$1" "$2" >/dev/null || { echo "ERROR: '$1' not found in $2"; exit 1; }
}
check "续签记录"   "$APP/zh-Hans.lproj/Settings.storyboardc"
check "后台续签"   "$APP/zh-Hans.lproj/Settings.storyboardc"
check "开发者门户服务" "$APP/zh-Hans.lproj/Settings.storyboardc"
check "我的应用"   "$APP/zh-Hans.lproj/Main.storyboardc"
check "来源"       "$APP/zh-Hans.lproj/Sources.storyboardc"
echo "OK: zh-Hans nibs baked with Chinese strings:"
ls "$APP/zh-Hans.lproj/"
