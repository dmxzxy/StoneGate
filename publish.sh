#!/bin/bash
# =============================================================================
# publish.sh — StoneGate .love 游戏包发布工具
#
# 用法:
#   bash publish.sh <file.love>           # 上传游戏包
#   bash publish.sh --list                # 查看服务器游戏列表
#   bash publish.sh --delete <game_id>    # 删除游戏
#   bash publish.sh --server <url> ...    # 指定服务器地址
#
# 环境变量:
#   STONEGATE_SERVER  服务器地址 (默认从 src/config.lua 读取)
#   STONEGATE_TOKEN   认证 token (默认 stonegate2024)
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_LUA="$SCRIPT_DIR/src/config.lua"
DEFAULT_SERVER="http://192.168.50.123:8080"
DEFAULT_TOKEN="stonegate2024"

# ---------------------------------------------------------------------------
# 从 config.lua 读取 server_url
# ---------------------------------------------------------------------------
read_server_url() {
    if [ -f "$CONFIG_LUA" ]; then
        # Extract: server_url = "http://...",
        local url
        url=$(grep -oP 'server_url\s*=\s*"[^"]*"' "$CONFIG_LUA" | head -1 | grep -oP '"[^"]*"' | tr -d '"')
        if [ -n "$url" ]; then
            echo "$url"
            return
        fi
    fi
    echo "$DEFAULT_SERVER"
}

SERVER="${STONEGATE_SERVER:-$(read_server_url)}"
TOKEN="${STONEGATE_TOKEN:-$DEFAULT_TOKEN}"

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
ACTION=""
TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --list|-l)
            ACTION="list"
            shift
            ;;
        --delete|-d)
            ACTION="delete"
            shift
            TARGET="${1:-}"
            [ -z "$TARGET" ] && { echo "用法: publish.sh --delete <game_id>"; exit 1; }
            shift
            ;;
        --server|-s)
            SERVER="$2"
            shift 2
            ;;
        --token|-t)
            TOKEN="$2"
            shift 2
            ;;
        --help|-h)
            echo "StoneGate Publish Tool"
            echo ""
            echo "用法:"
            echo "  bash publish.sh <file.love>           上传游戏包"
            echo "  bash publish.sh --list                查看服务器游戏列表"
            echo "  bash publish.sh --delete <game_id>    删除游戏"
            echo "  bash publish.sh --server <url> ...    指定服务器地址"
            echo ""
            echo "环境变量:"
            echo "  STONEGATE_SERVER   服务器地址 (默认从 src/config.lua 读取)"
            echo "  STONEGATE_TOKEN    认证 token"
            exit 0
            ;;
        *)
            # Treat as file to upload
            if [ -z "$ACTION" ]; then
                ACTION="upload"
                TARGET="$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$ACTION" ]; then
    echo "用法: bash publish.sh <file.love|--list|--delete <id>>"
    echo "      bash publish.sh --help 查看完整帮助"
    exit 1
fi

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

do_list() {
    echo "─── StoneGate 游戏列表 ───"
    echo "服务器: $SERVER"
    echo ""

    local response
    response=$(curl -sf "$SERVER/games/list.json" 2>&1) || {
        echo "❌ 无法连接服务器: $SERVER"
        exit 1
    }

    # Parse with python for nice output
    echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    games = data.get('games', [])
    if not games:
        print('  (空)')
    for g in games:
        size = g.get('size', 0)
        if size < 1024: size_s = f'{size} B'
        elif size < 1048576: size_s = f'{size/1024:.1f} KB'
        else: size_s = f'{size/1048576:.1f} MB'
        print(f\"  {g['id']:<20s} {g['name']:<24s} v{g['version']:<6s} {size_s:<10s} {g.get('updated','')}\")
    print(f'\\n共 {len(games)} 个游戏')
except Exception as e:
    print(f'解析失败: {e}')
" 2>/dev/null || echo "$response"
}

do_upload() {
    local file="$TARGET"

    if [ ! -f "$file" ]; then
        echo "❌ 文件不存在: $file"
        exit 1
    fi

    if [[ "$(basename "$file")" != *.love ]]; then
        echo "❌ 文件必须以 .love 结尾: $file"
        exit 1
    fi

    local filename
    filename=$(basename "$file")
    local size
    size=$(wc -c < "$file")

    echo "─── 上传游戏 ───"
    echo "  文件:   $filename"
    echo "  大小:   $size bytes"
    echo "  服务器: $SERVER"
    echo ""

    local response
    response=$(curl -sf \
        -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -F "file=@$file" \
        "$SERVER/games/upload" 2>&1)

    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "❌ 上传失败 (curl exit: $exit_code)"
        echo "   $response"
        exit 1
    fi

    # Parse response
    echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('ok'):
        g = data.get('game', {})
        print(f\"✅ 上传成功!\")
        print(f\"   ID:   {g.get('id', '?')}\")
        print(f\"   名称: {g.get('name', '?')}\")
        print(f\"   版本: {g.get('version', '?')}\")
        print(f\"   大小: {g.get('size', '?')} bytes\")
    else:
        print(f\"❌ 服务器拒绝: {data.get('error', 'unknown')}\")
except Exception as e:
    print(f\"⚠️  上传完成，但解析响应失败: {e}\")
    print(f\"   原始响应: {sys.stdin.read()}\")
" 2>/dev/null || echo "$response"
}

do_delete() {
    local game_id="$TARGET"

    echo "─── 删除游戏 ───"
    echo "  ID:     $game_id"
    echo "  服务器: $SERVER"
    echo ""

    local response
    response=$(curl -sf \
        -X DELETE \
        -H "Authorization: Bearer $TOKEN" \
        "$SERVER/games/$game_id" 2>&1)

    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "❌ 删除失败 (curl exit: $exit_code)"
        echo "   $response"
        exit 1
    fi

    echo "$response" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('ok'):
        print(f\"✅ 已删除: {data.get('deleted', '?')}\")
    else:
        print(f\"❌ 删除失败: {data.get('error', 'unknown')}\")
except Exception as e:
    print(f\"⚠️  响应解析失败: {e}\")
" 2>/dev/null || echo "$response"
}

# ---------------------------------------------------------------------------
# Execute
# ---------------------------------------------------------------------------
case "$ACTION" in
    list)   do_list   ;;
    upload) do_upload ;;
    delete) do_delete ;;
esac
