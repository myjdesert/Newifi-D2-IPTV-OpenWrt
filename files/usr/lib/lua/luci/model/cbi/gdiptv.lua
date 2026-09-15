-- ============================================================
-- 广东电信 IPTV —— LuCI 配置页
-- 填写 IPTV 专网拨号账号/密码/MAC 与 EPG 鉴权(postBody)，一键生成播放列表
-- ============================================================

local sys  = require "luci.sys"
local http = require "luci.http"
local uci  = require "luci.model.uci".cursor()

local CFG   = "gdiptv"
local SEC   = "main"
local lanip = uci:get("network", "lan", "ipaddr") or "192.168.1.2"

local function esc(s)
	-- 安全地包一层单引号，避免用户输入破坏 shell 命令
	return "'" .. tostring(s or ""):gsub("'", "'\\''") .. "'"
end

-- CBI 表单字段名规则：cbid.<config>.<section>.<option>
-- 直接从 formvalue 取，保证拿到的是用户刚输入的那一版
local function fv(opt)
	return http.formvalue(table.concat({"cbid", CFG, SEC, opt}, ".")) or ""
end

m = Map(CFG, "广东电信 IPTV 内网融合",
  "旁路由模式下电视机/手机与主路由同网段。在这里填写 IPTV 专网拨号账号与 EPG 鉴权参数，" ..
  "保存后会自动重拨并生成播放列表。<br>" ..
  "<b>“认证中间数据(postBody)”必填</b>，可用 SSH 执行 <code>gdiptv-sniff</code> 自动抓取，或手动粘贴。")

-- ---------------- 基本设置 ----------------
s = m:section(NamedSection, SEC, "gdiptv", "基本设置")

o = s:option(Flag, "enabled", "启用定时自动更新",
  "每天定时刷新频道列表与节目单")
o.rmempty = false

o = s:option(Value, "username", "IPTV 拨号账号",
  "电信给你的 IPTV 账号，形如 020xxxxxxxx@iptv.gd")
o.rmempty  = true
o.optional = true

o = s:option(Value, "password", "IPTV 拨号密码")
o.password = true
o.rmempty  = true
o.optional = true

o = s:option(Value, "macaddr", "机顶盒 MAC（可选）",
  "电信把 IPTV 绑定了机顶盒 MAC 时才需要；不填则使用 WAN 口自身 MAC")
o.rmempty     = true
o.optional    = true
o.placeholder = "AA:BB:CC:DD:EE:FF"

o = s:option(TextValue, "auth_body", "认证中间数据 (postBody)",
  "ValidAuthenticationHWCTC.jsp 的 POST 表单原文，例如：<br>" ..
  "UserID=xxx&amp;Lang=&amp;SupportHD=1&amp;NetUserID=...&amp;userToken=...&amp;VIP=")
o.rows    = 3
o.rmempty = true
o.wrap    = "off"

-- ---------------- 网络与节目单 ----------------
s2 = m:section(NamedSection, SEC, "gdiptv", "网络与节目单")

o = s2:option(Value, "iptv_device", "IPTV 接口设备",
  "接光猫 ITV 口的物理口，默认 wan（路由器 WAN 口）。单线复用改成 wan.45 之类")
o.default  = "wan"
o.rmempty  = true
o.optional = true

o = s2:option(Value, "lan_gateway", "主路由网关",
  "D2 所在网段的主路由地址，用于上外网拉节目单（改完需重启生效）")
o.default  = "192.168.1.1"
o.rmempty  = true
o.optional = true

o = s2:option(Value, "epg_url", "EPG 节目单地址",
  "xmltv 格式，默认 litiande03 每日输出（自动识别 gzip 并解压）")
o.default  = "https://raw.githubusercontent.com/litiande03/epg/refs/heads/master/pl.xml.gz"
o.rmempty  = true
o.optional = true

-- ---------------- 操作按钮 ----------------
btn = s2:option(Button, "_apply", "保存并重拨",
  "把账号/密码/MAC/设备同步到 network.iptv 并重拨，随后强制刷新列表（约需 1 分钟）")
btn.inputtitle = "保存并重拨 IPTV"
btn.inputstyle = "apply"
function btn.write(self, section)
	local u   = fv("username")
	local p   = fv("password")
	local mac = fv("macaddr")
	local dev = fv("iptv_device")
	if dev == "" then dev = "wan" end

	sys.call("uci -q set network.iptv.device="   .. esc(dev))
	sys.call("uci -q set network.iptv.username=" .. esc(u))
	sys.call("uci -q set network.iptv.password=" .. esc(p))
	if mac ~= "" then
		sys.call("uci -q set network.iptv.macaddr=" .. esc(mac))
	else
		sys.call("uci -q del network.iptv.macaddr 2>/dev/null")
	end
	sys.call("uci -q commit network")

	-- 后台执行：只重拨 iptv 接口（不动 lan，避免把 LuCI 连接掐断）
	sys.call(
		"( /sbin/ifdown iptv 2>/dev/null; sleep 2; /sbin/ifup iptv 2>/dev/null; " ..
		"sleep 15; /usr/bin/gdiptv-update -f ) >/tmp/gdiptv-update.log 2>&1 &"
	)
end

btn2 = s2:option(Button, "_update", "仅刷新列表",
  "IPTV 已拨号在线时使用，不动网络配置，只重拉频道列表与节目单")
btn2.inputtitle = "立即刷新列表"
btn2.inputstyle = "reload"
function btn2.write(self, section)
	sys.call("/usr/bin/gdiptv-update -f >/tmp/gdiptv-update.log 2>&1 &")
end

-- ---------------- 结果查看 ----------------
st = s2:option(DummyValue, "_url", "可用地址")
st.rawhtml = false
st.value = string.format(
	"列表首页 http://%s/iptv/    ·    rtp2httpd 状态 http://%s:5140/status",
	lanip, lanip)

logv = s2:option(TextValue, "_log", "最近一次更新日志")
logv.rows     = 12
logv.readonly = true
logv.wrap     = "off"
function logv.cfgvalue(self, section)
	local f = io.open("/tmp/gdiptv-update.log", "r")
	if not f then
		return "（暂无日志。点“保存并重拨 IPTV”后约 1 分钟再看这里）"
	end
	local c = f:read("*a")
	f:close()
	if not c or c == "" then
		return "（日志为空，可能还正在跑）"
	end
	return c
end

return m
