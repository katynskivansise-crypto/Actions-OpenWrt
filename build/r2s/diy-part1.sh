#!/bin/bash
# Copyright (c) 2019‑2020 P3TERX <https://p3terx.com>
# MIT License
# File name: diy-part1.sh
# Desc: Pre‑feeds ImmortalWrt‑25.12；保留kenzok8 feeds，diy‑part2清理坏包

# 修改默认网关 192.168.1.1 → 192.168.2.1
sed -i 's/192.168.1.1/192.168.2.1/g' package/base-files/files/bin/config_generate

# 设置时区 CST‑8 / Asia/Shanghai
sed -i "s/timezone='UTC'/timezone='CST-8'/" package/base-files/files/bin/config_generate
sed -i "/timezone='CST-8'/a \ \ \ \ set system.@system[-1].zonename='Asia/Shanghai'" package/base-files/files/bin/config_generate

# 启用kenzok8第三方feeds源
echo "src-git small https://github.com/kenzok8/small" >> feeds.conf.default
echo "src-git others https://github.com/kenzok8/openwrt-packages" >> feeds.conf.default
