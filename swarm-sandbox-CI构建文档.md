# swarm-sandbox CI 构建文档

> 本文档还原 swarm-sandbox 项目的三个核心构建文件，并说明它们之间的调用与依赖关系。

---

## 一、文件总览

| 文件 | 所在位置 | 角色 | 生成方式 |
|------|----------|------|----------|
| `cloudbuild.yaml` | 代码仓库根目录（流水线配置） | CI 流水线定义，调度整个构建流程 | 开发/运维编写，纳入版本控制 |
| `swarm-sandbox/scripts/build.sh` | 代码仓库内 | 打包脚本，收集资源并产出部署包 | 开发编写，纳入版本控制 |
| `Dockerfile` | 代码仓库根目录 | 容器镜像构建描述文件 | 开发编写，纳入版本控制（**不是 build.sh 生成的**） |
| `entrypoint.sh` | 代码仓库内 | 容器启动入口脚本 | 开发编写，纳入版本控制 |
| `swarm-sandbox.tar.gz` | 构建产出（release_package/） | 业务程序压缩包 | build.sh 执行 tar 打包生成 |
| `swarm-sandbox.tar.gz.cms` | 构建产出（release_package/） | tar 包的数字签名文件 | 流水线 POST_BUILD 阶段 signclient 生成 |

---

## 二、cloudbuild.yaml（CI 流水线定义）

```yaml
# 流水线语法版本，CloudBuild2.0 平台规范
version: 2.0

env:
  # 环境标签：BPIT 体系、JDK21 的 Docker 构建环境
  label: BPIT_Build_Docker_jdk21

# 流水线全局参数，用于版本追溯与平台识别
params:
  - name: product
    value: cloudbuild2.0          # 归属产品：cloudbuild2.0 构建平台
  - name: CB_AUTO_CHECK_VERSION
    value: "2.0"                  # 版本自动校验规则版本
  - name: BC_NEXT3RD_VERSION
    value: 2.0.0                  # 当前组件版本号
  - name: BASE_COMMIT
    value: "623f112"              # 源码基线 commit hash，用于代码版本追溯

# 流水线执行步骤：构建前 / 构建中 / 构建后
steps:
  # ── 构建前置阶段 ──
  PRE_BUILD:
    - checkout                    # 检出源码，拉取代码仓库全部文件到构建机

  # ── 核心构建阶段 ──
  BUILD:
    - build_execute:
        # 调用仓库内的打包脚本
        command: sh swarm-sandbox/scripts/build.sh
        accelerate: false         # 关闭构建缓存加速，每次全量构建
        check:
          mode: sync              # 同步模式执行代码检查，不通过则终止流水线
          sourcecheck:
            - project_type: python
              project_dir: requirements.txt   # 源码扫描：Python 项目
          dependency:
            - tool_type: python
              project_dir: requirements.txt   # 依赖检查：校验 Python 依赖包

  # ── 构建后置阶段（build.sh 成功后执行）──
  POST_BUILD:
    # 1. 制品签名：对 build.sh 产出的文件做安全签名，防篡改
    - sh:
        command: |
          signclient "swarm-sandbox/release_package/swarm-sandbox.tar.gz"
          signclient "swarm-sandbox/release_package/Dockerfile"

    # 2. 上传业务包 + 签名文件到云制品库
    - artget:
        artifact_type: cloudartifact
        action: push
        file_path: "package,swarm-sandbox/release_package/swarm-sandbox.tar.gz;cms,swarm-sandbox/release_package/swarm-sandbox.tar.gz.cms"
        version_output_path: .

    # 3. 单独上传 Dockerfile 到云制品库
    - artget:
        artifact_type: cloudartifact
        action: push
        file_path: "package,swarm-sandbox/release_package/Dockerfile"
        version_output_path: .

    # 4. 固化版本信息，写入制品元数据
    - version_set
```

---

## 三、swarm-sandbox/scripts/build.sh（打包脚本）

