# PMO资本化管理系统 GitHub Pages + Supabase 部署说明

## 交付内容

- `index.html`：第三版前端的 GitHub Pages 静态托管版本，已移除对本地同步服务和飞书多维表格的依赖。
- `assets/supabase-config.js`：Supabase 本地配置文件，填写项目 URL、anon key 和 Storage bucket。
- `supabase-schema.sql`：建表、登录角色、RLS 权限和文件存储策略。

## 部署步骤

### 1. 创建 Supabase 项目

在 Supabase 新建项目后，进入 SQL Editor，执行 `supabase-schema.sql` 的全部内容。

### 2. 创建登录用户

在 Supabase Authentication 中创建 PMO、财务用户。创建后复制用户 UUID，在 SQL Editor 执行：

```sql
insert into public.profiles(user_id, role, display_name, department)
values ('PMO用户UUID', 'pmo', '张瑶', 'PMO')
on conflict (user_id) do update set role=excluded.role, display_name=excluded.display_name, department=excluded.department;

insert into public.profiles(user_id, role, display_name, department)
values ('财务用户UUID', 'finance', '王珂', '财务')
on conflict (user_id) do update set role=excluded.role, display_name=excluded.display_name, department=excluded.department;
```

### 3. 填写前端配置

编辑 `assets/supabase-config.js`：

```js
window.PMO_SUPABASE_CONFIG = {
  url: 'https://你的项目.supabase.co',
  anonKey: '你的 anon public key',
  storageBucket: 'project-materials'
};
```

注意：这里可以放 anon key，不能放 service_role key。

### 4. 发布到 GitHub Pages

把本目录内文件提交到 GitHub 仓库，进入仓库 Settings → Pages，选择分支和根目录发布。

建议目录结构：

```text
/
  index.html
  supabase-schema.sql
  assets/
    supabase-config.js
```

## 权限说明

- PMO：可新增、编辑、删除项目、事件、材料、FTE，可上传附件。
- 财务：可登录查看项目、事件、材料、FTE，但数据库层禁止写入、删除。
- 未登录：前端会提示登录，不允许读取 Supabase 数据。

## 数据表说明

- `projects`：项目主数据。
- `events`：阶段节点事件，对应原“节点事件表”。
- `materials`：材料记录，对应原“材料表”。
- `fte_entries`：项目月度 FTE。
- `profiles`：账号角色表。
- `audit_logs`：预留审计日志表。

## 当前实现范围

已实现：

- 第三版前端静态化，适配 GitHub Pages。
- Supabase Auth 登录入口。
- PMO、财务角色从 `profiles` 表读取。
- 项目、事件、材料、FTE 的 Supabase 读写接口。
- 删除阶段、事件、材料时同步删除 Supabase 数据。
- 材料链接与文件上传逻辑对接 Supabase Storage。
- 数据层 RLS 权限控制。

后续建议：

- 补充导入脚本，把当前原型内置项目批量写入 Supabase。
- 若附件需要可预览或下载，增加 signed URL 获取逻辑。
- 若需要审计留痕，可把新增、修改、删除动作写入 `audit_logs`。
