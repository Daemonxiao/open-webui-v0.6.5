# Prompt 应用设计文档

## 1. 设计目标

基于 [Prompt 应用权限与使用 PRD](./prompt-apps-prd.md)，新增一套“可管理、可使用、指令脱敏”的 Prompt 应用能力。

核心目标：

- 下线旧 Workspace Prompt 功能，不保留旧用户侧兼容。
- 管理员可以查看并管理所有人的 Prompt 应用。
- 本期仅管理员可以创建 Prompt 应用。
- 普通用户可以在聊天时选择 Prompt 应用并使用。
- 普通用户不能查看、复制、导出或通过接口获取 Prompt 指令。
- 后续可扩展为普通用户创建和管理自己的 Prompt 应用，管理员仍可管理全部。
- 同一个聊天中，每次发送前都可以选择不同的 Prompt 应用。

## 2. 当前实现基线

当前仓库已经有 Prompt 相关能力：

- 后端路由：`backend/open_webui/routers/prompts.py`
- 数据模型：`backend/open_webui/models/prompts.py`
- 前端 API：`src/lib/apis/prompts/index.ts`
- 管理页列表：`src/lib/components/workspace/Prompts.svelte`
- 管理页编辑器：`src/lib/components/workspace/Prompts/PromptEditor.svelte`
- 聊天输入 Prompt 命令菜单：`src/lib/components/chat/MessageInput/Commands/Prompts.svelte`

现有 Prompt 字段包括：

- `id`
- `command`
- `user_id`
- `name`
- `content`
- `data`
- `meta`
- `tags`
- `is_active`
- `version_id`
- `created_at`
- `updated_at`
- `access_grants`

主要问题：

- `content` 当前是完整指令，并且多个列表/详情接口会直接返回。
- 现有 `read` 权限会让用户读到完整 Prompt，不适合表达“可使用但不可看指令”。
- 聊天输入 Prompt 菜单调用 `GET /api/v1/prompts/`，当前会拿到完整 `content`，该旧入口需要下线。
- 聊天 `/` Prompt 命令选择当前会把 `prompt.content` 插入输入框，该旧行为需要删除。
- 管理接口中的权限判断分散，容易出现某个接口忘记脱敏或忘记校验。
- 当前 `BYPASS_ADMIN_ACCESS_CONTROL` 会影响 admin 列表和 `write_access`，与“管理员全量管理”的产品要求不一致。
- 前端列表页会展示并复制 `prompt.content`。

## 3. 设计原则

### 3.1 管理和使用分离

Prompt 应用分成两个能力面：

- 管理面：创建、查看指令、编辑、删除、启停、版本、访问范围。
- 使用面：选择应用、提交用户输入、由后端注入隐藏指令。

普通用户的“使用”不能等价于“读取 Prompt”。用户使用 Prompt 应用时，只能拿到摘要信息，不能拿到 `content`。

### 3.2 后端强制脱敏

指令保护必须由后端响应模型保证，不能只靠前端隐藏按钮。

所有面向普通用户或非管理者的接口不得返回：

- `content`
- `access_grants`
- `version_id`
- history snapshot
- diff
- 导出内容

### 3.3 每条消息独立选择

Prompt 应用不是会话级固定配置，而是消息级可选上下文。

同一聊天中允许：

```text
第 1 条消息：不使用 Prompt 应用
第 2 条消息：使用“合同风险检查”
第 3 条消息：使用“邮件润色”
第 4 条消息：取消选择，恢复普通聊天
```

前端可以在发送后保留当前选择，也可以自动清空。建议本期默认保留，用户可手动取消；后续可增加用户偏好。

## 4. 权限模型

### 4.1 本期权限

```text
can_create_prompt_app(user):
  return user.role == "admin"

can_manage_prompt_app(user, prompt):
  return user.role == "admin"

can_use_prompt_app(user, prompt):
  return user is verified and prompt.is_active == true
```

含义：

- 管理员可以创建 Prompt 应用。
- 管理员可以查看并管理所有 Prompt 应用。
- 普通用户不能创建、编辑、删除或查看指令。
- 普通用户可以使用已启用的 Prompt 应用。

### 4.2 后续扩展权限

