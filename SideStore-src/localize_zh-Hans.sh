#!/bin/bash
# localize_zh-Hans.sh — 编译后用 ibtool 把中文 storyboard/xib 字符串烘焙进 nib
#
# 背景: Xcode 的 PBXVariantGroup 在这个项目里只走了"提取"阶段
# (ibtool 收到了 --companion-strings-file, 但只生成了 Base.lproj 的
# storyboardc, 没有生成 zh-Hans.lproj 的本地化编译产物)。
# 这里在 make build 之后、make ipa 之前, 直接调用 ibtool 生成
# zh-Hans.lproj 下的本地化 storyboardc/nib。
# 在 SideStore-src/ 目录下运行。任一步失败即退出, 不让坏包继续打包。
#
# 关键不确定点: ibtool 到底用哪种调用才能把 .strings 烤进 nib。
# 本脚本先拿 Settings.storyboard 做实验, 对比两种形式, 用胜出的
# 那一种处理全部 8 个文件, 并把两种形式的产物里实际含有的中文
# 都打印到日志里, 以便下一次判断。
set -euo pipefail

APP="SideStore.xcarchive/Products/Applications/SideStore.app"
[ -d "$APP" ] || { echo "ERROR: $APP not found (run after make build)"; exit 1; }

SB="AltStore/Settings/Base.lproj/Settings.storyboard"
ST="AltStore/Settings/zh-Hans.lproj/Settings.strings"
SCRATCH="$(mktemp -d)"
echo "scratch: $SCRATCH"

# 形式 A: --compile + --strings-file
mkdir -p "$SCRATCH/A"
ibtool --errors --warnings --notices --module SideStore \
  --target-device iphone --target-device ipad \
  --minimum-deployment-target 15.0 --output-format human-readable-text \
  --compile "$SCRATCH/A/Settings.storyboardc" \
  --strings-file "$ST" "$SB" || echo "FORM A ibtool exit: $?"

# 形式 B: Xcode 自己的做法 --companion-strings-file + --compilation-directory
mkdir -p "$SCRATCH/B"
ibtool --errors --warnings --notices --companion-strings-file "zh-Hans:$ST" \
  --module SideStore \
  --target-device iphone --target-device ipad \
  --minimum-deployment-target 15.0 --output-format human-readable-text \
  "$SB" --compilation-directory "$SCRATCH/B" || echo "FORM B ibtool exit: $?"
echo "--- form B output tree ---"
find "$SCRATCH/B" | head -30

# 扫描: 打印每个产物里实际含有的中文串(UTF-8 与 UTF-16LE 两种编码都查),
# 并判断 续签记录 / 后台续签 / 开发者门户服务 是否出现
python3 - "$SCRATCH" <<'EOF'
import os, re, sys
root = sys.argv[1]
want = ["续签记录", "后台续签", "开发者门户服务", "我的应用"]
cjk8 = re.compile(r'(?:[\xe4-\xe9][\x80-\xbf][\x80-\xbf]){2,}')
for form in ("A", "B"):
    base = os.path.join(root, form)
    found = {}
    for dp, dn, fn in os.walk(base):
        for f in fn:
            p = os.path.join(dp, f)
            try: d = open(p, 'rb').read()
            except Exception: continue
            for w in want:
                for enc in ("utf-8", "utf-16-le", "utf-16-be"):
                    if w.encode(enc) in d:
                        found.setdefault(w, set()).add(enc)
            # dump readable CJK runs (utf-8)
            try:
                for m in cjk8.finditer(d):
                    s = m.group().decode('utf-8', 'ignore')
                    if len(s) >= 2: found.setdefault("DUMP:" + s, set()).add("utf8")
            except Exception: pass
            # dump CJK runs from utf-16-le decode
            try:
                t = d.decode('utf-16-le', 'ignore')
                for m in re.finditer(r'[\u4e00-\u9fff]{2,}', t):
                    found.setdefault("DUMP:" + m.group(0), set()).add("utf16le")
            except Exception: pass
    print("=== FORM", form, "===")
    for k in sorted(found): print(" ", k, sorted(found[k]))
    ok = all(w in found for w in want[:3])
    print("FORM", form, "HAS_WANTED:", ok)
EOF

# 用胜出的形式处理全部文件; 若 A/B 都不行, 报错退出
pick_form() {
  python3 - "$SCRATCH" <<'EOF'
import os, sys
root = sys.argv[1]
want = ["续签记录", "后台续签", "开发者门户服务"]
for form in ("A", "B"):
    base = os.path.join(root, form)
    ok = True
    for w in want:
        hit = False
        for dp, dn, fn in os.walk(base):
            for f in fn:
                d = open(os.path.join(dp, f), 'rb').read()
                if any(w.encode(e) in d for e in ("utf-8", "utf-16-le", "utf-16-be")):
                    hit = True; break
            if hit: break
        if not hit: ok = False; break
    if ok:
        print(form); sys.exit(0)
print("NONE"); sys.exit(0)
EOF
}
FORM="$(pick_form)"
echo "picked form: $FORM"
[ "$FORM" = "NONE" ] && { echo "ERROR: neither ibtool form baked Chinese into Settings.storyboardc — see dumps above"; exit 1; }

