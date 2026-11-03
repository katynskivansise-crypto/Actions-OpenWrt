#!/bin/bash
# Copyright (c) 2019‑2026 P3TERX <https://p3terx.com>
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)

[ -f "$GITHUB_ENV" ] && source "$GITHUB_ENV"

kernel_ver=$(grep -Po '^KERNEL_PATCHVER=\K\S+' target/linux/rockchip/Makefile)

# R2S dmc调频，开启后利于跑满千兆
if [ "$build_target" = r2s ];then
    patch_file="./target/linux/rockchip/patches-${kernel_ver}/nanopi-r2s-dmc-.patch"
    if [ -f "$patch_file" ];then
        sed -ri '/auto-freq-en/s#0#1#' "$patch_file"
    fi
fi

### 通用合并自定义包函数
merge_package(){
    local pn=$1
    # 删掉/和它左边，只保留名字
    pn=${pn##/}
    find package/ -follow -name "$pn" -not -path "package/custom/*" | xargs -rt rm -rf
    if [ ! -z "$2" ]; then
        find package/ -follow -name "$2" -not -path "package/custom/*" | xargs -rt rm -rf
    fi

    if [[ $1 == *'/trunk/'* || $1 == *'/branches/'* ]]; then
        svn export "$1"
    else
        git clone --depth=1 --single-branch ${3:-"main"} "$1"
        rm -rf "${pn}/.git"
    fi
    mv "${pn}" package/custom/
}

rm -rf package/custom
mkdir -p package/custom

# ==============================
# 分支判断：lede / immortalwrt 共用驱动修复逻辑
# ==============================
if [ "$repo_name" = 'lede' ] || [ "$repo_name" = 'immortalwrt' ];then
    # blake2s crypto模块适配5.4 /5.10内核
    if [ "$kernel_ver" = '5.10' ] || [ "$kernel_ver" = '5.4' ];then
        sed -ri '/=CONFIG_CRYPTO_LIB_BLAKE2S/{n;s/HIDDEN:=1/DEPENDS:=@(LINUX_5_4||LINUX_5_10)/;}' package/kernel/linux/modules/crypto.mk
        SED_NUM_LIST=$(grep -En 'blake2s(|-generic|-arm).ko' package/kernel/linux/modules/crypto.mk | awk -F: '$0~":"{print $1}')
        for SED_NUM in $SED_NUM_LIST;do
            sed -ri "${SED_NUM}s#@lt5.9##" package/kernel/linux/modules/crypto.mk
        done
    fi

    # 5.15 /5.18 /5.19内核，清除存在兼容性问题无线模块配置行
    kernel_ver=$(grep -Po '^KERNEL_PATCHVER=\K\S+' target/linux/rockchip/Makefile)
    if echo "$kernel_ver" | grep -Pq '5.1[589]';then
        sed -ri '/kmod-(ath6k|carl9170|libertas-usb|rsi91x)/d' .config
    fi

    # 移除无关设备定义，减少编译扫描项
    sed -ri '/^\s*TARGET_DEVICES\s.+?(fastrhino_r66s|firefly_station-p2|friendlyelec_nanopi-r5s)/d' target/linux/rockchip/image/armv8.mk
    fi
fi

# 拉取argon主题
merge_package "https://github.com/jerrykuku/luci-theme-argon"

# R2S Only 拉取luci‑app‑oled
# ⚠️i2c内核模块配置为=m仅编译apk/ipk，固件不内置，不自动开启oled服务
if [ "$build_target" = r2s ];then
    merge_package https://github.com/NateLol/luci-app-oled
    # 注释掉强制开启oled，刷机无i2c模块不会报错
    # sed -ri "s/enable\s+'0'/enable '1'/" package/custom/luci-app-oled/root/etc/config/oled
    # 修复oled中文翻译 zh_Hans → zh‑cn
    if [ -d package/custom/luci-app-oled/po/zh_Hans ];then
        mv package/custom/luci-app-oled/po/zh_Hans package/custom/luci-app-oled/po/zh-cn
    fi
fi

# ==============================
# 风扇温控补丁：friendlywrt专属，immortalwrt路径不一致，全部注释隔离，避免构建失败
# ==============================
#enable fan control
#wget https://github.com/friendlyarm/friendlywrt/commit/cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch
#git apply cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch
#rm cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch
#sed -i 's/pwmchip1/pwmchip0/' target/linux/rockchip/armv8/base-files/usr/bin/fa-fancontrol.sh target/linux/rockchip/armv8/base-files/usr/bin/fa-fancontrol-direct.sh

# unblockneteasemusic适配proc‑ng‑ps，替换ps调用参数
lua_file=$(find -type f -name unblockneteasemusic.lua)
[ -n "$lua_file" ] && sed -ri '/sys.call.+"ps /s#ps -w#ps aux#' "$lua_file"

# ==============================
# 提前打包预置文件，合并进rootfs
# ==============================
mkdir -p files/
mkdir -p files/etc/uci-defaults/

# 复制uci‑defaults开机预置脚本
if [ -n "${GITHUB_WORKSPACE}" ] && [ -d "${GITHUB_WORKSPACE}/scripts/uci-defaults" ];then
    cp ${GITHUB_WORKSPACE}/scripts/uci-defaults/* files/etc/uci-defaults/
    chmod a+x files/etc/uci-defaults/*
fi

# 预处理下载相关脚本
if [ -n "${GITHUB_WORKSPACE}" ] && [ -d "${GITHUB_WORKSPACE}/scripts/files" ];then
    source ${GITHUB_WORKSPACE}/scripts/files/adh.sh
    source ${GITHUB_WORKSPACE}/scripts/files/openclash.sh
    source ${GITHUB_WORKSPACE}/scripts/files/pwmfan.sh
fi

# 升级脚本放入固件
if [ -n "${GITHUB_WORKSPACE}" ] && [ -f "${GITHUB_WORKSPACE}/build/scripts/update.sh" ];then
    \cp -a ${GITHUB_WORKSPACE}/build/scripts/update.sh files/
fi
