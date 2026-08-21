create schema if not exists private;
revoke all on schema private from public;

create table if not exists public.sports_catalog (
  code text primary key,
  name_ar text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.sports_catalog enable row level security;

drop policy if exists "public reads active sports" on public.sports_catalog;
create policy "public reads active sports"
on public.sports_catalog for select
to anon, authenticated
using (is_active = true);

grant select on public.sports_catalog to anon, authenticated;
revoke insert, update, delete on public.sports_catalog from anon, authenticated;

insert into public.sports_catalog (code, name_ar, is_active)
values
  ('football', 'كرة القدم', true),
  ('strength', 'الحديد واللياقة', true),
  ('padel', 'البادل', true)
on conflict (code) do update
set name_ar = excluded.name_ar,
    is_active = excluded.is_active,
    updated_at = now();

create table if not exists public.platform_stats (
  id smallint primary key default 1 check (id = 1),
  sports_count integer not null default 0 check (sports_count >= 0),
  facilities_count bigint not null default 0 check (facilities_count >= 0),
  bookings_count bigint not null default 0 check (bookings_count >= 0),
  activities_count bigint not null default 0 check (activities_count >= 0),
  updated_at timestamptz not null default now()
);

alter table public.platform_stats enable row level security;

drop policy if exists "public reads platform stats" on public.platform_stats;
create policy "public reads platform stats"
on public.platform_stats for select
to anon, authenticated
using (id = 1);

grant select on public.platform_stats to anon, authenticated;
revoke insert, update, delete on public.platform_stats from anon, authenticated;

create or replace function private.sync_platform_stats()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.platform_stats (
    id,
    sports_count,
    facilities_count,
    bookings_count,
    activities_count,
    updated_at
  )
  select
    1,
    (select count(*)::integer from public.sports_catalog where is_active = true),
    (select count(*) from public.partner_stadiums where is_active = true),
    (select count(*) from public.stadium_bookings where coalesce(status, '') not in ('cancelled', 'canceled', 'rejected', 'refunded')),
    (
      (select count(*) from public.product_orders where coalesce(status, '') not in ('cancelled', 'canceled', 'rejected', 'refunded')) +
      (select count(*) from public.meal_orders where coalesce(status, '') not in ('cancelled', 'canceled', 'rejected', 'refunded')) +
      (select count(*) from public.training_subscriptions where coalesce(status, '') not in ('cancelled', 'canceled', 'rejected')) +
      (select count(*) from public.training_booking_requests where coalesce(status, '') not in ('cancelled', 'canceled', 'rejected')) +
      (select count(*) from public.nutrition_plan_orders where coalesce(status, '') not in ('cancelled', 'canceled', 'rejected', 'refunded')) +
      (select count(*) from public.match_participants) +
      (select count(*) from public.player_ratings) +
      (select count(*) from public.football_clips where status = 'published')
    ),
    now()
  on conflict (id) do update
  set sports_count = excluded.sports_count,
      facilities_count = excluded.facilities_count,
      bookings_count = excluded.bookings_count,
      activities_count = excluded.activities_count,
      updated_at = excluded.updated_at;
end;
$$;

revoke all on function private.sync_platform_stats() from public, anon, authenticated;

create or replace function private.refresh_platform_stats_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.sync_platform_stats();
  return null;
end;
$$;

revoke all on function private.refresh_platform_stats_trigger() from public, anon, authenticated;

do $$
declare
  table_name text;
  tracked_tables text[] := array[
    'sports_catalog',
    'partner_stadiums',
    'stadium_bookings',
    'product_orders',
    'meal_orders',
    'training_subscriptions',
    'training_booking_requests',
    'nutrition_plan_orders',
    'match_participants',
    'player_ratings',
    'football_clips'
  ];
begin
  foreach table_name in array tracked_tables loop
    execute format('drop trigger if exists refresh_platform_stats on public.%I', table_name);
    execute format(
      'create trigger refresh_platform_stats after insert or update or delete on public.%I for each statement execute function private.refresh_platform_stats_trigger()',
      table_name
    );
  end loop;
end;
$$;

select private.sync_platform_stats();

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'platform_stats'
     ) then
    alter publication supabase_realtime add table public.platform_stats;
  end if;
end;
$$;
