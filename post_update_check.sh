#!/usr/bin/env bash
# post_update_check.sh — Brave 大版本更新后必须执行的验证脚本
# 版本：v1
# 用途：确认 Brave 更新未重置关键安全配置

PASS=0
FAIL=0

check() {
    local desc="$1"
    local result="$2"
    if [[ "$result" == "ok" ]]; then
        echo "  ✓ $desc"
        ((PASS++))
    else
        echo "  ✗ $desc — $result"
        ((FAIL++))
    fi
}

echo "=== Brave 更新后配置验证 ==="
echo ""

# 检查 Brave 版本
BRAVE_VER=$(brave-browser --version 2>/dev/null || echo "无法获取")
echo "  Brave 版本: $BRAVE_VER"
echo ""

# 检查 initial_preferences 文件是否存在
PREFS="$HOME/.config/BraveSoftware/Brave-Browser/initial_preferences"
if [[ -f "$PREFS" ]]; then
    check "initial_preferences 文件存在" "ok"
else
    check "initial_preferences 文件存在" "文件不存在，请重新执行 playbook"
fi

# 检查 brave-kiosk.sh 启动脚本存在且可执行
SCRIPT="$HOME/.local/bin/brave-kiosk.sh"
if [[ -x "$SCRIPT" ]]; then
    check "brave-kiosk.sh 可执行" "ok"
else
    check "brave-kiosk.sh 可执行" "文件缺失或无执行权限"
fi

# 检查 cage-kiosk.service 已启用
if systemctl is-enabled cage-kiosk.service &>/dev/null; then
    check "cage-kiosk.service 已启用" "ok"
else
    check "cage-kiosk.service 已启用" "服务未启用，执行: sudo systemctl enable cage-kiosk.service"
fi

echo ""
echo "─────────────────────────────────────────"
echo "  需要手动验证（无法自动检测）："
echo ""
echo "  1. 启动 Brave 后进入："
echo "     Settings → Web3 → Default wallet"
echo "     确认为 None（不是 Brave Wallet）"
echo ""
echo "  2. 确认 MetaMask 扩展能正常唤醒 window.ethereum"
echo "     方法：在 Polymarket 点击 Connect Wallet，"
echo "     应弹出 MetaMask 而不是 Brave Wallet"
echo "─────────────────────────────────────────"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "  自动检查全部通过（$PASS 项）"
else
    echo "  ⚠ $FAIL 项检查失败，请按提示修复"
fi