```bash
#!/bin/bash
set -e

# ============================================================
# swarm-sandbox 打包脚本
# 由 cloudbuild.yaml 在 BUILD 阶段调用执行
# 职责：生成构建编号、写入版本信息、打包业务资源到 release_package/
# ============================================================

# ── 1. 生成 buildNumber（构建号）──
if [ -z ${buildNumber} ]; then
  if [ -e /proc/sys/kernel/random/uuid ] && [ -r /proc/sys/kernel/random/uuid ]; then
    # Linux 内核 uuid 文件存在且可读：取 uuid → cksum 校验和 → 取第一个字段
    build=`cat /proc/sys/kernel/random/uuid | cksum | cut -f1 -d " "`
  else
    # 无内核 uuid，使用 bash 内置随机数
    build=${RANDOM}
  fi
  # 当前时间戳 YYYYmmddHHMMSS
  datetime=`date +%Y%m%d%H%M%S`
  # 拼接：时间戳.随机串
  buildNumber="${datetime}.${build}"
else
  # 外部已传入 buildNumber，直接复用
  buildNumber="${buildNumber}"
fi

SERVICE_NAME="swarm-sandbox"
echo "Release is ${isRelease}"

# ── 2. 判断版本类型：快照版 / 正式发布版 ──
if [ "${isRelease}"x = "false"x ]; then
  # 快照版本：1.0.0-SNAPSHOT，后缀带上 buildNumber
  SERVICE_VERSION='1.0.0-SNAPSHOT'
  echo "buildVersion=${SERVICE_VERSION}.${buildNumber}" > buildInfo.properties
elif [ "${isRelease}"x = "true"x ]; then
  # 正式发布：版本号使用外部变量 releaseVersion，不带 buildNumber
  SERVICE_VERSION=${releaseVersion}
  echo "buildVersion=${SERVICE_VERSION}" > buildInfo.properties
fi

# ── 3. 定位项目根目录 ──
# $0 是当前脚本路径，dirname 取脚本所在目录，/.. 上跳一级得到项目根目录
SANDBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# ── 4. 创建输出目录并打包 ──
echo "=== 打包 ==="
mkdir -p "${SANDBOX_DIR}/release_package"
cd "${SANDBOX_DIR}"

# 将 Dockerfile、entrypoint.sh、requirements.txt、app/ 目录打包为 tar.gz
# 注意：Dockerfile 是仓库里已有的文件，这里只是把它打进 tar 包
tar -czf release_package/swarm-sandbox.tar.gz \
  Dockerfile entrypoint.sh requirements.txt app/

# 额外单独复制一份 Dockerfile 到 release_package 目录
# 目的：让流水线 POST_BUILD 阶段可以单独签名、单独上传 Dockerfile
cp Dockerfile release_package/Dockerfile

echo "=== 完成 ==="
echo "  tar.gz:     release_package/swarm-sandbox.tar.gz"
echo "  Dockerfile: release_package/Dockerfile"
```

> **关键点：`Dockerfile` 是代码仓库中已有的文件，build.sh 并不生成它，只是把它（1）打进 tar 包，（2）复制一份到 release_package 目录。**

---

## 四、Dockerfile（仓库内的容器镜像构建文件）

