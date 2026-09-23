#!/bin/bash
# call_api.sh
# 参数1：USER_ID
# 参数2：用户query
# 参数3：【可选】模型名称，不填则使用默认模型

# 入参接收
USER_ID="$1"
USER_QUERY="$2"
MODEL_INPUT="$3"

# 设置默认模型（改成你openCode.json里其中一个模型名字）
DEFAULT_MODEL="model-a"

# 判断是否传入模型，有传入就覆盖
if [ -n "${MODEL_INPUT}" ]; then
    USE_MODEL="${MODEL_INPUT}"
else
    USE_MODEL="${DEFAULT_MODEL}"
fi

# 参数校验
if [ -z "${USER_ID}" ] || [ -z "${USER_QUERY}" ];then
    echo "ERROR: 参数缺失！"
    echo "用法："
    echo "  不指定模型：bash call_api.sh <USER_ID> <query>"
    echo "  指定模型：bash call_api.sh <USER_ID> <query> <model-name>"
    echo "示例："
    echo "  bash call_api.sh user01 \"1+1等于几\""
    echo "  bash call_api.sh user01 \"写一段简短文案\" model-b"
    exit 1
fi

SERVER_URL="http://127.0.0.1:3096"

# jq 安全构造JSON，自动转义特殊字符
BODY=$(jq -n \
  --arg msg "${USER_QUERY}" \
  --arg model "${USE_MODEL}" \
  '{
    "model": $model,
    "stream": false,
    "messages": [{"role":"user","content":$msg}]
  }')

# 发起请求
curl -X POST "${SERVER_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d "${BODY}"