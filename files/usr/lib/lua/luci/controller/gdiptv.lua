-- 广东电信 IPTV —— LuCI 菜单入口

function index()
	entry({"admin", "services", "gdiptv"},
		cbi("gdiptv"),
		_("广东电信 IPTV"),
		60).dependent = false
end
