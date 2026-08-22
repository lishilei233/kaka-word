# Picture Word Server

```bash
npm install
cp .env.example .env
npm run dev
```

## 目录结构

```text
src/
├── index.ts                   # 进程入口，只负责启动服务
├── app.ts                     # Hono 应用装配
├── config.ts                  # 环境变量与运行配置
├── routes/                    # HTTP 业务路由
├── core/image-analysis/       # 图片分析核心能力与供应商适配器
└── utils/                     # 日志、图片尺寸解析等通用能力
```

新增视觉模型时，在 `src/core/image-analysis/providers/` 添加适配器，并在 `index.ts` 注册；HTTP 层不需要感知供应商协议。

## 日志

服务端默认输出 JSON 结构化日志，可通过 `.env` 设置日志级别：

```env
LOG_LEVEL=info
```

可选值为 `debug`、`info`、`warn`、`error`。每个请求都会带有 `requestId`，并记录 HTTP 状态、总耗时、图片字节数与尺寸、视觉模型耗时和返回对象数量。日志不会记录图片内容、base64、Authorization 请求头或 API Key。客户端也可以传入 `X-Request-ID`，方便串联客户端和服务端问题。

The default `VISION_PROVIDER=qwen` uses Alibaba Cloud Model Studio through its Beijing OpenAI-compatible endpoint. Configure `QWEN_API_HOST`, `QWEN_API_KEY`, and optionally `QWEN_MODEL` in `.env`.

Set `VISION_PROVIDER=mock` to return deterministic objects for mobile UI development without using model credits. Gemini and Volcengine adapters remain available as optional alternatives.

The server keeps uploaded images in memory only. It does not write image files or store analysis results.
