#!/bin/bash
# call_api.sh
# 参数1：USER_ID
# 参数2：用户query

# 接收入参
USER_ID="$1"
USER_QUERY="$2"

# 参数校验
if [ -z "${USER_ID}" ] || [ -z "${USER_QUERY}" ];then
    echo "ERROR: 参数缺失！用法：bash call_api.sh <USER_ID> <query>"
    echo "示例：bash call_api.sh user01 \"简单介绍AIO沙箱\""
    exit 1
fi

# OpenCode本地服务地址
SERVER_URL="http://127.0.0.1:3096"
# 替换成你真实的模型名称
MODEL_NAME="your-model-name"

# 使用jq安全构建json，自动转义引号等特殊字符
BODY=$(jq -n \
  --arg msg "${USER_QUERY}" \
  --arg model "${MODEL_NAME}" \
  '{
    "model": $model,
    "stream": false,
    "messages": [{"role":"user","content":$msg}]
  }')

# 发起POST请求
curl -X POST "${SERVER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "${BODY}"