后续放开普通用户创建时：

```text
can_create_prompt_app(user):
  return user is verified

can_manage_prompt_app(user, prompt):
  return user.role == "admin" or prompt.user_id == user.id

can_use_prompt_app(user, prompt):
  return user is verified and prompt.is_active == true
```

普通用户只能管理自己的 Prompt 应用；管理员仍然可以管理所有人的 Prompt 应用。

### 4.3 实现要求

后端新增统一 helper，所有管理接口都必须调用：

```python
def can_manage_prompt_app(user, prompt) -> bool:
    return user.role == "admin"
```

后续扩展时只改 helper：

```python
def can_manage_prompt_app(user, prompt) -> bool:
    return user.role == "admin" or prompt.user_id == user.id
```

不要在每个 route 里散落编写权限条件。

Prompt 应用管理权限不能继续依赖：

- `BYPASS_ADMIN_ACCESS_CONTROL`
- `AccessGrants.has_access(..., permission='write')`
- 前端传回的 `write_access`

原因：

- PRD 要求管理员非 owner 可以看到所有人的 Prompt 并做任何管理操作；因此 admin 管理列表、详情、编辑、删除、启停、history 不应受 `BYPASS_ADMIN_ACCESS_CONTROL` 影响。
- 后续普通用户只能管理自己创建的 Prompt；因此旧的 prompt `write` grant 不能继续作为 Prompt 应用管理权限。
- `access_grants` 后续只能用于“谁可以使用”或更细粒度的使用范围，不用于授予指令查看和编辑权限。

## 5. 数据模型

### 5.1 字段方案

建议新增显式 `description` 字段：

```python
description = Column(Text, nullable=True)
```

对应响应字段：

```python
class PromptModel(BaseModel):
    description: Optional[str] = None
```

原因：

- 描述是用户侧列表的核心展示字段，不应长期放在松散 `meta`。
- 后续需要搜索、排序、导入导出、校验时，显式字段更稳定。

### 5.2 数据初始化

当前没有需要保留的历史 Prompt 数据，因此不做历史数据迁移和回填。

实现要求：

- 新增 `description` 字段。
- 新建 Prompt 应用时必须写入 `description`。
- 不需要从 `meta.description` 回填。
- 不需要为旧 Prompt 设置默认开放策略。

### 5.3 是否需要新增表

本期不建议新增 `prompt_app` 表。

理由：

- 当前 `prompt` 表已经覆盖名称、指令、owner、启停、版本、访问控制等基础字段。
- 新增表会带来迁移、历史版本、现有管理页和聊天入口的重复改造。
- 本需求本质是现有 Prompt 的权限和使用方式调整。

旧 Workspace Prompt 功能下线后，Prompt 表作为 Prompt 应用表继续使用；不再维护两套产品语义。

## 6. 后端 API 设计

### 6.1 响应模型拆分

新增两个响应模型：

```python
class PromptAppSummaryResponse(BaseModel):
    id: str
    name: str
    description: Optional[str] = ""
    user_id: str
    user: Optional[UserResponse] = None
    is_active: bool = True
    created_at: Optional[int] = None
    updated_at: Optional[int] = None


class PromptAppAdminResponse(PromptModel):
    user: Optional[UserResponse] = None
    write_access: bool = True
```

约束：

- `PromptAppSummaryResponse` 绝不包含 `content`。
- 管理接口可以返回 `PromptAppAdminResponse`。
- 使用入口必须使用 summary response。

### 6.2 管理接口

本期可以复用现有 `/api/v1/prompts` 路径承载 Prompt 应用管理，但不保留旧 Workspace Prompt 语义。

建议接口：

```text
GET    /api/v1/prompts/admin/list
POST   /api/v1/prompts/create
GET    /api/v1/prompts/id/{prompt_id}
POST   /api/v1/prompts/id/{prompt_id}/update
POST   /api/v1/prompts/id/{prompt_id}/toggle
DELETE /api/v1/prompts/id/{prompt_id}/delete
GET    /api/v1/prompts/id/{prompt_id}/history
GET    /api/v1/prompts/id/{prompt_id}/history/{history_id}
GET    /api/v1/prompts/id/{prompt_id}/history/diff
DELETE /api/v1/prompts/id/{prompt_id}/history/{history_id}
```

