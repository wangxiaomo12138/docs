#!/bin/bash
set -euo pipefail

## 参数说明【调试版】
# $1 = USER_ID
# $2 = SESSION_ID 【可以传空；为空脚本自动生成session，仅调试使用！！】
# $3 = 用户提问文本

USER_ID="$1"
SESSION_ID="${2:-}"
USER_PROMPT="$3"

# ========== 调试用：SESSION_ID为空就自动生成 ==========
if [ -z "${SESSION_ID}" ]; then
    SESSION_ID="debug_sess_${USER_ID}_$(date +%s)"
    echo "【调试模式】未传入SESSION_ID，自动生成：${SESSION_ID}" >&2
fi

# 必须重新设置全套环境！进程隔离！！
NAS_DATA_ROOT="/home/data/${USER_ID}"
export XDG_DATA_HOME="${NAS_DATA_ROOT}"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
export PATH="${SCRIPT_DIR}/bin:${PATH}"
export XDG_CONFIG_HOME="${SCRIPT_DIR}/config"
export XDG_CACHE_HOME="${SCRIPT_DIR}/cache"
export HOME="${SCRIPT_DIR}/home"

# 参数校验
if [ -z "${USER_ID}" ]; then
    echo "参数错误：第一个参数必须传入USER_ID" >&2
    exit 1
fi
if [ -z "${USER_PROMPT}" ]; then
    echo "参数错误：第三个参数为用户提问内容" >&2
    exit 1
fi

echo "====对话启动参数====" >&2
echo "USER_ID     : ${USER_ID}" >&2
echo "SESSION_ID  : ${SESSION_ID}" >&2
echo "PROMPT      : ${USER_PROMPT}" >&2
echo "DATA_ROOT   : ${NAS_DATA_ROOT}" >&2
echo "====================" >&2

cd "${SCRIPT_DIR}"

# 整条链路：关闭缓冲执行opencode run，输出交给python包装脚本生成流式JSON
stdbuf -i0 -o0 -e0 ./bin/opencode run --session-id "${SESSION_ID}" "${USER_PROMPT}" | stdbuf -o0 python3 ./stream_wrapper.py