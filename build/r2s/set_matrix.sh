#!/bin/bash
# 输出纯净JSON矩阵，使用新版GITHUB_OUTPUT，无多余转义
# matrix_json='[{"name":"lede","branch":"master","addr":"https://github.com/coolsnowwolf/lede"},{"name":"immortalwrt","branch":"openwrt-25.12","addr":"https://github.com/immortalwrt/immortalwrt"}]'
matrix_json='[{"name":"immortalwrt","branch":"openwrt-25.12","addr":"https://github.com/immortalwrt/immortalwrt"}]'
echo "matrix=$matrix_json" >> $GITHUB_OUTPUT