管理接口要求：

- 创建：本期仅 admin。
- 列表：admin 返回所有 Prompt 应用。
- 详情：admin 返回完整指令。
- 更新、删除、启停、history：必须 `can_manage_prompt_app(user, prompt)`。
- 普通用户访问管理接口返回 401/403。
- 管理接口的 admin 全量能力不受 `BYPASS_ADMIN_ACCESS_CONTROL` 控制。
- 响应里的 `write_access` 对 admin 永远为 `true`。
- 普通用户即使拥有旧 `read/write access_grants`，也不能访问完整详情、history、diff、导出或管理操作。

### 6.3 旧 Prompt 接口下线

旧 Workspace Prompt 用户侧接口不需要兼容。必须删除或改为 admin-only，避免普通用户继续通过旧 API 获取指令。

需要下线用户侧访问的旧接口：

```text
GET /api/v1/prompts/
GET /api/v1/prompts/list
GET /api/v1/prompts/command/{command}
```

设计要求：

- 管理页改用 Prompt 应用 admin/full-detail 接口。
- 用户侧选择入口只调用 `/prompts/apps`。
- 普通用户调用旧读取接口必须返回 401/403。
- 不提供旧接口 summary 兼容。
- 不保留旧 `/prompts/command/{command}` 取指令功能。

推荐处理：

| 接口 | 管理员 | 普通用户 |
| --- | --- | --- |
| `GET /prompts/` | 删除或改为 admin-only | 403 |
| `GET /prompts/list` | admin 返回 Prompt 应用管理列表 | 403 |
| `GET /prompts/command/{command}` | 删除；如保留仅 admin 调试使用 | 403 |

### 6.4 用户使用接口

新增用户侧脱敏列表：

```text
GET /api/v1/prompts/apps
```

返回当前用户可使用的已启用 Prompt 应用：

```json
{
  "items": [
    {
      "id": "prompt-id",
      "name": "合同风险检查",
      "description": "检查合同付款、违约、终止和责任条款风险。",
      "user_id": "admin-user-id",
      "user": {
        "id": "admin-user-id",
        "name": "Admin",
        "email": "admin@example.com"
      },
      "is_active": true,
      "updated_at": 1710000000
    }
  ]
}
```

不得返回 `content`。

### 6.5 是否新增 run API

有两种实现方式。

#### 方案 A：新增 run API

```text
POST /api/v1/prompts/apps/{prompt_id}/run
```

请求：

```json
{
  "chat_id": "optional-chat-id",
  "input": "用户输入内容",
  "model": "model-id"
}
```

后端读取 Prompt 指令，组合用户输入，然后调用现有聊天生成流程。

优点：

- 指令只在后端拼接，泄露风险低。
- 权限语义清晰。

缺点：

- 需要更深地接入现有聊天生成链路。
- 流式响应、文件、模型参数、工具调用等能力需要复用现有聊天 API，改造面较大。

#### 方案 B：扩展现有聊天提交 API

前端发送聊天时附带 Prompt 应用 ID。当前 Open WebUI 聊天链路不是简单的 `{ chat_id, prompt }`，实际会提交 `messages`、`user_message`、`parent_id`、`chat_id`、`files`、`tool_ids` 等字段，因此 `prompt_app_id` 必须作为顶层业务字段进入后端，并在转发模型 provider 前移除。

示意：

```json
{
  "chat_id": "chat-id",
  "messages": [],
  "user_message": {
    "content": "用户输入内容",
    "metadata": {}
  },
  "prompt_app_id": "prompt-id"
}
```

后端在现有聊天 pipeline 中：

1. 校验 `prompt_app_id`。
2. 校验 `can_use_prompt_app`。
3. 读取 `content`。
4. 将 `prompt_app_id` 从 provider 请求体中 pop/remove，避免透传给 OpenAI/Ollama/兼容 API。
5. 在进入模型请求前注入指令。
6. 保存消息 metadata：`prompt_app_id`、`prompt_app_name`。
7. 不把 `content` 写入普通用户可见 metadata。

优点：

