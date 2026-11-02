#!/bin/bash
#
# Copyright (c) 2019-2026 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

[ -f "$GITHUB_ENV" ] && source $GITHUB_ENV

kernel_ver=$(grep -Po '^KERNEL_PATCHVER=\K\S+' target/linux/rockchip/Makefile)

if [ "$build_target" = r2s ];then
    # dmc 调频，开了让跑满千兆
    if ls -l ./target/linux/rockchip/patches-${kernel_ver}/*nanopi-r2s*-dmc-*.patch 2>/dev/null;then
        sed -ri '/auto-freq-en/s#0#1#' ./target/linux/rockchip/patches-${kernel_ver}/*nanopi-r2s*-dmc-*.patch
    fi
fi

function merge_package(){
    local repo_url=$1
    local pn=${repo_url##*/}
    local pkg_name=${2:-$pn}
    local git_param=${3:-"--depth=1 --single-branch"}

    find package/ -follow -name $pkg_name -not -path "package/custom/*" | xargs -rt rm -rf

    if [[ $repo_url == *'/trunk/'* || $repo_url == *'/branches/'* ]]; then
        svn export $repo_url
    else
        git clone $git_param $repo_url
        rm -rf $pn/.git
    fi
    mv $pn package/custom/
}

rm -rf package/custom; mkdir package/custom

if [ "$repo_name" = 'lede' ];then
    if [ "$kernel_ver" = '5.10' ] || [ "$kernel_ver" = '5.4' ];then
        sed -ri '/=CONFIG_CRYPTO_LIB_BLAKE2S/{n;s/HIDDEN:=1/DEPENDS:=@(LINUX_5_4||LINUX_5_10)/;}' package/kernel/linux/modules/crypto.mk
        for SED_NUM in $( grep -En 'blake2s(|-generic|-arm).ko' package/kernel/linux/modules/crypto.mk | awk -F: '$0~":"{print $1}');do
            sed -ri "${SED_NUM}s#@lt5.9##" package/kernel/linux/modules/crypto.mk
        done
    fi

    kernel_ver=$(grep -Po '^KERNEL_PATCHVER=\K\S+' target/linux/rockchip/Makefile)
    if echo "$kernel_ver" | grep -Pq '5.1[589]';then
        sed -ri '/kmod-(ath6kl|carl9170|libertas-usb|rsi91x)/d' .config
    fi

    sed -ri '/^\s*TARGET_DEVICES\s.+?(fastrhino_r66s|firefly_station-p2|friendlyelec_nanopi-r5s)/d' target/linux/rockchip/image/armv8.mk

    if [ -f "${GITHUB_WORKSPACE}/build/${build_target}/patches/953-net-patch-linux-kernel-to-support-shortcut-fe.patch" ];then
        cp -f ${GITHUB_WORKSPACE}/build/${build_target}/patches/953-net-patch-linux-kernel-to-support-shortcut-fe.patch \
              target/linux/generic/hack-6.18/953-net-patch-linux-kernel-to-support-shortcut-fe.patch
        echo "==> 已用修复版覆盖 953 shortcut-fe 补丁（适配内核 $(grep -Po '^KERNEL_PATCHVER=\K\S+' target/linux/rockchip/Makefile)）"
    fi
fi

# ========== 新增：immortalwrt 同样移除高危无线驱动 ==========
if [ "$repo_name" = 'immortalwrt' ];then
    sed -ri '/kmod-(ath6kl|carl9170|libertas-usb|rsi91x|zd1211rw)/d' .config
fi

# merge_package(仓库地址,包名,git参数)
merge_package "https://github.com/jerrykuku/luci-theme-argon" "luci-theme-argon" "--depth=1 --single-branch -b 18.06"
merge_package "https://github.com/jerrykuku/luci-app-argon-config" "luci-app-argon-config" "--depth=1 --single-branch"

if [ "$build_target" = r2s ];then
    # Add luci-app-oled (R2S Only)
    merge_package "https://github.com/NateLol/luci-app-oled" "luci-app-oled" "--depth=1 --single-branch"
    # enable r2s oled plugin by default
    sed -ri "s/enable\s+'0'/enable '1'/" package/custom/luci-app-oled/root/etc/config/oled
    # 解决中文问题
    [ -d package/custom/luci-app-oled/po/zh_Hans ] && mv package/custom/luci-app-oled/po/zh_Hans package/custom/luci-app-oled/po/zh-cn
fi

# ========== 风扇补丁【注释掉，可选开启】 ==========
# 这个补丁在immortalwrt大概率失败，需要再调试，先注释，编译稳定后再开
# wget https://github.com/friendlyarm/friendlywrt/commit/cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch
# git apply cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch
# rm cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch
# sed -i 's/pwmchip1/pwmchip0/' target/linux/rockchip/armv8/base-files/usr/bin/fa-fancontrol.sh target/linux/rockchip/armv8/base-files/usr/bin/fa-fancontrol-direct.sh

# unblockneteasemusic ps 兼容修复
lua_file=$(find -type f -name unblockneteasemusic.lua)
[ -n "$lua_file" ] && sed -ri '/sys.call.+"ps /s#ps -w#ps aux#' $lua_file

# ----------- 提前打包一些文件，防止初次使用去下载
mkdir -p files/
mkdir -p files/etc/uci-defaults/
cp ${GITHUB_WORKSPACE}/scripts/uci-defaults/* files/etc/uci-defaults/
chmod a+x files/etc/uci-defaults/*

# 预处理脚本，按需开启，如果仓库没有这些文件会报错，可注释
# source ${GITHUB_WORKSPACE}/scripts/files/adh.sh
# source ${GITHUB_WORKSPACE}/scripts/files/openclash.sh
# source ${GITHUB_WORKSPACE}/scripts/files/pwmfan.sh

for sh_file in $(ls ${GITHUB_WORKSPACE}/scripts/files/*.sh 2>/dev/null);do
    source $sh_file
done

chmod a+x ${GITHUB_WORKSPACE}/build/scripts/*.sh
\cp -a ${GITHUB_WORKSPACE}/build/scripts/update.sh files/
