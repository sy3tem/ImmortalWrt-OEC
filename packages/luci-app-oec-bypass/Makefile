#
# luci-app-oec-bypass - LuCI app: single-NIC bypass router setup for OEC
#
# Copyright (C) 2026
# SPDX-License-Identifier: Apache-2.0
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-oec-bypass
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=OEC

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-oec-bypass
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=OEC bypass router setup (single NIC)
  DEPENDS:=+luci-base +luci-compat
  PKGARCH:=all
endef

define Package/luci-app-oec-bypass/description
  Single-NIC bypass router setup for the OneThing Edge Cube (OEC) / RK3566.

  Adds "Network -> Bypass Router" to LuCI, where the LAN port can be switched
  between a DHCP client (automatic address) and a static address.

  The local dnsmasq DHCP server is kept disabled, so the box never competes
  with the upstream router for DHCP -- that is what makes it a bypass router
  instead of a second DHCP server on the LAN.
endef

define Build/Compile
endef

define Package/luci-app-oec-bypass/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/oec_bypass.lua $(1)/usr/lib/lua/luci/controller/oec_bypass.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/oec
	$(INSTALL_DATA) ./luasrc/model/cbi/oec/bypass.lua $(1)/usr/lib/lua/luci/model/cbi/oec/bypass.lua
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/99-oec-net $(1)/etc/uci-defaults/99-oec-net
endef

$(eval $(call BuildPackage,luci-app-oec-bypass))