- 最大程度复用现有聊天、流式、文件、工具、模型参数逻辑。
- 用户体验和普通聊天完全一致。

缺点：

- 需要谨慎选择注入点，避免把隐藏指令写进用户可见消息正文。

本期建议采用方案 B。

落点要求：

- 在 `backend/open_webui/main.py` 的聊天 completion 入口解析 `prompt_app_id`。
- 在调用模型适配层前完成校验、读取和注入。
- 在转发 provider 前确保 payload 不包含 `prompt_app_id`、`prompt_app_content` 或任何隐藏指令字段。
- 注入后用于模型请求的隐藏消息不应持久化为用户消息正文。

## 7. 指令注入设计

### 7.1 注入位置

Prompt 应用指令应在后端进入模型请求前注入，不应由前端拼接。

建议注入形式：

```text
system/developer message: prompt.content
user message: 用户输入
```

如果现有模型请求不方便新增 system message，也可以在后端构造临时 prompt：

```text
{hidden_prompt_instruction}

用户输入：
{user_input}
```

但这个组合内容不能作为用户消息正文保存到聊天记录。

注入必须具备幂等保护：

- regenerate 时不能重复叠加同一个 Prompt 应用指令。
- continue response 时不能把历史 metadata 再次误注入。
- queued message、多模型 fanout、temporary chat 都应只在当前待发送请求中注入一次。

### 7.2 聊天记录保存

用户消息保存：

```json
{
  "role": "user",
  "content": "用户输入内容",
  "metadata": {
    "prompt_app_id": "prompt-id",
    "prompt_app_name": "合同风险检查",
    "prompt_app_version_id": "version-id"
  }
}
```

禁止保存：

```json
{
  "prompt_app_content": "隐藏指令"
}
```

Assistant 回复正常保存。

历史消息中只保存 Prompt 应用引用信息，不保存隐藏指令。`prompt_app_version_id` 用于追溯当时使用的是哪个版本；如果没有启用版本历史，也至少保存 `prompt_app_id` 和当时的 `prompt_app_name`。

### 7.3 审计信息

可以记录后端审计日志：

- 使用人 user_id。
- prompt_app_id。
- prompt_app_owner_id。
- chat_id。
- message_id。
- created_at。

审计日志不向普通用户展示指令。

## 8. 前端设计

### 8.1 用户侧入口

入口放在聊天输入框 `+` 菜单中，和“上传文件、引用网页、引用知识库、引用其他对话”保持一致。

新增菜单项：

```text
使用 Prompt 应用 >
```

点击后展示二级菜单或弹层：

```text
合同风险检查
检查合同付款、违约、终止条款风险

邮件润色
优化语气、结构和表达

会议纪要总结
提炼议题、结论和待办
```

用户选择后，在输入框附近显示状态标签：

```text
Prompt 应用：合同风险检查  ×
```

用户点击 `×` 取消选择。

### 8.2 旧 `/` Prompt 命令入口

当前 `/` Prompt 命令入口不能继续把 `prompt.content` 插入输入框，旧功能不做兼容。

处理方式：

- 删除旧 `/` Prompt 命令项，所有用户使用 `+` 菜单选择 Prompt 应用。
- 如产品希望保留快捷键体验，后续可以新增一个“选择 Prompt 应用”的快捷入口，但不能复用旧插入文本语义。

行为：

- 不调用旧 `getPrompts()` 获取完整 Prompt。
- 不调用 `insertTextHandler(data.content)`。
- 不在输入框中插入隐藏指令。
- 管理员如需查看或编辑指令，应进入 Prompt 应用管理页，而不是聊天输入框。

### 8.3 发送行为

用户发送时：

- 如果未选择 Prompt 应用，按普通聊天发送。
- 如果选择 Prompt 应用，请求里带上 `prompt_app_id`。
- 发送后默认保留选中状态。
- 用户可在下一次发送前切换为其他 Prompt 应用。

同一聊天中不同消息可以使用不同 Prompt 应用。

### 8.4 用户可见消息

消息流中可选展示一行轻量标记：

```text
使用 Prompt 应用：合同风险检查
```

展示内容只用 `prompt_app_name`，不展示指令。

### 8.5 管理员查看用户历史消息