```dockerfile
# ── 基础镜像：华为内部 Python3.12.10 镜像 ──
FROM szvecr03.his.huawei.com:80/baseimage_horbor/python3.12.10:202602V1

# ── OCI 镜像标签 ──
LABEL org.opencontainers.image.title="SwarmSandbox"
LABEL org.opencontainers.image.version="1.0.0"

# ── Python 环境变量 ──
ENV PYTHONUNBUFFERED=1              # 标准输出不缓冲，日志实时打印
ENV PYTHONUTF8=1                    # 默认 UTF-8 编码，避免中文乱码
ENV HOME=/home/sandbox              # 容器内用户家目录
ENV JIUWENSWARM_DATA_DIR=/home/sandbox/.jiuwenswarm

# ── 创建非 root 用户 sandbox（UID=1000）──
RUN useradd --create-home --shell /bin/bash -u 1000 sandbox \
    && mkdir -p /tmp/sandbox \
    && chown -R sandbox:sandbox /home/sandbox /tmp/sandbox

# ── 配置 pip 华为内网镜像源 ──
RUN mkdir -p /etc/pip.conf.d \
    && echo "[global]" > /etc/pip.conf \
    && echo "index-url = http://mirrors.tools.huawei.com/pypi/simple" >> /etc/pip.conf \
    && echo "trusted-host = mirrors.tools.huawei.com" >> /etc/pip.conf

# ── 安装 Python 依赖 ──
COPY requirements.txt /tmp/requirements.txt

RUN pip3 install --no-cache-dir \
      --index-url http://mirrors.tools.huawei.com/pypi/simple \
      --trusted-host mirrors.tools.huawei.com \
      -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt \
    # 找到 jiuwenswarm 包安装路径，把权限交给 sandbox 用户
    && JIUWENSWARM_DIR=$(python3 -c "from pathlib import Path; import jiuwenswarm; print(Path(jiuwenswarm.__file__).parent)" 2>/dev/null) \
    && if [ -n "$JIUWENSWARM_DIR" ]; then chown -R sandbox:sandbox "$JIUWENSWARM_DIR"; fi

# ── 复制应用代码 ──
COPY app/ /home/sandbox/app/

# ── 复制启动脚本 ──
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ── 预创建 jiuwenswarm 运行目录结构（构建阶段无 NFS 挂载，提前建好避免运行时权限报错）──
RUN mkdir -p /home/sandbox/.jiuwenswarm/config \
    && mkdir -p /home/sandbox/.jiuwenswarm/agent/workspace/skills \
    && mkdir -p /home/sandbox/.jiuwenswarm/memory \
    && mkdir -p /home/sandbox/.jiuwenswarm/.agent_teams \
    && mkdir -p /home/sandbox/.jiuwenswarm/logs \
    # 读取 jiuwenswarm 内置的 .env 模板，复制为配置文件
    && TEMPLATE=$(python3 -c "from pathlib import Path; import jiuwenswarm; print(Path(jiuwenswarm.__file__).parent / 'resources' / '.env.template')" 2>/dev/null) \
    && if [ -n "$TEMPLATE" ] && [ -f "$TEMPLATE" ]; then cp "$TEMPLATE" /home/sandbox/.jiuwenswarm/config/.env; else touch /home/sandbox/.jiuwenswarm/config/.env; fi \
    && chown -R sandbox:sandbox /home/sandbox/.jiuwenswarm

# ── 服务默认环境变量 ──
ENV SANDBOX_HOST=0.0.0.0
ENV SANDBOX_PORT=8080
ENV SANDBOX_LLM_API_KEY=""
ENV SANDBOX_LLM_BASE_URL="http://aigateway.his-beta.huawei.com/v1"
ENV SANDBOX_LLM_MODEL="Qwen-V36-27B"

# ── 容器工作目录与端口 ──
WORKDIR /home/sandbox
EXPOSE 8080

# ── 切换为非 root 用户运行（安全加固）──
USER sandbox

# ── 健康检查：每 30s 访问 /health 接口 ──
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
  CMD curl -sf http://localhost:8080/health || exit 1

# ── 容器启动入口 ──
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

---

## 五、三个文件的关系与执行流程

### 5.1 调用关系图

```
┌─────────────────────────────────────────────────────────────┐
│                    cloudbuild.yaml                          │
│                  （CI 流水线总指挥）                          │
│  代码仓库中，纳入版本控制                                       │
└────────────┬────────────────────────────────────────────────┘
             │
             │ ① PRE_BUILD: checkout 拉取源码
             │ ② BUILD: sh swarm-sandbox/scripts/build.sh
             ▼
