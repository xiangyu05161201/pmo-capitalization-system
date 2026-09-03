-- PMO资本化管理系统 Supabase 初始化脚本
-- 使用方式：在 Supabase SQL Editor 中整段执行。
-- 说明：前端使用 anon key + Supabase Auth；权限由 RLS 控制，PMO 可写，财务只读。

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('pmo','finance')) default 'finance',
  display_name text,
  department text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.projects (
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

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete cascade,
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
  constraint events_project_stage_label_unique unique(project_name, stage, label)
);

create table if not exists public.materials (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
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
  constraint materials_unique unique(project_name, stage, event_label, material_type)
);

alter table public.materials add column if not exists source_type text not null default 'link';
alter table public.materials add column if not exists content_text text default '';
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'materials_source_type_check'
  ) then
    alter table public.materials
      add constraint materials_source_type_check check (source_type in ('link','file','text'));
  end if;
end $$;

create table if not exists public.fte_entries (
  id uuid primary key default gen_random_uuid(),
  project_name text not null,
  month text not null,
  value numeric not null default 0,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fte_entries_unique unique(project_name, month)
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor uuid references auth.users(id),
  action text not null,
  target_table text,
  target_id uuid,
  detail jsonb default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.current_role_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role from public.profiles where user_id = auth.uid()), 'finance')
$$;

create or replace function public.is_pmo()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_role_name() = 'pmo'
$$;

create or replace function public.touch_row()
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

drop trigger if exists touch_projects on public.projects;
create trigger touch_projects before insert or update on public.projects for each row execute function public.touch_row();

drop trigger if exists touch_events on public.events;
create trigger touch_events before insert or update on public.events for each row execute function public.touch_row();

drop trigger if exists touch_materials on public.materials;
create trigger touch_materials before insert or update on public.materials for each row execute function public.touch_row();

drop trigger if exists touch_fte_entries on public.fte_entries;
create trigger touch_fte_entries before insert or update on public.fte_entries for each row execute function public.touch_row();

alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.events enable row level security;
alter table public.materials enable row level security;
alter table public.fte_entries enable row level security;
alter table public.audit_logs enable row level security;

-- profiles：登录用户可读自己的 profile；PMO 可读全部，便于管理角色。
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using (user_id = auth.uid() or public.is_pmo());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
using (user_id = auth.uid() or public.is_pmo())
with check (user_id = auth.uid() or public.is_pmo());

-- 业务表：PMO、财务均可读；仅 PMO 可新增、修改、删除。
drop policy if exists projects_select on public.projects;
create policy projects_select on public.projects for select to authenticated using (true);
drop policy if exists projects_insert_pmo on public.projects;
create policy projects_insert_pmo on public.projects for insert to authenticated with check (public.is_pmo());
drop policy if exists projects_update_pmo on public.projects;
create policy projects_update_pmo on public.projects for update to authenticated using (public.is_pmo()) with check (public.is_pmo());
drop policy if exists projects_delete_pmo on public.projects;
create policy projects_delete_pmo on public.projects for delete to authenticated using (public.is_pmo());

drop policy if exists events_select on public.events;
create policy events_select on public.events for select to authenticated using (true);
drop policy if exists events_insert_pmo on public.events;
create policy events_insert_pmo on public.events for insert to authenticated with check (public.is_pmo());
drop policy if exists events_update_pmo on public.events;
create policy events_update_pmo on public.events for update to authenticated using (public.is_pmo()) with check (public.is_pmo());
drop policy if exists events_delete_pmo on public.events;
create policy events_delete_pmo on public.events for delete to authenticated using (public.is_pmo());

drop policy if exists materials_select on public.materials;
create policy materials_select on public.materials for select to authenticated using (true);
drop policy if exists materials_insert_pmo on public.materials;
create policy materials_insert_pmo on public.materials for insert to authenticated with check (public.is_pmo());
drop policy if exists materials_update_pmo on public.materials;
create policy materials_update_pmo on public.materials for update to authenticated using (public.is_pmo()) with check (public.is_pmo());
drop policy if exists materials_delete_pmo on public.materials;
create policy materials_delete_pmo on public.materials for delete to authenticated using (public.is_pmo());

drop policy if exists fte_entries_select on public.fte_entries;
create policy fte_entries_select on public.fte_entries for select to authenticated using (true);
drop policy if exists fte_entries_insert_pmo on public.fte_entries;
create policy fte_entries_insert_pmo on public.fte_entries for insert to authenticated with check (public.is_pmo());
drop policy if exists fte_entries_update_pmo on public.fte_entries;
create policy fte_entries_update_pmo on public.fte_entries for update to authenticated using (public.is_pmo()) with check (public.is_pmo());
drop policy if exists fte_entries_delete_pmo on public.fte_entries;
create policy fte_entries_delete_pmo on public.fte_entries for delete to authenticated using (public.is_pmo());

drop policy if exists audit_logs_select_pmo on public.audit_logs;
create policy audit_logs_select_pmo on public.audit_logs for select to authenticated using (public.is_pmo());
drop policy if exists audit_logs_insert_auth on public.audit_logs;
create policy audit_logs_insert_auth on public.audit_logs for insert to authenticated with check (actor = auth.uid());

-- 文件存储：请在 Supabase Storage 中创建私有 bucket：project-materials。
-- 若你希望前端直接上传附件，执行以下策略前请确认 bucket 名称就是 project-materials。
insert into storage.buckets (id, name, public)
values ('project-materials', 'project-materials', false)
on conflict (id) do nothing;

drop policy if exists storage_materials_select on storage.objects;
create policy storage_materials_select on storage.objects for select to authenticated
using (bucket_id = 'project-materials');

drop policy if exists storage_materials_insert_pmo on storage.objects;
create policy storage_materials_insert_pmo on storage.objects for insert to authenticated
with check (bucket_id = 'project-materials' and public.is_pmo());

drop policy if exists storage_materials_update_pmo on storage.objects;
create policy storage_materials_update_pmo on storage.objects for update to authenticated
using (bucket_id = 'project-materials' and public.is_pmo())
with check (bucket_id = 'project-materials' and public.is_pmo());

drop policy if exists storage_materials_delete_pmo on storage.objects;
create policy storage_materials_delete_pmo on storage.objects for delete to authenticated
using (bucket_id = 'project-materials' and public.is_pmo());

-- 创建用户后，在 auth.users 中查到 user id，再执行示例：
-- insert into public.profiles(user_id, role, display_name, department)
-- values ('用户UUID', 'pmo', '张瑶', 'PMO')
-- on conflict (user_id) do update set role=excluded.role, display_name=excluded.display_name, department=excluded.department;
--
-- insert into public.profiles(user_id, role, display_name, department)
-- values ('用户UUID', 'finance', '王珂', '财务')
-- on conflict (user_id) do update set role=excluded.role, display_name=excluded.display_name, department=excluded.department;