管理员查看用户历史聊天时，需要能看到该用户消息当时使用了哪个 Prompt 应用。

展示建议：

```text
用户消息：
请检查下面这段合同条款：...

使用的 Prompt 应用：
合同风险检查
```

可展示字段：

- `prompt_app_id`
- `prompt_app_name`
- `prompt_app_version_id`
- Prompt 应用创建者
- 使用时间

不可直接展示在聊天正文中：

- Prompt 指令原文。
- 后端实际拼接后的完整模型请求。
- system/developer message。

管理员如需查看指令，应从 Prompt 应用管理页打开对应应用或版本。这样历史聊天保持用户实际输入的可读性，同时管理员仍可审计“这条消息用了哪个 Prompt 应用”。

### 8.6 管理员管理页

管理员使用新的 Prompt 应用管理页。可以复用现有 Workspace Prompt 页面代码实现，但产品入口和语义要替换为 Prompt 应用：

- 管理员列表显示所有 Prompt 应用。
- 列表增加描述字段。
- 列表可以显示创建者。
- 管理员可以进入任意 Prompt 应用详情。
- 管理员可以查看和编辑完整指令。
- 管理员可以删除、启停任意 Prompt 应用。

后续普通用户创建开放后：

- 普通用户的管理页只显示自己创建的 Prompt 应用。
- 管理员管理页仍显示所有 Prompt 应用。

## 9. 前端 API 调整

新增 API：

```typescript
export const getPromptApps = async (token: string) => {
  return fetch(`${WEBUI_API_BASE_URL}/prompts/apps`, ...);
};
```

聊天发送 API 需要支持可选字段：

```typescript
type ChatSubmitPayload = {
  messages: unknown[];
  user_message?: {
    content: string;
    metadata?: Record<string, unknown>;
  };
  prompt_app_id?: string | null;
};
```

管理 API 类型新增：

```typescript
type PromptItem = {
  id?: string;
  command: string;
  name: string;
  description?: string | null;
  content: string;
  ...
};

type PromptAppSummary = {
  id: string;
  name: string;
  description?: string | null;
  user_id: string;
  user?: {
    id: string;
    name: string;
    email: string;
  };
  is_active: boolean;
  updated_at?: number;
};
```

## 10. 初始化与下线

### 10.1 数据初始化

当前没有 Prompt 数据需要迁移。只需要保证新部署或升级后的 schema 支持 Prompt 应用字段。

Schema 变更：

```text
add prompt.description nullable text
```

需要同步更新：

- SQLAlchemy `Prompt` model。
- Pydantic `PromptModel`。
- `PromptForm`。
- `insert_new_prompt`。
- `update_prompt_by_id`。
- `update_prompt_metadata`，如果描述允许不创建历史版本。
- Prompt history snapshot。
- history restore。
- import/export JSON。
- search query，如果描述需要可搜索。
- 前端 `PromptItem` 类型。
- `PromptEditor.svelte` 表单。

### 10.2 旧功能下线

不保留旧 Workspace Prompt 用户侧兼容：

- 管理页调用 admin/full-detail 接口。
- 聊天用户选择调用 `/prompts/apps` 脱敏接口。
- 删除旧用户侧 `/` Prompt 命令菜单。
- 旧 `/prompts/`、`/prompts/list`、`/prompts/command/{command}` 对普通用户返回 403。
- 旧复制 Prompt、导出 Prompt、Discover prompt 等 Workspace Prompt 用户侧入口下线。

## 11. 安全边界

必须验证以下泄露路径：

- 普通用户调用 `/prompts/apps` 不返回 `content`。
- 普通用户调用旧 `/prompts/` 被拒绝。
- 普通用户调用旧 `/prompts/list` 被拒绝。
- 普通用户调用旧 `/prompts/command/{command}` 被拒绝。
- 普通用户调用 `/prompts/id/{id}` 被拒绝。
- 普通用户调用 `/prompts/id/{id}/history` 被拒绝。
- 普通用户调用 diff 被拒绝。
- 普通用户不能导出 Prompt。
- 普通用户拥有旧 `read/write access_grants` 时仍不能查看指令或管理他人 Prompt 应用。
- 旧 `/` Prompt 命令菜单被移除，不能插入隐藏指令。
- 普通用户不能通过浏览器网络响应看到指令。
- 聊天记录 metadata 不包含指令。
- 前端不把隐藏指令拼到输入框或消息正文。
- 停用 Prompt 不能被普通用户使用。
- Provider 请求体不包含 `prompt_app_id`、`prompt_app_content` 或隐藏指令元数据字段。

