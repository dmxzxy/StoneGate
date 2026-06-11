#!/bin/bash
# =============================================================================
# build_apk.sh — StoneGate 一键构建脚本
#
# 用法: bash build_apk.sh [选项]
#
# 目录结构:
#   src/         LÖVE 源代码 (conf.lua, main.lua, ...)
#   server/      游戏分发服务器
#   tools/       构建工具 (apktool.jar, uber-apk-signer.jar)
#   build/       构建产物 (自动生成，已 gitignore)
#
# 选项:
#   --clean      清理后全量重新构建
#   --no-sign    只打包不签名
#   --release    使用 release keystore 签名 (需 tools/stonegate.keystore)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# 配置区 — 修改这里定制你的 APP
# ---------------------------------------------------------------------------
APP_NAME="StoneGate"
PACKAGE_NAME="com.stonegate.app"
VERSION_CODE=2
VERSION_NAME="2.0.0"
SCREEN_ORIENTATION="sensorPortrait"

# LÖVE embed APK 下载地址 (love-android 官方 release)
LOVE_APK_URL="https://github.com/love2d/love-android/releases/download/11.5a/love-11.5-android-embed.apk"

# ---------------------------------------------------------------------------
# 路径
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

SRC_DIR="$SCRIPT_DIR/src"
TOOLS_DIR="$SCRIPT_DIR/tools"
BUILD_DIR="$SCRIPT_DIR/build"
SERVER_DIR="$SCRIPT_DIR/server"

DECODED="$BUILD_DIR/_decoded"        # apktool 反编译临时目录
BASE_APK="$TOOLS_DIR/love-embed.apk" # 基础 APK (自动下载)

APKTOOL="$TOOLS_DIR/apktool.jar"
SIGNER="$TOOLS_DIR/uber-apk-signer.jar"
KEYSTORE="$TOOLS_DIR/stonegate.keystore"

# ---------------------------------------------------------------------------
# 工具检测
# ---------------------------------------------------------------------------
detect_java() {
    local ms_jdk="/c/Program Files/Microsoft/jdk-21.0.11.10-hotspot/bin/java.exe"
    [ -f "$ms_jdk" ] && echo "$ms_jdk" && return
    command -v java &>/dev/null && echo "java" && return
    echo "ERROR: 未找到 Java！请安装 JDK 17+" >&2; exit 1
}

detect_python() {
    local paths=(
        "/c/Users/Shawn/AppData/Local/Programs/Python/Python310/python.exe"
        "/c/Users/Shawn/AppData/Local/Programs/Python/Python312/python.exe"
        "/c/Users/Shawn/AppData/Local/Programs/Python/Python313/python.exe"
    )
    for p in "${paths[@]}"; do [ -f "$p" ] && echo "$p" && return; done
    for cmd in python python3 py; do command -v "$cmd" &>/dev/null && echo "$cmd" && return; done
    echo ""
}

JAVA="$(detect_java)"
PYTHON="$(detect_python)"

echo "[INFO] Java:    $JAVA"
echo "[INFO] Python:  ${PYTHON:-未找到，跳过图标生成}"
echo "[INFO] App:     $APP_NAME ($PACKAGE_NAME) v$VERSION_NAME"
echo ""

# ---------------------------------------------------------------------------
# 参数
# ---------------------------------------------------------------------------
CLEAN=false; NO_SIGN=false; RELEASE=false
for arg in "$@"; do
    case "$arg" in
        --clean)   CLEAN=true ;;
        --no-sign) NO_SIGN=true ;;
        --release) RELEASE=true ;;
    esac
done

# ---------------------------------------------------------------------------
# 自动下载缺失的工具和基础 APK
# ---------------------------------------------------------------------------
download() {
    local url="$1" dest="$2"
    echo "[下载] $(basename "$dest") ..."
    /c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command \
        "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
         (New-Object System.Net.WebClient).DownloadFile('$url', '$(cygpath -w "$dest")')"
}

mkdir -p "$TOOLS_DIR" "$BUILD_DIR"

