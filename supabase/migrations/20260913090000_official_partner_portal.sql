-- Official Next Move partner onboarding, verification and settlements.
alter table public.partner_invite_codes
  drop constraint if exists partner_invite_codes_partner_role_check;
alter table public.partner_invite_codes
  add constraint partner_invite_codes_partner_role_check
  check (partner_role in ('merchant','stadium_owner','restaurant','gym_owner'));

alter table public.partner_profiles
  drop constraint if exists partner_profiles_status_check;
alter table public.partner_profiles
  add constraint partner_profiles_status_check
  check (status in ('pending','under_review','approved','rejected','suspended'));

alter table public.partner_profiles
  add column if not exists legal_name text,
  add column if not exists authorized_person text,
  add column if not exists phone text,
  add column if not exists governorate text default 'نينوى',
  add column if not exists district text,
  add column if not exists address text,
  add column if not exists registration_number text,
  add column if not exists tax_number text,
  add column if not exists commission_rate numeric(6,5) not null default 0.05000,
  add column if not exists settlement_cycle text not null default 'biweekly',
  add column if not exists payout_method text,
  add column if not exists payout_account_name text,
  add column if not exists payout_account_reference text,
  add column if not exists contract_version text,
  add column if not exists contract_accepted_at timestamptz,
  add column if not exists documents_submitted_at timestamptz,
  add column if not exists approved_at timestamptz,
  add column if not exists review_notes text,
  add column if not exists rejection_reason text;

alter table public.partner_profiles
  drop constraint if exists partner_profiles_commission_rate_check,
  drop constraint if exists partner_profiles_settlement_cycle_check;
alter table public.partner_profiles
  add constraint partner_profiles_commission_rate_check check (commission_rate >= 0 and commission_rate <= 1),
  add constraint partner_profiles_settlement_cycle_check check (settlement_cycle in ('weekly','biweekly','monthly'));

create or replace function public.protect_partner_controlled_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (select auth.role()) = 'authenticated' and (
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

drop trigger if exists protect_partner_controlled_fields on public.partner_profiles;
create trigger protect_partner_controlled_fields
before update on public.partner_profiles
for each row execute function public.protect_partner_controlled_fields();

create table if not exists public.partner_documents (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partner_profiles(user_id) on delete cascade,
  document_type text not null check (document_type in (
    'national_id_front','national_id_back','business_license','venue_proof','bank_proof','other'
  )),
  original_name text not null,
  storage_path text not null unique,
  mime_type text not null,
  file_size_bytes bigint not null check (file_size_bytes > 0 and file_size_bytes <= 10485760),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  rejection_reason text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.partner_documents enable row level security;
drop policy if exists "partners read own verification documents" on public.partner_documents;
create policy "partners read own verification documents"
on public.partner_documents for select to authenticated
using ((select auth.uid()) = partner_id);
drop policy if exists "partners upload own verification documents" on public.partner_documents;
create policy "partners upload own verification documents"
on public.partner_documents for insert to authenticated
with check (
  (select auth.uid()) = partner_id and
  exists (select 1 from public.partner_profiles p where p.user_id = (select auth.uid()))
);
drop policy if exists "partners delete pending verification documents" on public.partner_documents;
create policy "partners delete pending verification documents"
on public.partner_documents for delete to authenticated
using ((select auth.uid()) = partner_id and status in ('pending','rejected'));

grant select, insert, delete on public.partner_documents to authenticated;

create table if not exists public.partner_settlements (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.partner_profiles(user_id) on delete restrict,
  period_start date not null,
  period_end date not null,
  gross_iqd bigint not null default 0 check (gross_iqd >= 0),
  platform_commission_iqd bigint not null default 0 check (platform_commission_iqd >= 0),
  gateway_fees_iqd bigint not null default 0 check (gateway_fees_iqd >= 0),
  net_iqd bigint generated always as (gross_iqd - platform_commission_iqd - gateway_fees_iqd) stored,
  status text not null default 'draft' check (status in ('draft','approved','processing','paid','disputed')),
  payout_reference text,
  approved_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  check (period_end >= period_start),
  unique(partner_id, period_start, period_end)
);

alter table public.partner_settlements enable row level security;
drop policy if exists "partners read own settlements" on public.partner_settlements;
create policy "partners read own settlements"
on public.partner_settlements for select to authenticated
using ((select auth.uid()) = partner_id);
grant select on public.partner_settlements to authenticated;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values (
  'partner-documents','partner-documents',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "partners upload own official documents" on storage.objects;
create policy "partners upload own official documents"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'partner-documents' and
  (storage.foldername(name))[1] = (select auth.uid())::text and
  owner_id = (select auth.uid())::text and
  storage.extension(name) = any(array['jpg','jpeg','png','webp','pdf']) and
  exists (select 1 from public.partner_profiles p where p.user_id = (select auth.uid()))
);
drop policy if exists "partners read own official documents" on storage.objects;
create policy "partners read own official documents"
on storage.objects for select to authenticated
using (
  bucket_id = 'partner-documents' and
  (storage.foldername(name))[1] = (select auth.uid())::text and
  owner_id = (select auth.uid())::text
);
drop policy if exists "partners delete own pending official documents" on storage.objects;
create policy "partners delete own pending official documents"
on storage.objects for delete to authenticated
using (
  bucket_id = 'partner-documents' and
  (storage.foldername(name))[1] = (select auth.uid())::text and
  owner_id = (select auth.uid())::text and
  exists (
    select 1 from public.partner_documents d
    where d.storage_path = name and d.partner_id = (select auth.uid()) and d.status in ('pending','rejected')
  )
);

create or replace function public.redeem_partner_code_internal(
  p_user_id uuid,
  p_code text,
  p_business_name text,
  p_partner_role text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite public.partner_invite_codes%rowtype;
begin
  if p_user_id is null or not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_partner_role not in ('merchant','stadium_owner','restaurant','gym_owner') then
    raise exception 'INVALID_ROLE';
  end if;
  if char_length(btrim(p_business_name)) < 2 or char_length(btrim(p_business_name)) > 120 then
    raise exception 'INVALID_BUSINESS_NAME';
  end if;
  if exists (select 1 from public.partner_profiles where user_id = p_user_id) then
    raise exception 'ALREADY_PARTNER';
  end if;

  select * into v_invite
  from public.partner_invite_codes
  where code_hash = encode(extensions.digest(convert_to(upper(btrim(p_code)), 'UTF8'), 'sha256'),'hex')
    and used_by is null
    and (expires_at is null or expires_at > now())
  for update;

  if v_invite.id is null or not (
    v_invite.partner_role = p_partner_role or
    (p_partner_role = 'restaurant' and v_invite.partner_role = 'merchant') or
    (p_partner_role = 'gym_owner' and v_invite.partner_role = 'stadium_owner')
  ) then
    raise exception 'INVALID_OR_USED_CODE';
  end if;

  insert into public.partner_profiles(user_id,partner_role,business_name,status,invite_code_id)
  values (p_user_id,p_partner_role,btrim(p_business_name),'pending',v_invite.id);
  update public.partner_invite_codes set used_by=p_user_id, used_at=now() where id=v_invite.id;

  return jsonb_build_object('ok',true,'role',p_partner_role,'status','pending','business_name',btrim(p_business_name));
end;
$$;

revoke execute on function public.redeem_partner_code_internal(uuid,text,text,text) from public, anon, authenticated;
