#!/bin/bash
# Copyright (c) 2019‑2026 P3TERX <https://p3terx.com>
# MIT License
# File name: diy-part2.sh
# Desc: Post‑feeds ImmortalWrt‑25.12；保留kenzok8 feeds，自动清理损坏不兼容包；NanoPi‑R2S

[ -f "$GITHUB_ENV" ] && source "$GITHUB_ENV"
kernel_ver=$(grep -Po '^KERNEL_PATCHVER=\K\S+' target/linux/rockchip/Makefile)

# R2S DMC调频补丁，优化千兆转发性能
if [ "$build_target" = r2s ];then
    patch_file="./target/linux/rockchip/patches-${kernel_ver}/nanopi-r2s-dmc-.patch"
    if [ -f "$patch_file" ];then
        sed -ri '/auto-freq-en/s#0#1#' "$patch_file"
        echo "[INFO] DMC调频已开启"
    fi
fi

### 自定义包合并函数
merge_package(){
    set -e
    local pn="$1"
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
    set +e
}

rm -rf package/custom
mkdir -p package/custom

# ==============================
# 清理kenzok8 feeds损坏/不兼容包，解决递归依赖、缺失依赖警告
# ==============================
find package/feeds -type d -name "luci-app-fchomo" | xargs -rt rm -rf
find package/feeds -type d -name "luci-app-weechat" | xargs -rt rm -rf
find package/feeds -type d -name "dae" | xargs -rt rm -rf
find package/feeds -type d -name "daed" | xargs -rt rm -rf
find package/feeds -type d -name "luci-app-dae" | xargs -rt rm -rf
find package/feeds -type d -name "luci-app-daed" | xargs -rt rm -rf
find package/feeds -type d -name "trojan-plus" | xargs -rt rm -rf
find package/feeds -type d -name "luci-app-dockerman" | xargs -rt rm -rf

# Lede / ImmortalWrt 公共处理
if [ "$repo_name" = 'lede' ] || [ "$repo_name" = 'immortalwrt' ];then
    sed -ri '/^\s*TARGET_DEVICES\s.+?(fastrhino_r66s|firefly_station-p2|friendlyelec_nanopi-r5s)/d' target/linux/rockchip/image/armv8.mk
    patch_src="${GITHUB_WORKSPACE}/build/${build_target}/patches/953-net-patch-linux-kernel-to-support-shortcut-fe.patch"
    patch_dst="target/linux/generic/hack-6.18/953-net-patch-linux-kernel-to-support-shortcut-fe.patch"
    if [ -n "${GITHUB_WORKSPACE}" ] && [ -f "$patch_src" ];then
        cp -f "$patch_src" "$patch_dst"
        echo "[INFO] shortcut‑fe补丁已覆盖,内核 ${kernel_ver}"
    fi
fi

# 拉取第三方插件（覆盖feeds被删除的dockerman）
merge_package "-b 18.06 https://github.com/jerrykuku/luci-theme-argon"
merge_package "https://github.com/jerrykuku/luci-app-argon-config"
merge_package "https://github.com/vernesong/OpenClash"
merge_package "https://github.com/lisaac/luci-app-dockerman"

# R2S：拉取 luci‑app‑oled
if [ "$build_target" = r2s ];then
    merge_package https://github.com/NateLol/luci-app-oled
    if [ -d package/custom/luci-app-oled/po/zh_Hans ];then
        mv package/custom/luci-app-oled/po/zh_Hans package/custom/luci-app-oled/po/zh-cn
    fi
fi

# R2S PWM风扇温控部署
if [ "$build_target" = r2s ];then
    FAN_BASE="target/linux/rockchip/armv8/base-files/usr/bin"
    mkdir -p "${FAN_BASE}"
    wget -q -O fancontrol.patch https://github.com/friendlyarm/friendlywrt/commit/cebdc1f94dcd6363da3a5d7e1e69fd741b8b718e.patch
    if [ -f fancontrol.patch ];then
        git apply fancontrol.patch 2>/dev/null
        sed -i 's/pwmchip1/pwmchip0/' "${FAN_BASE}/fa-fancontrol.sh" "${FAN_BASE}/fa-fancontrol-direct.sh"
        rm -f fancontrol.patch
        echo "[INFO] 风扇温控脚本部署完成"
    else
        echo "[WARN] 下载风扇补丁失败，跳过风扇温控功能"
    fi
fi

# unblockneteasemusic适配proc‑ng‑ps
lua_file=$(find -type f -name unblockneteasemusic.lua)
[ -n "$lua_file" ] && sed -ri '/sys.call.+"ps /s#ps -w#ps aux#' "$lua_file"

# files目录预置文件合并进rootfs
mkdir -p files/
mkdir -p files/etc/uci-defaults/

if [ -n "${GITHUB_WORKSPACE}" ] && [ -d "${GITHUB_WORKSPACE}/scripts/uci-defaults" ];then
    cp ${GITHUB_WORKSPACE}/scripts/uci-defaults/* files/etc/uci-defaults/
    chmod a+x files/etc/uci-defaults/*
fi

if [ -n "${GITHUB_WORKSPACE}" ] && [ -d "${GITHUB_WORKSPACE}/scripts/files" ];then
    [ -f "${GITHUB_WORKSPACE}/scripts/files/adh.sh" ] && source "${GITHUB_WORKSPACE}/scripts/files/adh.sh"
    [ -f "${GITHUB_WORKSPACE}/scripts/files/openclash.sh" ] && source "${GITHUB_WORKSPACE}/scripts/files/openclash.sh"
    [ -f "${GITHUB_WORKSPACE}/scripts/files/pwmfan.sh" ] && source "${GITHUB_WORKSPACE}/scripts/files/pwmfan.sh"
fi

if [ -n "${GITHUB_WORKSPACE}" ] && [ -f "${GITHUB_WORKSPACE}/build/scripts/update.sh" ];then
    \cp -a ${GITHUB_WORKSPACE}/build/scripts/update.sh files/
fi

echo "==== diy‑part2.sh 执行结束，请运行 make defconfig && ./scripts/diffconfig.sh 校验配置 ===="