compile_storyboard() { # $1=base storyboard, $2=strings file
  local name; name="$(basename "$1" .storyboard)"
  if [ "$FORM" = "A" ]; then
    ibtool --errors --warnings --notices --module SideStore \
      --target-device iphone --target-device ipad \
      --minimum-deployment-target 15.0 --output-format human-readable-text \
      --compile "$APP/zh-Hans.lproj/$name.storyboardc" \
      --strings-file "$2" "$1"
  else
    local tmp; tmp="$(mktemp -d)"
    ibtool --errors --warnings --notices --companion-strings-file "zh-Hans:$2" \
      --module SideStore \
      --target-device iphone --target-device ipad \
      --minimum-deployment-target 15.0 --output-format human-readable-text \
      "$1" --compilation-directory "$tmp"
    # 形式 B 的产物位置由实验决定: 优先取 $tmp/zh-Hans.lproj/*.storyboardc,
    # 其次取 $tmp/*.storyboardc
    if [ -d "$tmp/zh-Hans.lproj/$name.storyboardc" ]; then
      mkdir -p "$APP/zh-Hans.lproj"
      cp -R "$tmp/zh-Hans.lproj/$name.storyboardc" "$APP/zh-Hans.lproj/"
    elif [ -d "$tmp/$name.storyboardc" ]; then
      mkdir -p "$APP/zh-Hans.lproj"
      cp -R "$tmp/$name.storyboardc" "$APP/zh-Hans.lproj/"
    else
      echo "ERROR: form B produced no $name.storyboardc under $tmp"; find "$tmp"; exit 1
    fi
    rm -rf "$tmp"
  fi
}

compile_xib() { # $1=base xib, $2=strings file
  local name; name="$(basename "$1" .xib)"
  if [ "$FORM" = "A" ]; then
    ibtool --errors --warnings --notices --module SideStore \
      --target-device iphone --target-device ipad \
      --minimum-deployment-target 15.0 --output-format human-readable-text \
      --compile "$APP/zh-Hans.lproj/$name.nib" \
      --strings-file "$2" "$1"
  else
    local tmp; tmp="$(mktemp -d)"
    ibtool --errors --warnings --notices --companion-strings-file "zh-Hans:$2" \
      --module SideStore \
      --target-device iphone --target-device ipad \
      --minimum-deployment-target 15.0 --output-format human-readable-text \
      "$1" --compilation-directory "$tmp"
    if [ -f "$tmp/zh-Hans.lproj/$name.nib" ]; then
      mkdir -p "$APP/zh-Hans.lproj"
      cp "$tmp/zh-Hans.lproj/$name.nib" "$APP/zh-Hans.lproj/"
    elif [ -f "$tmp/$name.nib" ]; then
      mkdir -p "$APP/zh-Hans.lproj"
      cp "$tmp/$name.nib" "$APP/zh-Hans.lproj/"
    else
      echo "ERROR: form B produced no $name.nib under $tmp"; find "$tmp"; exit 1
    fi
    rm -rf "$tmp"
  fi
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

# 严格校验: 本地化 nib 里必须出现中文(UTF-8 或 UTF-16 任一编码), 否则失败
python3 - "$APP" <<'EOF'
import os, sys
app = sys.argv[1]
checks = [
    ("续签记录", "zh-Hans.lproj/Settings.storyboardc"),
    ("后台续签", "zh-Hans.lproj/Settings.storyboardc"),
    ("开发者门户服务", "zh-Hans.lproj/Settings.storyboardc"),
    ("我的应用", "zh-Hans.lproj/Main.storyboardc"),
    ("来源", "zh-Hans.lproj/Sources.storyboardc"),
]
failed = False
for want, rel in checks:
    base = os.path.join(app, rel)
    hit = False
    if os.path.isdir(base):
        for dp, dn, fn in os.walk(base):
            for f in fn:
                d = open(os.path.join(dp, f), 'rb').read()
                if any(want.encode(e) in d for e in ("utf-8", "utf-16-le", "utf-16-be")):
                    hit = True; break
            if hit: break
    print(("OK  " if hit else "FAIL"), want, "in", rel)
    if not hit: failed = True
sys.exit(1 if failed else 0)
EOF
echo "OK: zh-Hans nibs baked with Chinese strings:"
ls "$APP/zh-Hans.lproj/"
