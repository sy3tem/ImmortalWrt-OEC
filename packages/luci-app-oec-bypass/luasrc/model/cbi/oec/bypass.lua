-- Copyright (C) 2026
-- SPDX-License-Identifier: Apache-2.0
--
-- 旁路由设置 —— 只做两件事：
--   1) 选 LAN 口怎么拿地址：自动获取（DHCP 客户端）/ 固定 IP（静态地址）
--   2) 保证本机 dnsmasq DHCP 服务关闭
--
-- 第 2 点是旁路由的硬性要求：单网口设备如果一边当旁路由、一边还在 LAN 上
-- 发 DHCP，就会和上游主路由抢着应答，局域网里会出现两个 DHCP server。

local m, s, o

m = Map("network", translate("旁路由设置"),
	translate("本机按单网口旁路由（旁路网关）使用。请选择 LAN 口如何获取 IP 地址；" ..
	          "本机的 DHCP 服务会被自动关闭，不会与上游路由器的 DHCP 冲突。"))

-- ------------------------------------------------------------------ LAN 口
s = m:section(NamedSection, "lan", "interface", translate("LAN 接口"))
s.anonymous = true
s.addremove = false

o = s:option(ListValue, "proto", translate("获取方式"))
o:value("dhcp", translate("自动获取（DHCP 客户端）"))
o:value("static", translate("固定 IP（静态地址）"))
o.default = "dhcp"
o.rmempty = false
o.description = translate("自动获取：从上游路由器直接拿地址，插上网线就能用。" ..
                          "固定 IP：手动指定地址，适合当网关或需要固定地址的场景。")

o = s:option(Value, "ipaddr", translate("IP 地址"))
o:depends("proto", "static")
o.datatype = "ip4addr"
o.placeholder = "192.168.100.250"

o = s:option(Value, "netmask", translate("子网掩码"))
o:depends("proto", "static")
o.datatype = "ip4addr"
o.default = "255.255.255.0"

o = s:option(Value, "gateway", translate("默认网关"))
o:depends("proto", "static")
o.datatype = "ip4addr"
o.placeholder = "192.168.100.1"

o = s:option(Value, "dns", translate("DNS 服务器"))
o:depends("proto", "static")
o.datatype = "ip4addr"
o.placeholder = "192.168.100.1"

-- ------------------------------------------------------------------ 提交后
function m.on_after_commit(self)
	local u = require "luci.model.uci".cursor()

	-- 旁路由：本机 DHCP 服务始终保持关闭
	u:set("dhcp", "lan", "ignore", "1")
	u:commit("dhcp")

	-- 切回自动获取时清掉静态残留，别在配置里留一堆用不上的字段
	if u:get("network", "lan", "proto") == "dhcp" then
		for _, k in ipairs({ "ipaddr", "netmask", "gateway", "dns" }) do
			u:delete("network", "lan", k)
		end
		u:commit("network")
	end
end

return m
