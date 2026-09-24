OpenCode 离线沙箱 NAS持久化 + 流式CLI调用 完整落地技术文档（最终调试版）
OpenCode 离线沙箱 NAS持久化 + 流式CLI调用 完整落地技术文档（最终调试版）
一、整体问题复盘（本次全部踩坑总结）
1. 核心重大误区（最关键问题）
最初误以为：
opencode serve（4096端口）可以被脚本/CURL调用做业务对话。
真实结论：
- opencode serve = 纯WebUI前端调试界面
- 浏览器聊天走的是 WebSocket长连接
- 不支持 HTTP POST / JSON / API 调用
- CURL访问4096会 永久挂死、无返回、无报错、平台超时空输出
业务绝对不能使用 4096 端口做对话！
2. 第二大问题：环境变量进程隔离
- start.sh 里 export 的所有 XDG 路径
- 只属于 PID1 进程
- AIO 每次执行 command 都是 全新子进程
- 完全不继承任何环境变量
👉解决方案：业务调用脚本必须每次重新设置全套NAS路径 + XDG环境变量
3. 第三大问题：控制台看似流式，实际是缓冲区缓存
原生 CLI 输出是 行缓冲模式
导致回答全部积攒结束后一次性输出，无法前端流式渲染。
👉解决方案：
1. 使用 stdbuf 关闭系统IO缓冲
2. 增加 Python 流式包装，逐字输出标准JSON分片
4. 第四大问题：SessionID 归属混乱
- OpenCode 不会自己生成、保存、管理 SessionID
- SessionID 不归沙箱管、不归脚本管
- SessionID 归属上层业务系统
调试阶段：脚本自动生成 SessionID 方便测试
生产阶段：业务传入固定 SessionID 做多轮记忆

---
二、最终落地架构（当前正式可用架构）
架构总览
1. 沙箱启动：常驻空休眠，不启动WebUI、不启动任何端口服务
2. 数据全部持久化到 用户独立NAS目录 /home/data/${USER_ID}
3. 业务调用使用 opencode run（纯CLI模式）
4. 无端口、无HTTP、无WebSocket、无卡死问题
5. 输出标准 JSON分片流式返回
6. 沙箱销毁重建 不丢失任何会话历史
三套核心文件（各司其职、绝对不能乱改）
文件1：start.sh（【沙箱启动唯一执行一次】）
职责：沙箱初始化 + NAS挂载等待 + 全局路径重定向 + 缓存初始化 + 常驻保活
执行时机：
- 沙箱创建瞬间自动执行 仅一次
做的事情：
1. 读取 USER_ID
2. 拼接当前用户独立NAS路径 /home/data/${USER_ID}
3. 等待NAS挂载就绪（超时24秒保护）
4. 强制重定向 OpenCode 所有数据目录到NAS
  - 会话数据库
  - 运行状态
  - 缓存配置
5. 初始化 node_modules 缓存、fake package.json
6. 不启动 serve、不启动4096
7. 最后 sleep infinity 作为 PID1 保活沙箱常驻
一句话总结：start.sh 只管环境初始化，不管对话。

---
文件2：invoke_debug.sh（【业务每次对话都执行】）
职责：接收参数 + 重建NAS环境 + 执行对话 + 流式输出
执行时机：
- 用户每一次提问，AIO平台 command 调用一次
做的事情：
1. 接收三个参数：user_id / session_id / query
2. 重新拼装NAS路径、重新export全套XDG环境变量（解决进程隔离）
3. 调试专属：不传 session_id 则自动生成新会话
4. 调用 opencode run 真实对话逻辑
5. 关闭IO缓冲，保证实时吐字
6. 管道交给python脚本输出标准流式JSON
一句话总结：所有对话逻辑、参数传入、流式输出全部在这里。

---
文件3：stream_wrapper.py（【流式格式化中间层】）
职责：原生文本 → 标准前端可解析 JSON 流式分片
输出格式：
{"type":"content","text":"内"}
{"type":"content","text":"容"}
{"type":"end","reason":"complete"}
特点：
- 逐字输出
- 无缓冲
- 有结束标记
- 前端可直接 for 循环渲染

