-- Private owner-only access for the NextMove management page.
-- Only the verified Supabase Auth identity with this email is provisioned.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  admin_role text not null default 'owner' check (admin_role = 'owner'),
  created_at timestamptz not null default now()
);

alter table public.admin_users enable row level security;
revoke all on table public.admin_users from public, anon, authenticated;
grant select on table public.admin_users to authenticated;
drop policy if exists "owner can read own admin status" on public.admin_users;
create policy "owner can read own admin status"
on public.admin_users for select to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and exists (select 1 from public.admin_users a where a.user_id = (select auth.uid()));
$$;
revoke all on function public.is_platform_admin() from public, anon, authenticated;
grant execute on function public.is_platform_admin() to authenticated;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
create or replace function private.seed_nextmove_owner_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if lower(coalesce(new.email, '')) = 'fouadmotaz25@gmail.com' then
    insert into public.admin_users(user_id, admin_role)
    values (new.id, 'owner')
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function private.seed_nextmove_owner_admin() from public, anon, authenticated;
drop trigger if exists seed_nextmove_owner_admin on auth.users;
create trigger seed_nextmove_owner_admin
after insert on auth.users
for each row execute function private.seed_nextmove_owner_admin();

-- Provision the owner's account if it already exists; the trigger handles later signups.
insert into public.admin_users(user_id, admin_role)
select id, 'owner'
from auth.users
where lower(email) = 'fouadmotaz25@gmail.com'
on conflict (user_id) do nothing;

-- Admin-only reads and controlled updates. Existing partner-own policies remain in force.
do $$
begin
  if to_regclass('public.partner_profiles') is not null then
    alter table public.partner_profiles enable row level security;
    grant select, update on public.partner_profiles to authenticated;
    drop policy if exists "platform owner reads partner profiles" on public.partner_profiles;
    create policy "platform owner reads partner profiles" on public.partner_profiles
      for select to authenticated using ((select public.is_platform_admin()));
    drop policy if exists "platform owner updates partner profiles" on public.partner_profiles;
    create policy "platform owner updates partner profiles" on public.partner_profiles
      for update to authenticated
      using ((select public.is_platform_admin()))
      with check ((select public.is_platform_admin()));
  end if;

  if to_regclass('public.partner_documents') is not null then
    alter table public.partner_documents enable row level security;
    grant select, update on public.partner_documents to authenticated;
    drop policy if exists "platform owner reads partner documents" on public.partner_documents;
    create policy "platform owner reads partner documents" on public.partner_documents
      for select to authenticated using ((select public.is_platform_admin()));
    drop policy if exists "platform owner reviews partner documents" on public.partner_documents;
    create policy "platform owner reviews partner documents" on public.partner_documents
      for update to authenticated
      using ((select public.is_platform_admin()))
      with check ((select public.is_platform_admin()));
  end if;

  if to_regclass('public.partner_settlements') is not null then
    alter table public.partner_settlements enable row level security;
    grant select, update on public.partner_settlements to authenticated;
    drop policy if exists "platform owner reads partner settlements" on public.partner_settlements;
    create policy "platform owner reads partner settlements" on public.partner_settlements
      for select to authenticated using ((select public.is_platform_admin()));
    drop policy if exists "platform owner updates partner settlements" on public.partner_settlements;
    create policy "platform owner updates partner settlements" on public.partner_settlements
      for update to authenticated
      using ((select public.is_platform_admin()))
      with check ((select public.is_platform_admin()));
  end if;
end;
$$;

-- Partner review triggers protect status fields from regular partner accounts.
-- Permit this owner's authenticated admin session to perform those reviewed changes.
create or replace function public.protect_partner_controlled_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (select auth.uid()) is not null
     and not (select public.is_platform_admin())
     and (
       old.user_id is distinct from new.user_id or
       old.partner_role is distinct from new.partner_role or
       old.invite_code_id is distinct from new.invite_code_id or
       old.status is distinct from new.status or
       old.commission_rate is distinct from new.commission_rate or
       old.settlement_cycle is distinct from new.settlement_cycle or
       old.approved_at is distinct from new.approved_at or
       old.review_notes is distinct from new.review_notes or
       old.rejection_reason is distinct from new.rejection_reason
     ) then
    raise exception 'PARTNER_CONTROLLED_FIELDS';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

