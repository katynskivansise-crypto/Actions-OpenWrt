# 原 sensec/luci-app-udp2raw 为 2018 年老包，已不再使用：
# 1) GitHub 已移除 Subversion 桥接，svn export .../trunk 无法访问；
# 2) 老包 Makefile 不兼容 apk（opkg→apk）及新源码。
#
# udp2raw 核心程序由官方 feeds(net/udp2raw) 提供，
# 在配置中开启 CONFIG_PACKAGE_udp2raw 即可（已在 config.buildinfo 中改为核心包）。
true
