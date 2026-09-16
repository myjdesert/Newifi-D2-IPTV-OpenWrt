#!/bin/bash
# ============================================================
# DIY Part 2 - feeds 安装之后、make 之前执行
# 主要任务: 把 rtp2httpd 及其 LuCI 界面加入源码树
#
# 关键点：官方 openwrt-support/rtp2httpd/Makefile 里的 Build/Prepare 是
#   $(CP) $(CURDIR)/../../* $(PKG_BUILD_DIR)/
# 那是给"整个仓库当 package 目录"用的，直接把它拷进 package/ 会导致把
# OpenWrt 整棵源码树复制进 build_dir，编译必炸。
# 所以这里改用官方为固件维护者准备的 Makefile.versioned：
# 固定版本 + 下载 tarball + PKG_HASH，干净可靠。
# ============================================================

set -e

echo "============================================"
echo " DIY Part 2: 加入 rtp2httpd"
echo "============================================"

# --- 1. rtp2httpd ---
echo "[1/4] 添加 rtp2httpd..."

rm -rf /tmp/rtp2httpd
git clone --depth 1 https://github.com/stackia/rtp2httpd.git /tmp/rtp2httpd 2>/dev/null || {
    echo "  -> github 失败，尝试 gitcode 镜像..."
    git clone --depth 1 https://gitcode.com/stackia/rtp2httpd.git /tmp/rtp2httpd 2>/dev/null || {
        echo "  !! ERROR: 无法克隆 rtp2httpd"
        exit 1
    }
}

if [ ! -d "/tmp/rtp2httpd/openwrt-support/rtp2httpd" ]; then
    echo "  !! ERROR: 仓库里没有 openwrt-support/rtp2httpd"
    exit 1
fi

# 取 Makefile.versioned 里固定的版本号，把仓库切到对应 tag，
# 保证 files/（init 脚本 + 默认 UCI 配置）与源码版本一致
VER=$(sed -n 's/^RELEASE_VERSION:=\(.*\)/\1/p' /tmp/rtp2httpd/openwrt-support/rtp2httpd/Makefile.versioned 2>/dev/null | tr -d ' \t')
if [ -n "$VER" ]; then
    echo "  -> Makefile.versioned 固定版本: $VER"
    ( cd /tmp/rtp2httpd && git fetch --depth 1 origin "refs/tags/v$VER:refs/tags/v$VER" >/dev/null 2>&1 && git checkout -q "v$VER" >/dev/null 2>&1 ) \
        && echo "  -> 已切换到 v$VER" || echo "  -> 切 tag 失败，使用 main 分支的 files/"
fi

rm -rf package/rtp2httpd package/luci-app-rtp2httpd
cp -r /tmp/rtp2httpd/openwrt-support/rtp2httpd package/rtp2httpd
[ -d /tmp/rtp2httpd/openwrt-support/luci-app-rtp2httpd ] && \
    cp -r /tmp/rtp2httpd/openwrt-support/luci-app-rtp2httpd package/luci-app-rtp2httpd

# 用 versioned Makefile 覆盖 git-describe 版
if [ -f /tmp/rtp2httpd/openwrt-support/rtp2httpd/Makefile.versioned ]; then
    cp /tmp/rtp2httpd/openwrt-support/rtp2httpd/Makefile.versioned package/rtp2httpd/Makefile
    echo "  -> 已使用 Makefile.versioned（固定版本 + tarball）"
else
    echo "  !! ERROR: 没有 Makefile.versioned"
    exit 1
fi

# 双重保险：确认 Build/Prepare 不会再去拷源码树
if grep -q 'CURDIR)/../\.\.' package/rtp2httpd/Makefile; then
    echo "  !! Makefile 仍含 CURDIR/../.. 的复制逻辑，改用 TOPDIR 下的源目录"
    sed -i 's#\$(CURDIR)/\.\./\.\./\*#$(TOPDIR)/rtp2httpd-src/*#g' package/rtp2httpd/Makefile
fi

rm -rf /tmp/rtp2httpd

# 校验
[ -f "package/rtp2httpd/Makefile" ] || { echo "  !! ERROR: Makefile 缺失"; exit 1; }
[ -f "package/rtp2httpd/files/rtp2httpd.init" ] || echo "  [WARN] files/rtp2httpd.init 缺失"
[ -f "package/rtp2httpd/files/rtp2httpd.conf" ] || echo "  [WARN] files/rtp2httpd.conf 缺失"
echo "  [OK] package/rtp2httpd"
[ -f "package/luci-app-rtp2httpd/Makefile" ] && echo "  [OK] package/luci-app-rtp2httpd" || echo "  [WARN] luci-app-rtp2httpd 缺失（不影响主程序）"

# --- 2. 校正 .config 里的设备键（ramips <-> mediatek 改名兼容） ---
echo "[2/4] 校正 .config 设备键..."
TARGET_DIR="ramips"
[ -f /tmp/.gdiptv_target ] && TARGET_DIR=$(cat /tmp/.gdiptv_target)
if [ -f .config ] && [ "$TARGET_DIR" != "ramips" ]; then
    sed -i "s|CONFIG_TARGET_ramips_mt7621_DEVICE_|CONFIG_TARGET_${TARGET_DIR}_mt7621_DEVICE_|g" .config
    sed -i "s|^CONFIG_TARGET_ramips=y|CONFIG_TARGET_${TARGET_DIR}=y|g" .config
    sed -i "s|^CONFIG_TARGET_ramips_mt7621=y|CONFIG_TARGET_${TARGET_DIR}_mt7621=y|g" .config
    echo "  -> 已改写为 ${TARGET_DIR}"
else
    echo "  -> 保持 ramips（真正的改写发生在 workflow 里）"
fi

# --- 3. 空白占位 ---
echo "[3/4] -"

# --- 4. 关键包检查 ---
echo "[4/4] 关键包检查:"
for p in rtp2httpd luci-app-rtp2httpd igmpproxy curl tcpdump ip-full kmod-8021q luci-theme-argon; do
    if find package/ feeds/ -mindepth 2 -maxdepth 3 -type d -name "$p" 2>/dev/null | grep -q .; then
        echo "    [OK] $p"
    else
        echo "    [WARN] $p 未找到"
    fi
done

echo ""
echo "============================================"
echo " Target : ${TARGET_DIR}/mt7621/d-team_newifi-d2"
echo " IPTV   : rtp2httpd(5140) + igmpproxy"
echo " 鉴权   : /usr/bin/gdiptv-update (EDS + ValidAuthenticationHWCTC)"
echo "============================================"
echo "DIY Part 2 完成。"
