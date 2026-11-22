-- Initial schema for a fresh NextMove Supabase project.
-- Existing records from the inaccessible previous project are not copied by this migration.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.partner_invite_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash text not null unique,
  partner_role text not null check (partner_role in ('merchant','stadium_owner','restaurant','gym_owner')),
  expires_at timestamptz,
  used_by uuid references auth.users(id) on delete set null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.partner_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  partner_role text not null check (partner_role in ('merchant','stadium_owner','restaurant','gym_owner')),
  business_name text not null,
  invite_code_id uuid references public.partner_invite_codes(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','under_review','approved','rejected','suspended')),
  commission_rate numeric(6,5) not null default 0.05 check (commission_rate between 0 and 1),
  settlement_cycle text not null default 'biweekly' check (settlement_cycle in ('weekly','biweekly','monthly')),
  legal_name text, authorized_person text, phone text, governorate text default 'نينوى',
  district text, address text, registration_number text, tax_number text,
  payout_method text, payout_account_name text, payout_account_reference text,
  contract_version text, contract_accepted_at timestamptz, documents_submitted_at timestamptz,
  approved_at timestamptz, review_notes text, rejection_reason text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.partner_notifications (
  id uuid primary key default gen_random_uuid(), recipient_id uuid not null references auth.users(id) on delete cascade,
  kind text not null default 'product_order', title text not null, message text not null,
  reference_id text, is_read boolean not null default false, created_at timestamptz not null default now()
);

create table if not exists public.partner_stadiums (
  id bigint generated always as identity primary key, owner_id uuid not null references public.partner_profiles(user_id) on delete cascade,
  name text not null, area text not null, price_iqd integer not null check (price_iqd >= 0),
  pitch_size text not null default 'خماسي', image_url text, features text[] not null default '{}',
  rating numeric(3,2) not null default 0, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.stadium_time_slots (
  id bigint generated always as identity primary key,
  stadium_id bigint not null references public.partner_stadiums(id) on delete cascade,
  slot_date date not null, start_time time not null,
  status text not null default 'available' check (status in ('available','booked')),
  created_at timestamptz not null default now(), unique(stadium_id,slot_date,start_time)
);

create table if not exists public.stadium_bookings (
  id bigint generated always as identity primary key,
  slot_id bigint not null unique references public.stadium_time_slots(id) on delete restrict,
  customer_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'confirmed' check (status in ('pending','confirmed','cancelled','completed')),
  total_iqd bigint not null check (total_iqd >= 0),
  payment_status text not null default 'pending', payment_provider text, payment_reference text,
  deposit_required_iqd bigint not null default 0, deposit_paid_iqd bigint not null default 0,
  deposit_payment_reference text, deposit_paid_at timestamptz,
  join_code text unique, created_at timestamptz not null default now()
);

create table if not exists public.stadium_booking_shares (
  id bigint generated always as identity primary key,
  booking_id bigint not null references public.stadium_bookings(id) on delete cascade,
  player_name text not null, amount_iqd bigint not null check (amount_iqd >= 0),
  status text not null default 'pending', paid_at timestamptz, created_at timestamptz not null default now()
);

create table if not exists public.market_products (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.partner_profiles(user_id) on delete cascade,
  title text not null, description text not null default '', specifications text not null default '',
  category text not null, price_iqd integer not null check (price_iqd > 0), stock integer not null default 0 check (stock >= 0),
  image_url text, brand text, sizes text[] not null default '{}', product_condition text not null default 'new',
  delivery_available boolean not null default true, is_active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.product_orders (
  id bigint generated always as identity primary key,
  product_id bigint not null references public.market_products(id) on delete restrict,
  customer_id uuid not null references auth.users(id) on delete restrict,
  merchant_id uuid not null references auth.users(id) on delete restrict,
  quantity integer not null default 1 check (quantity between 1 and 100),
  unit_price_iqd integer not null check (unit_price_iqd > 0), total_iqd bigint generated always as (quantity * unit_price_iqd) stored,
  status text not null default 'new', payment_status text not null default 'pending',
  payment_provider text, payment_reference text, paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.partner_documents (
  id uuid primary key default gen_random_uuid(), partner_id uuid not null references public.partner_profiles(user_id) on delete cascade,
  document_type text not null check(document_type in ('national_id_front','national_id_back','business_license','venue_proof','bank_proof','other')),
  original_name text not null, storage_path text not null unique,
  mime_type text not null, file_size_bytes bigint not null check(file_size_bytes between 1 and 10485760),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  rejection_reason text, reviewed_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.partner_settlements (
  id uuid primary key default gen_random_uuid(), partner_id uuid not null references public.partner_profiles(user_id) on delete restrict,
  period_start date not null, period_end date not null, gross_iqd bigint not null default 0,
  platform_commission_iqd bigint not null default 0, gateway_fees_iqd bigint not null default 0,
  net_iqd bigint generated always as (gross_iqd-platform_commission_iqd-gateway_fees_iqd) stored,
  status text not null default 'draft', payout_reference text, approved_at timestamptz, paid_at timestamptz,
  created_at timestamptz not null default now(), unique(partner_id,period_start,period_end), check(period_end>=period_start)
);
create table if not exists public.partner_contracts (
  id uuid primary key default gen_random_uuid(), partner_id uuid references public.partner_profiles(user_id) on delete set null,
  contract_number text not null unique, governorate text, category text, partnership_scope text,
  platform_percent numeric(6,3), partner_percent numeric(6,3), settlement_cycle text,
  status text not null default 'draft', starts_on date, ends_on date, created_at timestamptz not null default now()
);
create table if not exists public.partner_financial_entries (
  id uuid primary key default gen_random_uuid(), partner_id uuid references public.partner_profiles(user_id) on delete set null,
  entry_type text not null, amount_iqd bigint not null, status text not null default 'recorded',
  description text, occurred_on date, planned_for date, reference_number text, created_at timestamptz not null default now()
);
create table if not exists public.partner_commission_rules (
  id uuid primary key default gen_random_uuid(), governorate text, category text, partner_role text,
  platform_percent numeric(6,3) not null default 5, partner_percent numeric(6,3) not null default 95,
  effective_from date not null default current_date, effective_to date, is_active boolean not null default true
);

create table if not exists public.training_coaches (
  user_id uuid primary key references auth.users(id) on delete cascade, display_name text not null,
  specialty text, is_active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.training_programs (
  id bigint generated always as identity primary key, title text not null, coach_id uuid references public.training_coaches(user_id) on delete set null,
  coach_name text, price_iqd integer not null default 0, billing_period text, sessions_count integer,
  is_active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.training_booking_requests (
  id uuid primary key default gen_random_uuid(), trainee_id uuid references auth.users(id) on delete set null,
  trainee_name text not null, trainee_phone text not null, program_id bigint references public.training_programs(id) on delete set null,
  program_title text, training_date date, training_time time, status text not null default 'pending', created_at timestamptz not null default now()
);
create table if not exists public.training_subscriptions (
  id uuid primary key default gen_random_uuid(), trainee_id uuid references auth.users(id) on delete set null,
  program_id bigint references public.training_programs(id) on delete set null, coach_id uuid references public.training_coaches(user_id) on delete set null,
  status text not null default 'pending', payment_status text not null default 'pending', starts_at timestamptz, ends_at timestamptz,
  updated_at timestamptz not null default now(), created_at timestamptz not null default now()
);
create table if not exists public.nutrition_plan_orders (
  id uuid primary key default gen_random_uuid(), customer_id uuid references auth.users(id) on delete set null,
  customer_name text, customer_phone text, plan_name text not null, meals_count integer, total_iqd bigint not null default 0,
  status text not null default 'new', payment_status text not null default 'pending', created_at timestamptz not null default now()
);

create table if not exists public.football_clips (
  id uuid primary key default gen_random_uuid(), owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null, video_path text not null, duration_seconds numeric(5,2) not null,
  status text not null default 'published', created_at timestamptz not null default now()
);
create table if not exists public.football_clip_ratings (
  clip_id uuid not null references public.football_clips(id) on delete cascade,
  voter_id uuid not null references auth.users(id) on delete cascade, rating smallint not null check(rating between 1 and 5),
  created_at timestamptz not null default now(), primary key(clip_id,voter_id)
);
create table if not exists public.sports_catalog (
  code text primary key, name_ar text not null, is_active boolean not null default true
);
create table if not exists public.advertisements (
  id uuid primary key default gen_random_uuid(), title text not null, category text, target_url text,
  is_published boolean not null default false, sort_order integer not null default 0, created_at timestamptz not null default now()
);
create table if not exists public.player_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade, display_name text not null default 'لاعب',
  position text not null default 'غير محدد', area text not null default 'نينوى', avatar_url text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.match_participants (
  booking_id bigint not null references public.stadium_bookings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, team text not null default 'home', joined_at timestamptz not null default now(),
  primary key(booking_id,user_id)
);
create table if not exists public.player_ratings (
  id bigint generated always as identity primary key, booking_id bigint not null references public.stadium_bookings(id) on delete cascade,
  rater_id uuid not null references auth.users(id) on delete cascade, rated_user_id uuid not null references auth.users(id) on delete cascade,
  performance smallint not null default 5, teamwork smallint not null default 5, sportsmanship smallint not null default 5,
  comment text, created_at timestamptz not null default now()
);
create table if not exists public.match_join_attempts (
  id bigint generated always as identity primary key, user_id uuid references auth.users(id) on delete set null,
  attempted_at timestamptz not null default now(), succeeded boolean not null default false
);
create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(), recipient_id uuid references auth.users(id) on delete cascade,
  title text not null, message text not null, is_read boolean not null default false, created_at timestamptz not null default now()
);
create table if not exists public.app_campaigns (
  id uuid primary key default gen_random_uuid(), title text not null, message text not null, audience text not null default 'all',
  recipient_count integer not null default 0, created_at timestamptz not null default now()
);
create table if not exists public.app_push_deliveries (
  id uuid primary key default gen_random_uuid(), campaign_id uuid references public.app_campaigns(id) on delete cascade,
  state text not null default 'queued', lease_until timestamptz, response_code integer, updated_at timestamptz not null default now()
);
create table if not exists public.app_admin_audit (
  id uuid primary key default gen_random_uuid(), actor_id uuid references auth.users(id) on delete set null,
  action text not null, target_id text, details jsonb not null default '{}', created_at timestamptz not null default now()
);
create table if not exists public.platform_stats (
  id integer primary key default 1 check(id=1), sports_count integer not null default 0,
  facilities_count integer not null default 0, bookings_count integer not null default 0,
  activities_count integer not null default 0, updated_at timestamptz not null default now()
);
insert into public.platform_stats(id) values(1) on conflict(id) do nothing;

-- Client-facing rows use RLS; the owner-only admin policies are added by the following migrations.
do $$ declare t text; begin
  foreach t in array array['partner_invite_codes','partner_profiles','partner_notifications','partner_stadiums','stadium_time_slots','stadium_bookings','stadium_booking_shares','market_products','product_orders','partner_documents','partner_settlements','partner_contracts','partner_financial_entries','partner_commission_rules','training_coaches','training_programs','training_booking_requests','training_subscriptions','nutrition_plan_orders','football_clips','football_clip_ratings','sports_catalog','advertisements','player_profiles','match_participants','player_ratings','match_join_attempts','app_notifications','app_campaigns','app_push_deliveries','app_admin_audit','platform_stats'] loop
    execute format('alter table public.%I enable row level security',t);
  end loop;
end $$;

grant select on public.partner_stadiums,public.stadium_time_slots,public.market_products,public.training_coaches,public.training_programs,public.football_clips,public.football_clip_ratings,public.player_profiles,public.sports_catalog,public.advertisements,public.platform_stats to anon,authenticated;
grant select,insert,update,delete on public.partner_stadiums,public.stadium_time_slots,public.market_products,public.partner_notifications,public.partner_profiles,public.product_orders,public.training_booking_requests,public.training_subscriptions,public.app_notifications,public.player_profiles,public.football_clips,public.football_clip_ratings,public.match_participants,public.player_ratings,public.match_join_attempts to authenticated;
grant select,insert,update,delete on public.partner_documents,public.partner_settlements,public.partner_contracts,public.partner_financial_entries,public.partner_commission_rules,public.training_coaches,public.training_programs,public.nutrition_plan_orders,public.advertisements,public.sports_catalog,public.app_campaigns,public.app_push_deliveries,public.app_admin_audit,public.platform_stats,public.stadium_booking_shares,public.stadium_bookings to authenticated;
grant usage,select on all sequences in schema public to authenticated;

create policy "public reads active stadiums" on public.partner_stadiums for select to anon,authenticated using (is_active or owner_id=(select auth.uid()));
create policy "owners manage own stadiums" on public.partner_stadiums for all to authenticated using (owner_id=(select auth.uid())) with check (owner_id=(select auth.uid()));
create policy "public reads slot availability" on public.stadium_time_slots for select to anon,authenticated using (true);
create policy "owners manage stadium slots" on public.stadium_time_slots for all to authenticated using (exists(select 1 from public.partner_stadiums s where s.id=stadium_id and s.owner_id=(select auth.uid()))) with check (exists(select 1 from public.partner_stadiums s where s.id=stadium_id and s.owner_id=(select auth.uid())));
create policy "public reads active products" on public.market_products for select to anon,authenticated using (is_active or owner_id=(select auth.uid()));
create policy "approved partners manage products" on public.market_products for all to authenticated using (owner_id=(select auth.uid()) and exists(select 1 from public.partner_profiles p where p.user_id=(select auth.uid()) and p.status='approved')) with check (owner_id=(select auth.uid()) and exists(select 1 from public.partner_profiles p where p.user_id=(select auth.uid()) and p.status='approved'));
create policy "partners read own profile" on public.partner_profiles for select to authenticated using (user_id=(select auth.uid()));
create policy "partners read own notifications" on public.partner_notifications for select to authenticated using (recipient_id=(select auth.uid()));
create policy "partners update own notification state" on public.partner_notifications for update to authenticated using (recipient_id=(select auth.uid())) with check (recipient_id=(select auth.uid()));
create policy "customers and merchants read own product orders" on public.product_orders for select to authenticated using (customer_id=(select auth.uid()) or merchant_id=(select auth.uid()));
create policy "customers create own product orders" on public.product_orders for insert to authenticated with check (customer_id=(select auth.uid()));
create policy "customers read own notifications" on public.app_notifications for select to authenticated using (recipient_id=(select auth.uid()));
create policy "players read public profiles" on public.player_profiles for select to anon,authenticated using (true);
create policy "players create own profile" on public.player_profiles for insert to authenticated with check (user_id=(select auth.uid()));
create policy "players update own profile" on public.player_profiles for update to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy "public reads published clips" on public.football_clips for select to anon,authenticated using (status='published' or owner_id=(select auth.uid()));
create policy "users publish own clips" on public.football_clips for insert to authenticated with check (owner_id=(select auth.uid()));
create policy "users rate clips once" on public.football_clip_ratings for insert to authenticated with check (voter_id=(select auth.uid()));
create policy "public reads clip ratings" on public.football_clip_ratings for select to anon,authenticated using (true);
create policy "users join games" on public.match_participants for select to authenticated using (user_id=(select auth.uid()));
create policy "users see own ratings" on public.player_ratings for select to authenticated using (rater_id=(select auth.uid()) or rated_user_id=(select auth.uid()));
create policy "users read own training requests" on public.training_booking_requests for select to authenticated using (trainee_id=(select auth.uid()));
create policy "users create training requests" on public.training_booking_requests for insert to authenticated with check (trainee_id=(select auth.uid()));
create policy "users read own subscriptions" on public.training_subscriptions for select to authenticated using (trainee_id=(select auth.uid()) or coach_id=(select auth.uid()));
create policy "users read own settlements" on public.partner_settlements for select to authenticated using (partner_id=(select auth.uid()));
create policy "users read own documents" on public.partner_documents for select to authenticated using (partner_id=(select auth.uid()));

create or replace function public.seed_nextmove_player_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.player_profiles(user_id,display_name,avatar_url)
  values(new.id,left(coalesce(nullif(new.raw_user_meta_data->>'full_name',''),nullif(new.raw_user_meta_data->>'name',''),nullif(split_part(coalesce(new.email,''),'@',1),''),nullif(new.phone,''),'لاعب'),80),new.raw_user_meta_data->>'avatar_url')
  on conflict(user_id) do nothing;
  return new;
end $$;
drop trigger if exists seed_nextmove_player_profile on auth.users;
create trigger seed_nextmove_player_profile after insert on auth.users
for each row execute function public.seed_nextmove_player_profile();
revoke all on function public.seed_nextmove_player_profile() from public,anon,authenticated;

create or replace function public.prepare_product_order()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_owner uuid; v_price integer; v_stock integer;
begin
  if (select auth.uid()) is null then raise exception 'AUTH_REQUIRED'; end if;
  select owner_id,price_iqd,stock into v_owner,v_price,v_stock
  from public.market_products where id=new.product_id and is_active for update;
  if v_owner is null or v_stock < new.quantity then raise exception 'PRODUCT_UNAVAILABLE'; end if;
  if not exists(select 1 from public.partner_profiles p where p.user_id=v_owner and p.status='approved') then raise exception 'MERCHANT_NOT_APPROVED'; end if;
  new.customer_id := (select auth.uid()); new.merchant_id := v_owner; new.unit_price_iqd := v_price;
  update public.market_products set stock=stock-new.quantity,updated_at=now() where id=new.product_id;
  return new;
end $$;
drop trigger if exists prepare_product_order_trigger on public.product_orders;
create trigger prepare_product_order_trigger before insert on public.product_orders
for each row execute function public.prepare_product_order();
revoke all on function public.prepare_product_order() from public,anon,authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('football-clips','football-clips',true,52428800,array['video/mp4','video/webm','video/quicktime'])
on conflict(id) do update set public=true,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists "authenticated users upload own football clips" on storage.objects;
create policy "authenticated users upload own football clips" on storage.objects for insert to authenticated
with check(bucket_id='football-clips' and (storage.foldername(name))[1]=(select auth.uid())::text and owner_id=(select auth.uid())::text);
drop policy if exists "users delete own football clips" on storage.objects;
create policy "users delete own football clips" on storage.objects for delete to authenticated
using(bucket_id='football-clips' and owner_id=(select auth.uid())::text);

