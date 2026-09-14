#!/bin/bash
# ============================================================
# DIY Part 1 - 在 feeds 安装之前执行
# 目标: immortalwrt/immortalwrt @ openwrt-24.10
# 设备: Newifi 3 D2 (ramips/mt7621, d-team_newifi-d2)
# ============================================================

set -e

echo "============================================"
echo " DIY Part 1: Newifi D2 广东电信 IPTV 固件"
echo "============================================"

# 1. 确认目标存在（ramips 在新版本可能被改名为 mediatek，这里做兼容探测）
echo "[1/4] 探测 target 目录..."
if [ -d "target/linux/ramips" ]; then
    TARGET_DIR="ramips"
elif [ -d "target/linux/mediatek" ]; then
    TARGET_DIR="mediatek"
else
    echo "  !! ERROR: 既没有 target/linux/ramips 也没有 target/linux/mediatek"
    exit 1
fi
echo "  -> target = $TARGET_DIR"
echo "$TARGET_DIR" > /tmp/.gdiptv_target

# 2. 确认设备定义存在
echo "[2/4] 确认 d-team_newifi-d2 设备定义..."
if grep -rq "d-team_newifi-d2" "target/linux/$TARGET_DIR/image/" 2>/dev/null; then
    echo "  [OK] 找到 d-team_newifi-d2"
else
    echo "  !! ERROR: 未找到 d-team_newifi-d2 设备定义"
    exit 1
fi

# 3. 追加自定义 feeds（rtp2httpd 走本地 package 方式，见 part2）
echo "[3/4] 准备 feeds.conf..."
if [ -f "feeds.conf.default" ]; then
    echo "  -> 保留默认 feeds"
fi

# 4. 打印内核版本
echo "[4/4] 内核版本:"
grep -H "KERNEL_PATCHVER" "target/linux/$TARGET_DIR/Makefile" 2>/dev/null || true
grep -H "KERNEL_PATCHVER" "target/linux/$TARGET_DIR/mt7621/Makefile" 2>/dev/null || true

echo ""
echo "DIY Part 1 完成。"