---
三、完整运行流程（100%可复现）
步骤1：创建沙箱，自动执行 start.sh
效果：
- NAS挂载成功
- 全部数据目录重定向NAS
- 沙箱常驻待命，无任何端口占用
步骤2：第一次对话（新建会话）
调用命令：
bash invoke_debug.sh "user01" "" "你的问题"
行为：
1. 检测 session_id 为空 → 自动生成新session
2. 在NAS创建全新会话数据库
3. 流式输出回答
4. 控制台打印本次 session_id（手动保存）
步骤3：第二次、第三次多轮对话（接续历史）
调用命令：
bash invoke_debug.sh "user01" "刚才的session_id" "继续提问"
行为：
1. 读取NAS中该session的全部历史上下文
2. 带入历史继续对话
3. 续写会话记录到NAS
4. 持续流式输出
步骤4：销毁沙箱、重建沙箱
- user_id 不变
- session_id 不变
- NAS数据还在
👉 历史对话 100% 不丢失

---
四、SessionID 完整机制（彻底讲透）
调试模式规则
1. 不传 session_id → 脚本自动生成全新会话
2. 自己传入 session_id → 接续历史会话
3. 所有会话永久保存在NAS
生产模式规则（后续上线使用）
1. SessionID 由业务后端生成、保存、管理
2. 前端新对话 → 后端生成 UUID/SessionID
3. 每次提问携带同一个 SessionID
4. 沙箱只负责根据 SessionID 读写NAS数据
核心铁律
- 沙箱不记忆会话
- 脚本不保存会话
- 只有NAS磁盘 + 业务侧SessionID 能记住会话

---
五、流式输出实现原理
两层缓冲问题彻底解决
1. 系统层缓冲：使用 stdbuf -i0 -o0 -e0 彻底关闭
2. 应用层缓冲：Python 逐字 read + 强制 flush
最终输出效果
- 回答一个字一个字往外吐
- 前端可实时渲染打字机效果
- 末尾带结束标记，可关闭加载状态

---
六、目录持久化最终落地结构
每个用户完全隔离：
/home/data/${USER_ID}/
 ├─ 会话数据库（记忆多轮对话）
 ├─ 运行状态
 └─ 模型运行缓存
容器本地目录 不再存任何业务数据
所有数据 100% NAS 持久化

---
七、文件用途最简速查（给团队看）
文件
执行时机
核心作用
[start.sh](start.sh)
沙箱启动一次
初始化NAS、重定向路径、常驻保活
[invoke_debug.sh](invoke_debug.sh)
每次用户提问
执行业务对话、传参、多轮会话、流式输出
[stream_wrapper.py](stream_wrapper.py)
对话调用时加载
把原生输出转为标准前端流式JSON

---
八、当前可直接使用的调试命令
1. 启动沙箱环境
export USER_ID=user01
bash start.sh
2. 新建对话（自动生成session）
bash invoke_debug.sh "user01" "" "帮我介绍二分查找"
3. 接续对话（手动带入session）
bash invoke_debug.sh "user01" "xxx_session_id" "继续详细说"

---
九、当前架构优势（汇报可用）
1. 彻底规避 serve UI 卡死BUG
2. 无端口、无HTTP、无websocket兼容问题
3. 完美适配沙箱900秒销毁机制
4. 全程NAS持久化，跨沙箱不丢会话
5. 原生支持流式输出，前端体验达标
6. 进程模型极简：调用即跑、跑完即退、无僵尸进程
7. 多用户数据完全隔离

---
十、后续上线改造点（仅生产需要）
1. 删除脚本自动生成 session_id 逻辑
2. 强制业务必须传入 session_id
3. 关闭调试日志冗余输出
4. 保留现有流式、NAS、CLI架构不变

---
文档结尾总结（一句话整体架构）
本次最终落地方案：
放弃WebUI的4096端口API幻想，采用CLI原生对话模式 + 每次重建NAS环境变量 + 磁盘持久化会话 + Python标准流式包装，实现了稳定、不卡死、可多轮记忆、可前端流式渲染的OpenCode离线沙箱业务能力。ni
