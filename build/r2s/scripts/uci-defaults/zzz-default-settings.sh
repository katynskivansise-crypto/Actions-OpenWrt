#!/bin/sh

# Change default shell to bash
if [ -f /bin/bash ];then
  sed -i '/^root:/s#/bin/ash#/bin/bash#' /etc/passwd
fi
# 同时开 bash 和 zsh 的话有上面优先
if [ -f /bin/zsh ];then
  sed -i '/^root:/s#/bin/ash#/bin/zsh#' /etc/passwd
fi

# 软件源保持各自官方源默认，不做镜像替换
if command -v apk >/dev/null 2>&1; then
    # ---------- apk 包管理器（ImmortalWrt/OpenWrt 25.12+） ----------
    DIST_APK=/etc/apk/repositories.d/distfeeds.list

    # 安装预置在根目录的 apk（apk 用连字符命名 name-version-r1.apk）
    if ls -l /*.apk >/dev/null 2>&1; then
        apk add --allow-untrusted /*.apk
        rm -f /*.apk
    fi

    # slim 固件：配置本地 apk 源，并注释官方源做离线使用
    if [ -f /local_feed/packages.adb ]; then
        [ -f "$DIST_APK" ] && sed -ri 's@^[^#]@#&@' "$DIST_APK"
        CUSTOM_APK=/etc/apk/repositories.d/customfeeds.list
        grep -q '/local_feed' "$CUSTOM_APK" 2>/dev/null || echo '/local_feed/packages.adb' >> "$CUSTOM_APK"
    fi
else
    # ---------- opkg 包管理器（旧版 / lede） ----------
    DIST_OPKG=/etc/opkg/distfeeds.conf

    # 安装预置在根目录的 ipk（ipk 用下划线命名 name_ver_arch.ipk）
    if ls -l /*_*_*.ipk >/dev/null 2>&1; then
        opkg install /*_*_*.ipk
        rm -f /*_*_*.ipk
    fi

    # slim 固件：配置本地 opkg 源，并注释官方源
    if ls -l /local_feed/*.ipk >/dev/null 2>&1; then
        sed -ri 's@^[^#]@#&@' "$DIST_OPKG"
        grep -E '/local_feed' /etc/opkg/customfeeds.conf || echo 'src/gz local file:///local_feed' >> /etc/opkg/customfeeds.conf
        # 本地源无法签名，关闭签名检查
        sed -ri '/check_signature/s@^[^#]@#&@' /etc/opkg.conf
    fi
fi


if [ -f /etc/uci-defaults/luci-aliyundrive-webdav ];then
    uci set  aliyundrive-webdav.@server[0].enable=0
    uci commit aliyundrive-webdav
fi

# 默认主题
if [ -d /usr/lib/lua/luci/view/themes/argonne/ ];then
    uci set luci.main.mediaurlbase='/luci-static/argonne'
fi
if [ -d /usr/lib/lua/luci/view/themes/argon_blue/ ];then
    uci set luci.main.mediaurlbase='/luci-static/argon_blue'
fi
if [ -d /usr/lib/lua/luci/view/themes/argon/ ];then
    uci set luci.main.mediaurlbase='/luci-static/argon'
fi
uci commit luci
# 此文件名注意ls 排序，下面也行
# sed -ri "/option mediaurlbase/s#(/luci-static/)[^']+#\1argon_blue#" /etc/config/luci
# uci commit luci

if [ -f /etc/config/qbittorrent ];then
    uci set qbittorrent.main.AnnounceToAllTrackers='true'
    uci commit qbittorrent
fi


if ! grep -Eq '120.25.115.20' /etc/config/system;then
  uci add_list system.ntp.server=120.25.115.20
  uci commit system
fi

touch /etc/crontabs/root
chmod 0600 /etc/crontabs/root

# 允许 wan 访问 openwrt web
# uci set uhttpd.main.rfc1918_filter='0'
# uci commit uhttpd

# 允许 wan ssh
uci delete dropbear.@dropbear[0].Interface
uci commit dropbear
# 配合下面的单个端口，或者放行整个段
# iptables -I input_wan_rule -p tcp -m tcp --dport 22 -j ACCEPT
# 二级路由的话放行上层的  CIDR 即可

if ! grep -Eq 'iptables -I input_wan_rule -s \S+\s+-j ACCEPT' /etc/firewall.user;then
cat >> /etc/firewall.user << EOF
# 允许wan口指定网段访问，一般二级路由下需要
iptables -I input_wan_rule -s 192.168.0.0/16  -j ACCEPT
# r2s 只插 wan 下做旁路由时候，wan 的 zone 需要开 forward accept
iptables -I forwarding_wan_rule -s 192.168.0.0/16  -j ACCEPT
EOF
fi

# 使用上面的 iptables 规则理论上也行
# r2s 只插 wan 下做旁路由时候，wan 的 zone 需要开 forward accept
# line=`awk '/config zone/,/^\s*$/{if($2=="name" && $3~"wan"){a=1};if(a==1 && $2=="forward"){print NR}}'  /etc/config/firewall`
# if [ -n "$line" ];then
#     sed -ri "$line"'s#REJECT#ACCEPT#' /etc/config/firewall
# fi

# dnsmasq
uci set dhcp.@dnsmasq[0].rebind_protection='0'
uci set dhcp.@dnsmasq[0].localservice='0'
uci set dhcp.@dnsmasq[0].nonwildcard='0'
if ! grep -Eq '223.5.5.5' /etc/config/dhcp;then
  uci add_list dhcp.@dnsmasq[0].server='223.5.5.5#53'
fi
uci commit dhcp
