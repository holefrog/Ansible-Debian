#!/usr/bin/env bash
# brave-kiosk.sh — Brave Kiosk 启动脚本
# 版本：v2

# 循环检查网络连通性，最多等待 30 秒
# 这样既能防止开机太快导致加载失败，又能在真正断网时让浏览器报错提示用户
MAX_RETRIES=30
count=0
while ! ping -c 1 -W 1 polymarket.com &> /dev/null; do
    sleep 1
    count=$((count + 1))
    if [ $count -ge $MAX_RETRIES ]; then
        break
    fi
done

exec brave-browser \
    --ozone-platform=wayland \
    --enable-features=UseOzonePlatform \
    --kiosk \
    --no-first-run \
    --disable-sync \
    --disable-translate \
    --no-default-browser-check \
    --disable-client-side-phishing-detection \
    --disable-default-apps \
    --disable-hang-monitor \
    --disable-prompt-on-repost \
    --disable-domain-reliability \
    --disable-breakpad \
    --metrics-recording-only \
    --safebrowsing-disable-auto-update \
    "https://polymarket.com"
