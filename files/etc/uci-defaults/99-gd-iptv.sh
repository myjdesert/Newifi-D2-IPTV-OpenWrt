#!/bin/sh
# ============================================================
# 首次启动初始化（uci-defaults 只跑一次，跑完自动删除）
# ============================================================

. /lib/functions.sh

# git/Windows 可能丢掉可执行位，这里补回来
chmod 0755 /usr/bin/gdiptv-update /usr/bin/gdiptv-sniff 2>/dev/null
chmod 0755 /etc/hotplug.d/iface/30-gdiptv 2>/dev/null
chmod 0600 /etc/crontabs/root 2>/dev/null

mkdir -p /www/iptv /etc/gdiptv/cache 2>/dev/null
chmod 0755 /www/iptv 2>/dev/null

# ---------- 系统 ----------
uci -q set system.@system[0].hostname='Newifi-D2-IPTV'
uci -q set system.@system[0].timezone='CST-8'
uci -q set system.@system[0].zonename='Asia/Shanghai'
uci -q set system.@system[0].log_size='256'
uci -q set system.@system[0].ttylogin='0'
uci -q commit system

# ---------- LuCI 快捷命令（luci-app-commands）----------
if [ -f /etc/config/luci ]; then
	uci -q batch <<-EOF
		delete luci.iptv_refresh
		set luci.iptv_refresh=command
		set luci.iptv_refresh.name='刷新IPTV列表(强制)'
		set luci.iptv_refresh.command='/usr/bin/gdiptv-update'
		set luci.iptv_refresh.param='-f'
		set luci.iptv_refresh.public='0'

		delete luci.iptv_update
		set luci.iptv_update=command
		set luci.iptv_update.name='刷新IPTV列表'
		set luci.iptv_update.command='/usr/bin/gdiptv-update'
		set luci.iptv_update.param=''
		set luci.iptv_update.public='0'

		delete luci.iptv_sniff
		set luci.iptv_sniff=command
		set luci.iptv_sniff.name='抓取IPTV鉴权包(180s)'
		set luci.iptv_sniff.command='/usr/bin/gdiptv-sniff'
		set luci.iptv_sniff.param=''
		set luci.iptv_sniff.public='0'
	EOF
	uci -q commit luci
fi

# ---------- 服务自启 ----------
/etc/init.d/cron enable
[ -x /etc/init.d/rtp2httpd ] && /etc/init.d/rtp2httpd enable
# igmpproxy 默认不开：只有机顶盒要原生组播才需要
[ -x /etc/init.d/igmpproxy ] && /etc/init.d/igmpproxy disable

exit 0