┌─────────────────────────────────────────────────────────────┐
│                swarm-sandbox/scripts/build.sh               │
│                   （打包脚本，仓库内）                         │
│  职责：生成 buildNumber → 写 buildInfo.properties           │
│        → tar 打包资源 → cp Dockerfile 到 release_package/   │
└──────┬──────────────────────────┬───────────────────────────┘
       │                          │
       │ ③ tar -czf               │ ④ cp Dockerfile
       │    Dockerfile             │
       │    entrypoint.sh          │
       │    requirements.txt       │
       │    app/                   │
       ▼                          ▼
┌──────────────────┐   ┌──────────────────────────┐
│ swarm-sandbox.   │   │ release_package/Dockerfile│
│ tar.gz           │   │ （仓库中 Dockerfile 的副本）│
│ （业务压缩包）    │   └──────────────────────────┘
└────────┬─────────┘
         │
         │ ⑤ POST_BUILD: signclient 签名
         ▼
┌──────────────────────────┐
│ swarm-sandbox.tar.gz.cms │
│ （数字签名文件）           │
└──────────┬───────────────┘
           │
           │ ⑥ artget push 上传云制品库
           ▼
    ┌─────────────────┐
    │   云制品库       │
    │  - tar.gz       │
    │  - tar.gz.cms   │
    │  - Dockerfile   │
    └─────────────────┘
```

### 5.2 完整执行时序

| 步骤 | 阶段 | 执行方 | 动作 |
|------|------|--------|------|
| 1 | PRE_BUILD | 流水线 | `checkout` 拉取源码，拿到 build.sh、Dockerfile、app/、requirements.txt 等 |
| 2 | BUILD | 流水线 | 执行 Python 源码与依赖检查 |
| 3 | BUILD | build.sh | 生成 buildNumber，写入 `buildInfo.properties` |
| 4 | BUILD | build.sh | `tar -czf` 将 Dockerfile、entrypoint.sh、requirements.txt、app/ 打包为 `swarm-sandbox.tar.gz` |
| 5 | BUILD | build.sh | `cp Dockerfile release_package/Dockerfile`，单独复制一份 Dockerfile 到输出目录 |
| 6 | POST_BUILD | 流水线 | `signclient` 对 tar.gz 和 Dockerfile 签名，生成 `.cms` 文件 |
| 7 | POST_BUILD | 流水线 | `artget push` 上传 tar.gz + cms + Dockerfile 到云制品库 |
| 8 | POST_BUILD | 流水线 | `version_set` 固化版本信息 |

### 5.3 关键区分点

1. **Dockerfile 在代码仓库中**：它是开发编写的固定文件，纳入版本控制。build.sh 不生成它，只是把它打进 tar 包并复制一份到 release_package/。
2. **yaml 不做实际打包**：yaml 只负责调度，打包逻辑全部在 build.sh 中。
3. **`.cms` 不是 build.sh 的产物**：它是流水线 POST_BUILD 阶段由 signclient 工具生成的签名文件。
4. **release_package/ 是构建输出目录**：build.sh 运行后在此目录产出 `swarm-sandbox.tar.gz` 和 `Dockerfile` 副本。
5. **Dockerfile 单独复制的原因**：流水线需要单独对 Dockerfile 签名并上传，而 tar 包里也包含一份 Dockerfile（用于镜像构建时使用）。

### 5.4 后续镜像构建

从云制品库拉取 `Dockerfile` + `swarm-sandbox.tar.gz` 后，用 Docker 构建命令即可生成最终的 swarm-sandbox 容器镜像：

```bash
docker build -t swarm-sandbox:1.0.0 .
```

---

## 六、代码仓库中的文件结构（构建前）

```
swarm-sandbox/
├── Dockerfile                  # 容器镜像构建文件（开发编写，版本控制）
├── entrypoint.sh               # 容器启动入口脚本
├── requirements.txt            # Python 依赖清单
├── buildInfo.properties        # （build.sh 运行时生成）版本信息
├── scripts/
│   └── build.sh                # 打包脚本
├── app/                        # 业务应用代码
└── release_package/            # （build.sh 运行时生成）构建输出目录
    ├── swarm-sandbox.tar.gz    # 业务压缩包
    └── Dockerfile              # 仓库中 Dockerfile 的副本
```
