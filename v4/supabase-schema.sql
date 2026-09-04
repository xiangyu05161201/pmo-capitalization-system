-- PMO资本化管理系统第四版 Supabase 初始化脚本
-- 使用方式：在 Supabase SQL Editor 中整段执行。
-- 说明：前端使用 anon key + Supabase Auth；权限由 RLS 控制，PMO 可写，财务只读。

create extension if not exists pgcrypto;

create table if not exists public.v4_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('pmo','finance')) default 'finance',
  display_name text,
  department text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.v4_projects (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  type text default '未提供',
  owner text default '未提供',
  current_stage text default '-',
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.v4_events (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.v4_projects(id) on delete cascade,
  project_name text not null,
  stage text not null,
  label text not null,
  event_type text not null default '上会',
  result text not null check (result in ('已通过','未通过','待定')) default '待定',
  event_time text,
  note text default '',
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint v4_events_project_stage_label_unique unique(project_name, stage, label)
);

create table if not exists public.v4_materials (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.v4_projects(id) on delete cascade,
  event_id uuid references public.v4_events(id) on delete cascade,
  project_name text not null,
  stage text not null,
  event_label text not null,
  event_type text not null default '上会',
  material_type text not null,
  name text not null,
  required boolean not null default true,
  status text not null check (status in ('missing','pending','archived')) default 'missing',
  source_type text not null default 'link' check (source_type in ('link','file','text')),
  material_link text default '',
  storage_path text default '',
  content_text text default '',
  note text default '',
  uploaded_by text default '',
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint v4_materials_unique unique(project_name, stage, event_label, material_type)
);

alter table public.v4_materials add column if not exists source_type text not null default 'link';
alter table public.v4_materials add column if not exists content_text text default '';
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'v4_materials_source_type_check'
  ) then
    alter table public.v4_materials
      add constraint v4_materials_source_type_check check (source_type in ('link','file','text'));
  end if;
end $$;

create table if not exists public.v4_fte_entries (
  id uuid primary key default gen_random_uuid(),
  project_name text not null,
  month text not null,
  value numeric not null default 0,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint v4_fte_entries_unique unique(project_name, month)
);

create table if not exists public.v4_audit_logs (
  id bigint generated always as identity primary key,
  actor uuid references auth.users(id),
  action text not null,
  target_table text,
  target_id uuid,
  detail jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.v4_current_role_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.v4_profiles where user_id = auth.uid()), 'finance')
$$;

create or replace function public.v4_is_pmo()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.v4_current_role_name() = 'pmo'
$$;

create or replace function public.v4_touch_row()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  new.updated_by = auth.uid();
  if tg_op = 'INSERT' then
    new.created_by = coalesce(new.created_by, auth.uid());
  end if;
  return new;
end;
$$;

drop trigger if exists touch_v4_projects on public.v4_projects;
create trigger touch_v4_projects before insert or update on public.v4_projects for each row execute function public.v4_touch_row();

drop trigger if exists touch_v4_events on public.v4_events;
create trigger touch_v4_events before insert or update on public.v4_events for each row execute function public.v4_touch_row();

drop trigger if exists touch_v4_materials on public.v4_materials;
create trigger touch_v4_materials before insert or update on public.v4_materials for each row execute function public.v4_touch_row();

drop trigger if exists touch_v4_fte_entries on public.v4_fte_entries;
create trigger touch_v4_fte_entries before insert or update on public.v4_fte_entries for each row execute function public.v4_touch_row();

alter table public.v4_profiles enable row level security;
alter table public.v4_projects enable row level security;
alter table public.v4_events enable row level security;
alter table public.v4_materials enable row level security;
alter table public.v4_fte_entries enable row level security;
alter table public.v4_audit_logs enable row level security;

-- profiles：登录用户可读自己的 profile；PMO 可读全部，便于管理角色。
drop policy if exists v4_profiles_select on public.v4_profiles;
create policy v4_profiles_select on public.v4_profiles for select to authenticated
using (user_id = auth.uid() or public.v4_is_pmo());

drop policy if exists v4_profiles_update_self on public.v4_profiles;
create policy v4_profiles_update_self on public.v4_profiles for update to authenticated
using (user_id = auth.uid() or public.v4_is_pmo())
with check (user_id = auth.uid() or public.v4_is_pmo());

-- 业务表：PMO、财务均可读；仅 PMO 可新增、修改、删除。
drop policy if exists v4_projects_select on public.v4_projects;
create policy v4_projects_select on public.v4_projects for select to authenticated using (true);
drop policy if exists v4_projects_insert_pmo on public.v4_projects;
create policy v4_projects_insert_pmo on public.v4_projects for insert to authenticated with check (public.v4_is_pmo());
drop policy if exists v4_projects_update_pmo on public.v4_projects;
create policy v4_projects_update_pmo on public.v4_projects for update to authenticated using (public.v4_is_pmo()) with check (public.v4_is_pmo());
drop policy if exists v4_projects_delete_pmo on public.v4_projects;
create policy v4_projects_delete_pmo on public.v4_projects for delete to authenticated using (public.v4_is_pmo());

