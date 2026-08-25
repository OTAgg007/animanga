create extension if not exists pgcrypto;

create table if not exists roles (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  description text,
  permissions jsonb not null default '{}'::jsonb,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  avatar_url text,
  points_balance int not null default 0 check(points_balance >= 0),
  role_id uuid references roles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists manga (
  id uuid primary key default gen_random_uuid(), title text not null, slug text unique not null,
  description text, author text, artist text, cover_url text, status text not null default 'ongoing',
  featured boolean not null default false, created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists chapters (
  id uuid primary key default gen_random_uuid(), manga_id uuid not null references manga(id) on delete cascade,
  number numeric not null, title text, access_type text not null default 'free' check(access_type in ('free','points')),
  points_price int not null default 0 check(points_price >= 0), status text not null default 'published',
  created_by uuid references profiles(id) on delete set null, created_at timestamptz not null default now(),
  unique(manga_id,number)
);

create table if not exists chapter_pages (
  id uuid primary key default gen_random_uuid(), chapter_id uuid not null references chapters(id) on delete cascade,
  page_number int not null, image_path text not null, image_url text, created_at timestamptz not null default now(),
  unique(chapter_id,page_number)
);

create table if not exists chapter_unlocks (
  user_id uuid not null references profiles(id) on delete cascade,
  chapter_id uuid not null references chapters(id) on delete cascade,
  points_spent int not null default 0, created_at timestamptz not null default now(),
  primary key(user_id,chapter_id)
);

create table if not exists point_transactions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references profiles(id) on delete cascade,
  amount int not null, type text not null, description text, created_at timestamptz not null default now()
);

insert into roles(name,description,permissions,is_system) values
('Owner','كل الصلاحيات','{"manage_users":true,"manage_roles":true,"manage_manga":true,"manage_chapters":true,"upload_pages":true,"manage_points":true,"view_dashboard":true}',true),
('Admin','إدارة الموقع','{"manage_users":true,"manage_roles":false,"manage_manga":true,"manage_chapters":true,"upload_pages":true,"manage_points":true,"view_dashboard":true}',true),
('Editor','تحرير المحتوى','{"manage_users":false,"manage_roles":false,"manage_manga":true,"manage_chapters":true,"upload_pages":true,"manage_points":false,"view_dashboard":true}',true),
('Uploader','رفع الصفحات','{"manage_users":false,"manage_roles":false,"manage_manga":false,"manage_chapters":false,"upload_pages":true,"manage_points":false,"view_dashboard":true}',true),
('Member','قارئ','{"manage_users":false,"manage_roles":false,"manage_manga":false,"manage_chapters":false,"upload_pages":false,"manage_points":false,"view_dashboard":false}',true)
on conflict(name) do nothing;

create or replace function public.has_permission(uid uuid, perm text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from profiles p join roles r on r.id=p.role_id where p.id=uid and coalesce((r.permissions->>perm)::boolean,false));
$$;

create or replace function public.is_owner(uid uuid default auth.uid()) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from profiles p join roles r on r.id=p.role_id where p.id=uid and r.name='Owner');
$$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
declare assigned_role uuid; begin
  if not exists(select 1 from profiles p join roles r on r.id=p.role_id where r.name='Owner') then
    select id into assigned_role from roles where name='Owner';
  else
    select id into assigned_role from roles where name='Member';
  end if;
  insert into profiles(id,display_name,role_id) values(new.id, coalesce(new.raw_user_meta_data->>'display_name',split_part(new.email,'@',1)), assigned_role)
  on conflict(id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.bootstrap_first_owner() returns void language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from profiles p join roles r on r.id=p.role_id where r.name='Owner') then
    update profiles set role_id=(select id from roles where name='Owner') where id=auth.uid();
  end if;
end; $$;

create or replace function public.spend_points(p_chapter uuid) returns boolean
language plpgsql security definer set search_path=public as $$
declare price int; uid uuid := auth.uid(); bal int; begin
  if uid is null then raise exception 'not_authenticated'; end if;
  if exists(select 1 from chapter_unlocks where user_id=uid and chapter_id=p_chapter) then return true; end if;
  select points_price into price from chapters where id=p_chapter and access_type='points' and status='published';
  if price is null then return false; end if;
  select points_balance into bal from profiles where id=uid for update;
  if coalesce(bal,0) < price then return false; end if;
  update profiles set points_balance=points_balance-price where id=uid;
  insert into point_transactions(user_id,amount,type,description) values(uid,-price,'chapter_unlock','Unlock chapter');
  insert into chapter_unlocks(user_id,chapter_id,points_spent) values(uid,p_chapter,price);
  return true;
