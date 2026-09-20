-- Copyright (C) 2026
-- SPDX-License-Identifier: Apache-2.0
--
-- LuCI controller:  网络 -> 旁路由设置
--
-- 写法参照 luci-app-openclash：本固件的 LuCI 是 JS 内核 + luci-compat
-- 提供的 Lua 兼容层，Lua 的 entry()/form() 会被兼容层挂进菜单树。

module("luci.controller.oec_bypass", package.seeall)

function index()
	-- network 配置尚未生成时（首次启动的极早阶段）不注册菜单
	if not nixio.fs.access("/etc/config/network") then
		return
	end

	local page = entry({"admin", "network", "oec_bypass"},
		form("oec/bypass"), _("旁路由设置"), 60)

	page.dependent = false
	page.leaf = true
end
