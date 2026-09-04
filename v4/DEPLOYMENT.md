# PMO资本化管理系统第四版 GitHub Pages + Supabase 部署说明

## 交付内容

- `index.html`：第四版前端的 GitHub Pages 静态托管版本，已移除对本地同步服务和飞书多维表格的依赖。
- `assets/supabase-config.js`：Supabase 本地配置文件，填写项目 URL、anon key 和 Storage bucket，以及第四版独立表配置。
- `supabase-schema.sql`：建表、登录角色、RLS 权限和文件存储策略。

## 部署步骤

### 1. 创建 Supabase 项目

在 Supabase 新建项目后，进入 SQL Editor，执行第四版目录内 `supabase-schema.sql` 的全部内容。该脚本会创建 `v4_*` 独立数据表和 `project-materials-v4` 独立文件桶，并尝试从第三版原表复制一份初始数据。

### 2. 创建登录用户

在 Supabase Authentication 中创建 PMO、财务用户。创建后复制用户 UUID，在 SQL Editor 执行：

```sql
insert into public.v4_profiles(user_id, role, display_name, department)
values ('PMO用户UUID', 'pmo', '张瑶', 'PMO')
on conflict (user_id) do update set role=excluded.role, display_name=excluded.display_name, department=excluded.department;

insert into public.v4_profiles(user_id, role, display_name, department)
values ('财务用户UUID', 'finance', '王珂', '财务')
on conflict (user_id) do update set role=excluded.role, display_name=excluded.display_name, department=excluded.department;
```

### 3. 填写前端配置

编辑 `assets/supabase-config.js`：

```js
window.PMO_SUPABASE_CONFIG = {
  url: 'https://你的项目.supabase.co',
  anonKey: '你的 anon public key',
  storageBucket: 'project-materials-v4',
  tables: {
    profiles: 'v4_profiles',
    projects: 'v4_projects',
    events: 'v4_events',
    materials: 'v4_materials',
    fte_entries: 'v4_fte_entries'
  }
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

- `v4_projects`：第四版项目主数据。
- `v4_events`：第四版阶段节点事件。
- `v4_materials`：第四版材料记录。
- `v4_fte_entries`：第四版项目月度 FTE。
- `v4_profiles`：第四版账号角色表。
- `v4_audit_logs`：第四版预留审计日志表。

## 当前实现范围

已实现：

- 第四版前端静态化，适配 GitHub Pages。
- Supabase Auth 登录入口。
- PMO、财务角色从 `v4_profiles` 表读取。
- 项目、事件、材料、FTE 的 Supabase 读写接口。
- 删除阶段、事件、材料时同步删除 Supabase 数据。
- 材料链接与文件上传逻辑对接 Supabase Storage。
- 数据层 RLS 权限控制。

后续建议：

- 若需要重新初始化第四版数据，可重新执行 `supabase-schema.sql` 末尾的初始化复制段；脚本会按项目 A/B/C/D/E 做脱敏映射。
- 若需要完全物理隔离，可新建另一个 Supabase 项目，并替换 `assets/supabase-config.js` 中的 URL 与 anon key。
- 若需要审计留痕，可把新增、修改、删除动作写入 `v4_audit_logs`。


## 第四版隔离说明

第四版前端读取 `assets/supabase-config.js` 中的 `tables` 配置，默认访问 `v4_projects`、`v4_events`、`v4_materials`、`v4_fte_entries`、`v4_profiles`，附件上传使用 `project-materials-v4` 文件桶。因此第四版新增、修改、删除数据不会影响第三版原表和第三版文件桶。

第四版内置展示数据已将原项目名替换为 `项目A`、`项目B`、`项目C`、`项目D`、`项目E`。