[ ! -f "$APKTOOL" ] && \
    download "https://github.com/iBotPeaches/Apktool/releases/download/v2.10.0/apktool_2.10.0.jar" "$APKTOOL"

[ ! -f "$SIGNER" ] && \
    download "https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar" "$SIGNER"

[ ! -f "$BASE_APK" ] && \
    download "$LOVE_APK_URL" "$BASE_APK"

# ---------------------------------------------------------------------------
# 清理
# ---------------------------------------------------------------------------
if [ "$CLEAN" = true ]; then
    echo "[清理] 删除中间产物..."
    rm -rf "$DECODED"
    rm -f "$BUILD_DIR"/*.apk "$BUILD_DIR"/*.idsig
fi

# ===================================================================
# Step 1: 反编译 (仅在 decoded 不存在时)
# ===================================================================
echo "[1/5] 反编译 APK..."
if [ ! -d "$DECODED" ]; then
    "$JAVA" -jar "$APKTOOL" d -s -o "$DECODED" "$BASE_APK"
else
    echo "  (复用已有，加 --clean 强制重新反编译)"
fi

# ===================================================================
# Step 2: 生成图标
# ===================================================================
echo "[2/5] 图标..."
if [ -n "$PYTHON" ]; then
    ICON_DIR="$(cygpath -w "$DECODED/res")"
    "$PYTHON" -c "
from PIL import Image, ImageDraw, ImageFont
import os

sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
icon_dir = r'$ICON_DIR'

for density, px in sizes.items():
    img = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    margin = max(2, px // 20)
    # Stone arch/gate icon
    draw.rounded_rectangle([margin, margin, px-margin, px-margin], radius=px//5, fill=(20,30,60))
    # Gate arch
    gw = px * 2 // 3
    gh = px // 2
    gx = (px - gw) // 2
    gy = margin + px // 10
    draw.arc([gx, gy, gx+gw, gy+gh*2], 180, 0, fill=(65,140,255), width=max(2, px//15))
    # Gate bars
    bar_y = gy + gh // 2
    draw.line([gx + gw//4, bar_y, gx + gw//4, gy + gh], fill=(65,140,255), width=max(1, px//25))
    draw.line([gx + gw//2, bar_y, gx + gw//2, gy + gh], fill=(65,140,255), width=max(1, px//25))
    draw.line([gx + gw*3//4, bar_y, gx + gw*3//4, gy + gh], fill=(65,140,255), width=max(1, px//25))
    draw.line([gx, gy + gh, gx + gw, gy + gh], fill=(65,140,255), width=max(1, px//20))
    # Stone text
    try:
        fs = max(8, px//7)
        font = ImageFont.truetype('arial.ttf', fs)
    except: font = ImageFont.load_default()
    bbox = draw.textbbox((0,0), 'SG', font=font)
    draw.text((px//2-(bbox[2]-bbox[0])//2, px-margin-fs-4), 'SG', fill=(200,210,240), font=font)
    img.save(os.path.join(icon_dir, f'drawable-{density}', 'love.png'), 'PNG')
print('  图标已生成 (5 个密度)')
" 2>&1
else
    echo "  (跳过，保留原图标)"
fi

# ===================================================================
# Step 3: 定制 Manifest
# ===================================================================
echo "[3/5] 定制 Manifest..."
MANIFEST="$DECODED/AndroidManifest.xml"
YML="$DECODED/apktool.yml"

sed -i \
    -e "s|package=\"org.love2d.android\"|package=\"${PACKAGE_NAME}\"|" \
    -e "s|android:versionCode=\"[0-9]*\"|android:versionCode=\"${VERSION_CODE}\"|" \
    -e "s|android:versionName=\"[^\"]*\"|android:versionName=\"${VERSION_NAME}\"|" \
    -e "s|android:label=\"LÖVE for Android\"|android:label=\"${APP_NAME}\"|g" \
    -e "s|android:screenOrientation=\"[a-z]*\"|android:screenOrientation=\"${SCREEN_ORIENTATION}\"|" \
    -e "s|org.love2d.android.DYNAMIC|${PACKAGE_NAME}.DYNAMIC|" \
    -e "s|org.love2d.android.androidx-startup|${PACKAGE_NAME}.androidx-startup|" \
    "$MANIFEST"

if ! grep -q "android:versionCode" "$MANIFEST"; then
    sed -i "s|package=\"${PACKAGE_NAME}\"|package=\"${PACKAGE_NAME}\" android:versionCode=\"${VERSION_CODE}\" android:versionName=\"${VERSION_NAME}\"|" "$MANIFEST"
fi

sed -i \
    -e "s|renameManifestPackage:.*|renameManifestPackage: ${PACKAGE_NAME}|" \
    -e "s|versionCode:.*|versionCode: ${VERSION_CODE}|" \
    -e "s|versionName:.*|versionName: ${VERSION_NAME}|" \
    "$YML"

echo "  $PACKAGE_NAME v$VERSION_NAME"

# ===================================================================
# Step 4: 打包 game.love 并嵌入
# ===================================================================
echo "[4/5] 打包 game.love..."

GAME_LOVE="$BUILD_DIR/game.love"

# 用 PowerShell 打 zip (game.love 本质是 zip)
/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "
Remove-Item -Force '$(cygpath -w "$GAME_LOVE")' -ErrorAction SilentlyContinue
Set-Location '$(cygpath -w "$SRC_DIR")'
Compress-Archive -Path *.lua -DestinationPath '$(cygpath -w "$BUILD_DIR/_temp.zip")' -Force
Rename-Item '$(cygpath -w "$BUILD_DIR/_temp.zip")' 'game.love'
" 2>&1 | tail -1

cp "$GAME_LOVE" "$DECODED/assets/game.love"

LOVE_SIZE=$(wc -c < "$GAME_LOVE")
echo "  game.love 已嵌入 (${LOVE_SIZE} bytes)"

# ===================================================================
# Step 5: 重编译 + 签名
# ===================================================================
echo "[5/5] 重编译 + 签名..."

UNSIGNED="$BUILD_DIR/${PACKAGE_NAME}.apk"
"$JAVA" -jar "$APKTOOL" b -o "$UNSIGNED" "$DECODED" 2>&1 | tail -2

if [ "$NO_SIGN" = true ]; then
    echo ""
    echo "完成 (未签名): $UNSIGNED"
    exit 0
fi

if [ "$RELEASE" = true ] && [ -f "$KEYSTORE" ]; then
    echo "[签名] release keystore..."
    "$JAVA" -jar "$SIGNER" -a "$UNSIGNED" \
        --ks "$KEYSTORE" --ksAlias stonegate \
        --ksPass stonegate --ksKeyPass stonegate \
        --out "$BUILD_DIR/" 2>&1 | tail -3
else
    echo "[签名] debug..."
    "$JAVA" -jar "$SIGNER" -a "$UNSIGNED" --out "$BUILD_DIR/" 2>&1 | tail -3
fi

# 找到签名后的 APK (uber-apk-signer 输出文件名含 -aligned-signed 或 -aligned-debugSigned)
FINAL_APK=$(ls -t "$BUILD_DIR/"*-aligned-*igned.apk 2>/dev/null | head -1)
if [ -n "$FINAL_APK" ]; then
    FRIENDLY="$BUILD_DIR/stonegate_v${VERSION_NAME}.apk"
    cp "$FINAL_APK" "$FRIENDLY"
    # 清理中间文件
    rm -f "$UNSIGNED"
    rm -f "$BUILD_DIR/"*-aligned-*igned.apk "$BUILD_DIR/"*-aligned-*igned.apk.idsig 2>/dev/null || true

    echo ""
    echo "========================================="
    echo "  ✅ 构建成功"
    echo "  $(cygpath -w "$FRIENDLY")"
    ls -lh "$FRIENDLY" | awk '{print "  大小: " $5}'
    echo "  $PACKAGE_NAME v$VERSION_NAME"
    echo "========================================="
else
    echo "[WARN] 签名后未找到 APK，请检查 $BUILD_DIR/"
fi
