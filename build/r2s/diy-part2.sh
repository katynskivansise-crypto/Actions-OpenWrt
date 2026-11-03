#!/bin/bash
# Copyright (c) 2019‑2026 P3TERX <https://p3terx.com>
# MIT License
# File name: diy-part2.sh
# Desc: Post‑feeds ImmortalWrt‑25.12 | NanoPi‑R2S
# 保留kenzok8 feeds源，自动清理损坏不兼容软件包
# luci‑theme‑argon=y 内置固件作为默认web主题

[ -f "$GITHUB_ENV" ] && source "$GITHUB_ENV"
kernel_ver=$(grep -Po '^KERNEL_PATCHVER=\K\S+' target/linux/rockchip/Makefile)

# R2S DMC调频，优化千兆网络转发性能
if [ "$build_target" = r2s ];then
    patch_file="./target/linux/rockchip/patches-${kernel_ver}/nanopi-r2s-dmc-.patch"
    if [ -f "$patch_file" ];then
        sed -ri '/auto-freq-en/s#0#1#' "$patch_file"
        echo "[INFO] DMC调频已开启"
    fi
fi

### 自定义包合并函数【修复：URL截取仓库名语法错误、git clone分支参数】
# 参数1：完整git仓库URL；参数2：额外需要删除的包名(可为空)；参数3：git分支(默认main)
merge_package(){
    set -e
    local pn="$1"
    local del_name="$2"
    local branch="${3:-main}"
    # 截取URL最后一段作为本地目录名，##*/ 匹配最后一个/及前面全部字符
    pn=${pn##*/}
    find package/ -follow -name "${pn}" -not -path "package/custom/*" | xargs -rt rm -rf
    if [ ! -z "$del_name" ]; then
        find package/ -follow -name "${del_name}" -not -path "package/custom/*" | xargs -rt rm -rf
    fi

    if [[ $1 == *'/trunk/'* || $1 == *'/branches/'* ]]; then
        svn export "$1"
    else
        git clone --depth=1 -b "${branch}" --single-branch "$1"
        rm -rf "${pn}/.git"
    fi
    mv "${pn}" package/custom/
    set +e
}

rm -rf package/custom
mkdir -p package/custom

# 清理kenzok8 feeds中存在依赖问题、无法编译的软件包
find package/feeds -type d -name "luci-app-fchomo" | xargs -rt rm -rf
find package/feeds -type d -name "luci-app-weechat" | xargs -rt rm -rf
find package/feeds -type d -name "dae" | xargs -rt rm -rf
find package/feeds -type d -name "daed" | xargs -rt rm -rf
find package/feeds -type d -name "luci-app-dae" | xargs -rt rm -rf
find package/feeds -type d -name "luci-app-daed" | xargs -rt rm -rf
find package/feeds -type d -name "trojan-plus" | xargs -rt rm -rf
find package/feeds -type d -name "luci-app-dockerman" | xargs -rt rm -rf

# ImmortalWrt公共处理：删除无关设备编译配置，减少编译扫描项
if [ "$repo_name" = 'lede' ] || [ "$repo_name" = 'immortalwrt' ];then
    sed -ri '/^\s*TARGET_DEVICES\s.+?(fastrhino_r66s|firefly_station-p2|friendlyelec_nanopi-r5s)/d' target/linux/rockchip/image/armv8.mk
fi

# 拉取第三方LuCI插件源码
merge_package "https://github.com/vernesong/OpenClash" "" "master"
merge_package "https://github.com/lisaac/luci-app-dockerman"

# R2S：拉取OLED控制面板插件
# I2C内核驱动已内置固件；i2c‑tools、libi2c编译apk，刷机后手动安装使用
if [ "$build_target" = r2s ];then
    merge_package https://github.com/NateLol/luci-app-oled
    # 修复中文翻译目录名称 zh_Hans → zh‑cn
    if [ -d package/custom/luci-app-oled/po/zh_Hans ];then
        mv package/custom/luci-app-oled/po/zh_Hans package/custom/luci-app-oled/po/zh-cn
    fi
fi

# R2S PWM风扇温控脚本部署
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

# 适配unblockneteasemusic，适配proc‑ng‑ps，修改ps调用参数
lua_file=$(find -type f -name unblockneteasemusic.lua)
[ -n "$lua_file" ] && sed -ri '/sys.call.+"ps /s#ps -w#ps aux#' "$lua_file"

# 预置files目录，文件合并进固件rootfs
mkdir -p files/
mkdir -p files/etc/uci-defaults/

# 导入开机自动执行uci‑defaults脚本
if [ -n "${GITHUB_WORKSPACE}" ] && [ -d "${GITHUB_WORKSPACE}/scripts/uci-defaults" ];then
    cp ${GITHUB_WORKSPACE}/scripts/uci-defaults/* files/etc/uci-defaults/
    chmod a+x files/etc/uci-defaults/*
fi

# 执行外部预置资源脚本，文件不存在不中断流程
if [ -n "${GITHUB_WORKSPACE}" ] && [ -d "${GITHUB_WORKSPACE}/scripts/files" ];then
    [ -f "${GITHUB_WORKSPACE}/scripts/files/adh.sh" ] && source "${GITHUB_WORKSPACE}/scripts/files/adh.sh"
    [ -f "${GITHUB_WORKSPACE}/scripts/files/openclash.sh" ] && source "${GITHUB_WORKSPACE}/scripts/files/openclash.sh"
    [ -f "${GITHUB_WORKSPACE}/scripts/files/pwmfan.sh" ] && source "${GITHUB_WORKSPACE}/scripts/files/pwmfan.sh"
fi

# 固件内置升级脚本
if [ -n "${GITHUB_WORKSPACE}" ] && [ -f "${GITHUB_WORKSPACE}/build/scripts/update.sh" ];then
    \cp -a ${GITHUB_WORKSPACE}/build/scripts/update.sh files/
fi

echo "==== diy‑part2.sh 执行结束，请运行 make defconfig && ./scripts/diffconfig.sh 校验配置 ===="