## 12. 测试计划

### 12.1 后端测试

管理员：

- 创建 Prompt 应用成功。
- 管理列表返回所有 Prompt 应用。
- 可以查看任意 Prompt 的 `content`。
- 可以编辑、删除、启停任意 Prompt。
- 可以查看任意 Prompt history 和 diff。
- `BYPASS_ADMIN_ACCESS_CONTROL=false` 时，仍可以列表、详情、编辑、删除任意 Prompt 应用。

普通用户：

- `/prompts/apps` 只返回已启用 Prompt 摘要。
- `/prompts/apps` 不返回 `content`。
- 旧 `/prompts/`、`/prompts/list`、`/prompts/command/{command}` 被拒绝。
- 不能调用完整详情。
- 不能更新、删除、启停。
- 不能访问 history 和 diff。
- 即使拥有旧 `read/write access_grants`，也不能查看指令或管理他人 Prompt 应用。
- 聊天发送 `prompt_app_id` 可以正常得到回复。
- 聊天保存内容不包含隐藏指令。
- 聊天用户消息 metadata 保存 `prompt_app_id`、`prompt_app_name`、`prompt_app_version_id`。
- Provider 请求体不包含 `prompt_app_id` 或隐藏指令元数据。
- regenerate、continue response、temporary chat、多模型 fanout 不重复注入且不泄露。

停用：

- 管理员可看到停用 Prompt。
- 普通用户不可在使用列表看到停用 Prompt。
- 普通用户携带停用 Prompt ID 发送时失败。

### 12.2 前端测试

- `+` 菜单展示“使用 Prompt 应用”。
- 用户可以打开 Prompt 应用列表。
- 列表只展示名称和描述。
- 选择后输入框显示选中状态。
- 可以取消选择。
- 每次发送前可以切换 Prompt 应用。
- 旧 `/` Prompt 命令入口已移除。
- 管理员查看用户历史消息时能看到该消息使用的 Prompt 应用名称和版本 ID。
- 管理员管理页显示所有 Prompt 应用。
- 普通用户看不到复制、导出、编辑、删除、历史入口。

## 13. 分阶段实现

### Phase 1：后端安全边界

- 新增 `description` 字段并更新模型/表单。
- 新增脱敏 summary response。
- 新增 `/prompts/apps`。
- 新增统一 `can_manage_prompt_app`。
- 管理接口统一接入权限 helper。
- 旧用户侧读取接口删除或改为 admin-only。
- 聊天请求支持 `prompt_app_id` 并后端注入指令。
- Provider payload 移除 `prompt_app_id` 和隐藏指令元数据。
- 确保普通用户拿不到 `content`。

### Phase 2：前端使用入口

- 在聊天输入 `+` 菜单加入“使用 Prompt 应用”。
- 接入 `/prompts/apps`。
- 实现选中状态和取消。
- 聊天发送携带 `prompt_app_id`。
- 消息 metadata 展示应用名称。
- 删除旧 `/` Prompt 命令入口，禁止插入 `content`。

### Phase 3：管理员管理页调整

- 列表增加描述和创建者。
- 管理员列表返回所有 Prompt 应用。
- 编辑页支持描述字段。
- 删除、启停、history 接入统一权限。

### Phase 4：后续普通用户创建

- 放开 `can_create_prompt_app`。
- 普通用户管理列表只返回自己创建的 Prompt。
- 管理权限 helper 改为 `admin or owner`。
- 补充普通用户 owner 测试。

## 14. 开放问题

- 发送后是否默认保留已选 Prompt 应用，还是自动清空？本设计建议默认保留。
- Prompt 应用注入应使用 system message 还是 developer message，需要看现有模型适配层支持情况。
- 是否需要按用户组限制可使用的 Prompt 应用？本期建议所有 verified 用户可使用已启用应用。