end; $$;


create or replace function public.admin_adjust_points(target_user uuid, delta int, note text default 'Admin adjustment') returns boolean
language plpgsql security definer set search_path=public as $$
begin
  if not public.has_permission(auth.uid(),'manage_points') then raise exception 'forbidden'; end if;
  update profiles set points_balance=greatest(0,points_balance+delta) where id=target_user;
  insert into point_transactions(user_id,amount,type,description) values(target_user,delta,'admin_adjustment',note);
  return true;
end; $$;

create or replace function public.guard_role_changes() returns trigger language plpgsql security definer set search_path=public as $$
declare old_name text; new_name text;
begin
  if new.role_id is distinct from old.role_id then
    select name into old_name from roles where id=old.role_id;
    select name into new_name from roles where id=new.role_id;
    if not public.is_owner(auth.uid()) and (old_name='Owner' or new_name='Owner') then raise exception 'only owner can assign owner'; end if;
  end if;
  return new;
end; $$;
drop trigger if exists guard_profile_role_changes on profiles;
create trigger guard_profile_role_changes before update of role_id on profiles for each row execute procedure public.guard_role_changes();
alter table roles enable row level security; alter table profiles enable row level security; alter table manga enable row level security;
alter table chapters enable row level security; alter table chapter_pages enable row level security; alter table chapter_unlocks enable row level security; alter table point_transactions enable row level security;

drop policy if exists roles_read on roles; create policy roles_read on roles for select using(true);
drop policy if exists roles_owner_write on roles; create policy roles_owner_write on roles for all using(public.is_owner()) with check(public.is_owner());
drop policy if exists profiles_self_read on profiles; create policy profiles_self_read on profiles for select using(auth.uid()=id or public.has_permission(auth.uid(),'manage_users'));
drop policy if exists profiles_self_update on profiles; create policy profiles_self_update on profiles for update using(auth.uid()=id or public.has_permission(auth.uid(),'manage_users')) with check(auth.uid()=id or public.has_permission(auth.uid(),'manage_users'));
drop policy if exists manga_read on manga; create policy manga_read on manga for select using(true);
drop policy if exists manga_manage on manga; create policy manga_manage on manga for all using(public.has_permission(auth.uid(),'manage_manga')) with check(public.has_permission(auth.uid(),'manage_manga'));
drop policy if exists chapters_read on chapters; create policy chapters_read on chapters for select using(status='published' or public.has_permission(auth.uid(),'manage_chapters'));
drop policy if exists chapters_manage on chapters; create policy chapters_manage on chapters for all using(public.has_permission(auth.uid(),'manage_chapters')) with check(public.has_permission(auth.uid(),'manage_chapters'));
drop policy if exists pages_read on chapter_pages; create policy pages_read on chapter_pages for select using(exists(select 1 from chapters c where c.id=chapter_pages.chapter_id and (c.access_type='free' or public.has_permission(auth.uid(),'manage_chapters') or exists(select 1 from chapter_unlocks u where u.user_id=auth.uid() and u.chapter_id=c.id))));
drop policy if exists pages_manage on chapter_pages; create policy pages_manage on chapter_pages for all using(public.has_permission(auth.uid(),'upload_pages')) with check(public.has_permission(auth.uid(),'upload_pages'));
drop policy if exists unlock_self on chapter_unlocks; create policy unlock_self on chapter_unlocks for select using(user_id=auth.uid());
drop policy if exists tx_self on point_transactions; create policy tx_self on point_transactions for select using(user_id=auth.uid());

-- Storage bucket (create via dashboard if this statement is not allowed in your project)
insert into storage.buckets(id,name,public) values('manga-pages','manga-pages',false) on conflict(id) do nothing;

drop policy if exists manga_pages_read on storage.objects;
create policy manga_pages_read on storage.objects for select using(bucket_id='manga-pages' and (public.has_permission(auth.uid(),'upload_pages') or exists(select 1 from chapter_pages cp where cp.image_path=name and (exists(select 1 from chapter_unlocks u where u.user_id=auth.uid() and u.chapter_id=cp.chapter_id) or exists(select 1 from chapters c where c.id=cp.chapter_id and c.access_type='free')))));
drop policy if exists manga_pages_insert on storage.objects;
create policy manga_pages_insert on storage.objects for insert with check(bucket_id='manga-pages' and public.has_permission(auth.uid(),'upload_pages'));
drop policy if exists manga_pages_delete on storage.objects;
create policy manga_pages_delete on storage.objects for delete using(bucket_id='manga-pages' and public.has_permission(auth.uid(),'upload_pages'));