drop policy if exists v4_events_select on public.v4_events;
create policy v4_events_select on public.v4_events for select to authenticated using (true);
drop policy if exists v4_events_insert_pmo on public.v4_events;
create policy v4_events_insert_pmo on public.v4_events for insert to authenticated with check (public.v4_is_pmo());
drop policy if exists v4_events_update_pmo on public.v4_events;
create policy v4_events_update_pmo on public.v4_events for update to authenticated using (public.v4_is_pmo()) with check (public.v4_is_pmo());
drop policy if exists v4_events_delete_pmo on public.v4_events;
create policy v4_events_delete_pmo on public.v4_events for delete to authenticated using (public.v4_is_pmo());

drop policy if exists v4_materials_select on public.v4_materials;
create policy v4_materials_select on public.v4_materials for select to authenticated using (true);
drop policy if exists v4_materials_insert_pmo on public.v4_materials;
create policy v4_materials_insert_pmo on public.v4_materials for insert to authenticated with check (public.v4_is_pmo());
drop policy if exists v4_materials_update_pmo on public.v4_materials;
create policy v4_materials_update_pmo on public.v4_materials for update to authenticated using (public.v4_is_pmo()) with check (public.v4_is_pmo());
drop policy if exists v4_materials_delete_pmo on public.v4_materials;
create policy v4_materials_delete_pmo on public.v4_materials for delete to authenticated using (public.v4_is_pmo());

drop policy if exists v4_fte_entries_select on public.v4_fte_entries;
create policy v4_fte_entries_select on public.v4_fte_entries for select to authenticated using (true);
drop policy if exists v4_fte_entries_insert_pmo on public.v4_fte_entries;
create policy v4_fte_entries_insert_pmo on public.v4_fte_entries for insert to authenticated with check (public.v4_is_pmo());
drop policy if exists v4_fte_entries_update_pmo on public.v4_fte_entries;
create policy v4_fte_entries_update_pmo on public.v4_fte_entries for update to authenticated using (public.v4_is_pmo()) with check (public.v4_is_pmo());
drop policy if exists v4_fte_entries_delete_pmo on public.v4_fte_entries;
create policy v4_fte_entries_delete_pmo on public.v4_fte_entries for delete to authenticated using (public.v4_is_pmo());

drop policy if exists v4_audit_logs_select_pmo on public.v4_audit_logs;
create policy v4_audit_logs_select_pmo on public.v4_audit_logs for select to authenticated using (public.v4_is_pmo());
drop policy if exists v4_audit_logs_insert_auth on public.v4_audit_logs;
create policy v4_audit_logs_insert_auth on public.v4_audit_logs for insert to authenticated with check (actor = auth.uid());

-- 文件存储：请在 Supabase Storage 中创建私有 bucket：project-materials-v4。
-- 若你希望前端直接上传附件，执行以下策略前请确认 bucket 名称就是 project-materials-v4。
insert into storage.buckets (id, name, public)
values ('project-materials-v4', 'project-materials-v4', false)
on conflict (id) do nothing;

drop policy if exists storage_v4_materials_select on storage.objects;
create policy storage_v4_materials_select on storage.objects for select to authenticated
using (bucket_id = 'project-materials-v4');

drop policy if exists storage_v4_materials_insert_pmo on storage.objects;
create policy storage_v4_materials_insert_pmo on storage.objects for insert to authenticated
with check (bucket_id = 'project-materials-v4' and public.v4_is_pmo());

drop policy if exists storage_v4_materials_update_pmo on storage.objects;
create policy storage_v4_materials_update_pmo on storage.objects for update to authenticated
using (bucket_id = 'project-materials-v4' and public.v4_is_pmo())
with check (bucket_id = 'project-materials-v4' and public.v4_is_pmo());

drop policy if exists storage_v4_materials_delete_pmo on storage.objects;
create policy storage_v4_materials_delete_pmo on storage.objects for delete to authenticated
using (bucket_id = 'project-materials-v4' and public.v4_is_pmo());

-- 创建用户后，在 auth.users 中查到 user id，再执行示例：
-- insert into public.v4_profiles(user_id, role, display_name, department)
-- values ('用户UUID', 'pmo', '张瑶', 'PMO')
-- on conflict (user_id) do update set role=excluded.role, display_name=excluded.display_name, department=excluded.department;
--
-- insert into public.v4_profiles(user_id, role, display_name, department)
-- values ('用户UUID', 'finance', '王珂', '财务')
-- on conflict (user_id) do update set role=excluded.role, display_name=excluded.display_name, department=excluded.department;

