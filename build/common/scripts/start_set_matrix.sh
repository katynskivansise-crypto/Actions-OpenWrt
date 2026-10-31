#!/bin/bash

if [ ! -f /usr/local/bin/yq ];then
    # 固定版本下载到 /tmp 再 sudo 安装，避免：1) 直接写 /usr/local/bin 权限不足；2) GitHub API 匿名限流
    if ! curl -fsSL --retry 3 -o /tmp/yq_linux_amd64 https://github.com/mikefarah/yq/releases/download/v4.44.3/yq_linux_amd64; then
        curl -sLo /tmp/yq_linux_amd64  $(curl -L https://api.github.com/repos/mikefarah/yq/releases/latest | jq -r '.assets[]|select(.name|match("linux_amd64$"))|.browser_download_url')
    fi
    sudo mv -f /tmp/yq_linux_amd64 /usr/local/bin/yq
    sudo chmod a+x /usr/local/bin/yq
fi

if [ "$1" = set ];then
    repository_dispatch_file=$(grep -rlP '^\s+repository_dispatch:' .github/workflows/ | head -1)
    tr -cd '\11\12\15\40-\176' < ${repository_dispatch_file}  > ${repository_dispatch_file}.new
    #yq '.on.workflow_dispatch.inputs' ${repository_dispatch_file}.new > input.yml
    yq '.on.workflow_dispatch.inputs|to_entries|.[]|{.key: .value.default}' ${repository_dispatch_file}.new > /tmp/var.yml


    # 不为空则是 input 触发
    if [ -n "$(yq '.event.inputs //""' /tmp/github)" ];then
        yq -P '.event.inputs' /tmp/github >> /tmp/var.yml
    fi

    # 不为空则是 dispatch 触发
    if [ -n "$(yq '.event.client_payload //""' /tmp/github)" ];then
        yq -P '.event.client_payload' /tmp/github | sed -r 's#^device:#target:#' >> /tmp/var.yml
    fi

    sed -r 's#: #=#' /tmp/var.yml > /tmp/var.sh

    tac /tmp/var.yml | awk '!a[$1]++' | yq -o=json -I=0 > /tmp/var.json

    source /tmp/var.sh

    if [ ! -d "${GITHUB_WORKSPACE}/build/${target}" ];then
        echo "no such target: ${target}"
        exit 2
    fi

    echo config: ${config}
    if [ -z "${repo_json}" ] ;then
        bash ${GITHUB_WORKSPACE}/build/${target}/set_matrix.sh
    else # [{"name":"openwrt","branch":"master","addr":"https://github.com/openwrt/openwrt"}]
        echo "matrix=${repo_json}" >> $GITHUB_OUTPUT
    fi

    echo "input=$(cat /tmp/var.json)" >> $GITHUB_OUTPUT

    cat /tmp/var.json
fi

if [ ! -f /tmp/var.sh ];then
    # 用 jq 生成干净 key=value 赋值。
    # 原 yq -P + sed 会产出带花括号/引号/逗号的非法 shell 赋值（如 "target"="r2s",），source 时直接 command not found(127)
    jq -r 'to_entries[] | "\(.key)=\(.value)"' /tmp/github.json > /tmp/var.sh
    cat /tmp/var.sh
    source /tmp/var.sh
    cat /tmp/var.sh >>  $GITHUB_ENV
fi
