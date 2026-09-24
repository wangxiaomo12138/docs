#!/bin/bash
set -euo pipefail

# 1.读取平台注入的 USER_ID，调试兜底 user01
USER_ID=${USER_ID:-user01}
NAS_DATA_ROOT="/home/data/${USER_ID}"

echo "当前实例的 ID: ${USER_ID}" >&2
echo "NAS 挂载目录: ${NAS_DATA_ROOT}" >&2

# 2.等待 NAS 挂载就绪
wait_mount() {
    local MAX_WAIT=24
    for ((i=1; i<=MAX_WAIT; i++)); do
        if mount -q "${NAS_DATA_ROOT}"; then
            echo "NAS 挂载成功，挂载点在 ${NAS_DATA_ROOT}" >&2
            return
        fi
        echo "NAS 未挂载，等待 ${i}/${MAX_WAIT} s" >&2
        sleep 1
    done
    echo "警告：NAS 等待超时 ${MAX_WAIT} 秒" >&2
    exit 1
}

wait_mount

# OpenCode持久化目录：会话、日志、skill配置
export XDG_DATA_HOME="${NAS_DATA_ROOT}"
echo "XDG_DATA_HOME=${XDG_DATA_HOME}" >&2

mkdir -p "${NAS_DATA_ROOT}"
chmod -R u+rw "${NAS_DATA_ROOT}"
echo "OpenCode的数据、配置目录配置到XDG路径" >&2

# 获取脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# 环境变量配置
export PATH="${SCRIPT_DIR}/bin:${PATH}"
export XDG_CONFIG_HOME="${SCRIPT_DIR}/config"
export XDG_CACHE_HOME="${SCRIPT_DIR}/cache"
export HOME="${SCRIPT_DIR}/home"

# OpenCode离线模式环境变量
export OPENCODE_MODELS_UI_FILE="${SCRIPT_DIR}/data/models"
export OPENCODE_DISABLE_AUTOUPDATE="true"

# 终端兼容性
export TERM=${TERM:-xterm-256color}

# 初始化缓存
init_cache() {
    if [ ! -d "${XDG_CACHE_HOME}/opencode/node_modules" ]; then
        mkdir -p "${XDG_CACHE_HOME}/opencode"
        if [ -d "${SCRIPT_DIR}/cache/opencode/node_modules" ]; then
            cp -r "${SCRIPT_DIR}/cache/opencode/node_modules" "${XDG_CACHE_HOME}/opencode/"
        fi
    fi

    if [ ! -d "${XDG_CONFIG_HOME}/opencode/node_modules" ]; then
        mkdir -p "${XDG_CONFIG_HOME}/opencode"
        if [ -d "${SCRIPT_DIR}/cache/opencode/node_modules" ]; then
            cp -r "${SCRIPT_DIR}/cache/opencode/node_modules" "${XDG_CONFIG_HOME}/opencode/"
        fi
    fi

    cat > "${XDG_CONFIG_HOME}/opencode/package.json" <<EOF
{
    "name": "opencode-config-fake",
    "private": true,
    "dependencies": {}
}
EOF
    echo "缓存就绪" >&2
}

init_cache

echo "沙箱初始化全部完成，进入空闲待命状态，等待业务command调用" >&2
# sleep infinity作为PID1，保持沙箱常驻，不启动WebUI
exec sleep infinity