-- 第四版初始化数据：从第三版表复制一份到 v4_* 独立表，并将示例项目名称改为 项目A / 项目B / 项目C / 项目D / 项目E。
-- 该段为一次性初始化，可重复执行；后续第四版写入 v4_* 表，不会影响第三版原表。
do $$
begin
  if to_regclass('public.profiles') is not null then
    execute $copy$
      insert into public.v4_profiles(user_id, role, display_name, department)
      select user_id, role, display_name, department from public.profiles
      on conflict (user_id) do update set
        role = excluded.role,
        display_name = excluded.display_name,
        department = excluded.department
    $copy$;
  end if;

  if to_regclass('public.projects') is not null then
    execute $copy$
      insert into public.v4_projects(name, type, owner, current_stage)
      select case name
          when '代号：沦陷' then '项目A'
          when '代号：纸片' then '项目B'
          when '代号：U' then '项目C'
          when '代号：Pack' then '项目D'
          when '代号：N3' then '项目E'
          else name
        end as name,
        type, owner, current_stage
      from public.projects
      on conflict (name) do update set
        type = excluded.type,
        owner = excluded.owner,
        current_stage = excluded.current_stage
    $copy$;
  end if;

  if to_regclass('public.events') is not null then
    execute $copy$
      insert into public.v4_events(project_id, project_name, stage, label, event_type, result, event_time, note)
      select vp.id,
        case e.project_name
          when '代号：沦陷' then '项目A'
          when '代号：纸片' then '项目B'
          when '代号：U' then '项目C'
          when '代号：Pack' then '项目D'
          when '代号：N3' then '项目E'
          else e.project_name
        end as project_name,
        e.stage, e.label, e.event_type, e.result, e.event_time, e.note
      from public.events e
      join public.v4_projects vp on vp.name = case e.project_name
        when '代号：沦陷' then '项目A'
        when '代号：纸片' then '项目B'
        when '代号：U' then '项目C'
        when '代号：Pack' then '项目D'
        when '代号：N3' then '项目E'
        else e.project_name
      end
      on conflict (project_name, stage, label) do update set
        event_type = excluded.event_type,
        result = excluded.result,
        event_time = excluded.event_time,
        note = excluded.note,
        project_id = excluded.project_id
    $copy$;
  end if;

  if to_regclass('public.materials') is not null then
    execute $copy$
      insert into public.v4_materials(project_id, event_id, project_name, stage, event_label, event_type, material_type, name, required, status, source_type, material_link, storage_path, content_text, note, uploaded_by)
      select vp.id, ve.id,
        case m.project_name
          when '代号：沦陷' then '项目A'
          when '代号：纸片' then '项目B'
          when '代号：U' then '项目C'
          when '代号：Pack' then '项目D'
          when '代号：N3' then '项目E'
          else m.project_name
        end as project_name,
        m.stage, m.event_label, m.event_type, m.material_type, m.name, m.required, m.status,
        coalesce(m.source_type, 'link'), coalesce(m.material_link, ''), coalesce(m.storage_path, ''), coalesce(m.content_text, ''), coalesce(m.note, ''), coalesce(m.uploaded_by, '')
      from public.materials m
      join public.v4_projects vp on vp.name = case m.project_name
        when '代号：沦陷' then '项目A'
        when '代号：纸片' then '项目B'
        when '代号：U' then '项目C'
        when '代号：Pack' then '项目D'
        when '代号：N3' then '项目E'
        else m.project_name
      end
      left join public.v4_events ve on ve.project_name = vp.name and ve.stage = m.stage and ve.label = m.event_label
      on conflict (project_name, stage, event_label, material_type) do update set
        event_type = excluded.event_type,
        name = excluded.name,
        required = excluded.required,
        status = excluded.status,
        source_type = excluded.source_type,
        material_link = excluded.material_link,
        storage_path = excluded.storage_path,
        content_text = excluded.content_text,
        note = excluded.note,
        uploaded_by = excluded.uploaded_by,
        project_id = excluded.project_id,
        event_id = excluded.event_id
    $copy$;
  end if;

  if to_regclass('public.fte_entries') is not null then
    execute $copy$
      insert into public.v4_fte_entries(project_name, month, value)
      select case project_name
          when '代号：沦陷' then '项目A'
          when '代号：纸片' then '项目B'
          when '代号：U' then '项目C'
          when '代号：Pack' then '项目D'
          when '代号：N3' then '项目E'
          else project_name
        end as project_name,
        month, value
      from public.fte_entries
      on conflict (project_name, month) do update set value = excluded.value
    $copy$;
  end if;
end $$;
