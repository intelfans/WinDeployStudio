# AI 模型迁移 —— mimo-v2.5-pro → mimo-v2.6-pro

**触发:** 供应商 2026-10-21 下线 `mimo-v2.5-pro`(系统替换时间 2026-10-14 18:00 UTC+8)。
替换后 `mimo-v2.5-pro` 的请求会被自动路由到 `mimo-v2.6-pro`,超过下线时间直接报错。

本仓库在三处做了改动,任何一处单独生效都能救活旧客户端;三处叠加是为了让
“已安装的旧版本”和“新构建”都不断线。

---

## 1. Cloudflare Worker(`worker/worker.js`)

网关侧兜底:**老客户端还在发 `mimo-v2.5-pro` 也能拿到回答**。

| 行为 | 实现 |
|---|---|
| 模型改名 | `MODEL_ALIASES`:`mimo-v2.5-pro→mimo-v2.6-pro`、`mimo-v2.5→mimo-v2.6-flash`、`mimo-v2-pro/omni/flash` 一并映射 |
| 未知模型 | 原样透传(自定义供应商不受影响) |
| 缺省模型 | 请求没带 `model` 时补 `mimo-v2.6-pro` |
| 思考模式采样参数 | v2.6 思考模式固定 `temperature=1.0 / top_p=0.95`、不接受自定义 → **剥离** `temperature`/`top_p`,否则上游可能 400 |
| `max_completion_tokens` | **不注入**。v2.6 默认 131072,注入会把所有调用方钉死在上限 |
| 可观测性 | 响应头 `X-WDS-Model` 给出实际模型,`X-WDS-Model-Migrated` 给出被替换的原值 |
| 流式 | `upstream.body` 直接 pipe,不缓冲;SSE 增量不会被攒住 |
| 超时 | 120s AbortController;超时 → 504,网络失败 → 502 |
| `GET /v1/models` | 新增透传(客户端“加载模型列表”要用) |

### 部署

```bash
cd worker
npx wrangler secret put MIMO_API_KEY     # 上游 token
npx wrangler deploy
```

可选覆盖:`MIMO_BASE_URL`(上游地址)、`MIMO_MODEL`(缺省模型)。

### 自测

```bash
node --test worker/          # 10 个用例,全部通过
```

覆盖:改名、采样参数剥离、自定义模型透传、缺省模型、SSE 不缓冲、
非对象 body 拒绝、`/v1/models` 透传、缺凭据不调用上游、上游网络失败映射、CORS 预检。

> 注意:老 worker 的 `supportedPaths` 只有 `/chat/completions` 和 `/responses`,
> 客户端 Settings 里“加载模型列表”(`GET /v1/models`)会直接 404。新版已补。

---

## 2. 客户端默认值(`lib/core/config/ai_config.dart`)

```dart
static const defaultModel = 'mimo-v2.6-pro';
```

外加一张退役表 + `migrateRetiredModelId()`,**读取路径**就会把旧值改写并落盘:

```dart
final migrated = migrateRetiredModelId(saved);
if (migrated != saved && isValidModelId(migrated)) {
  await setModel(migrated, endpointUrl: endpoint);
  return migrated;
}
```

老用户升级后,即使 SharedPreferences 里存的是 `mimo-v2.5-pro`,
第一次读就已经是 `mimo-v2.6-pro`,不需要手动去设置页改。

对应测试:`test/ai_model_migration_test.dart`(4 例)。

---

## 3. 换掉网关地址时改哪里

| 位置 | 改什么 |
|---|---|
| `lib/core/config/ai_config.dart:10` | `defaultEndpointUrl` |
| `ai_config.dart` 的 `_retiredBuiltInEndpointUrls` | 把**旧**地址加进去(触发自动迁移 + 清掉绑定的 key) |
| `worker/wrangler.toml` 的 `[vars]` | `MIMO_MODEL` 缺省模型 |
| worker secret | `MIMO_API_KEY` |

旧地址迁移逻辑已经就位:命中 `_retiredBuiltInEndpointUrls` 会清空
`ai_api_key_protected` / `ai_model` 以及它们的 endpoint 绑定,避免把用户的
key 关联到已经不用的供应商。

---

## 4. 上游以后换参数约束时

只有一处要动:`worker/worker.js` 的

```js
const FIXED_SAMPLING_MODELS = new Set(["mimo-v2.6-pro", "mimo-v2.6-flash"]);
```

把新模型加进去,采样参数会在转发前被剥离;要恢复可调就把模型从集合里移除。
