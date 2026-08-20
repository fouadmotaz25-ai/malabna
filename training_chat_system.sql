-- Secure online-training subscriptions and coach/trainee chat.
-- Messages and private images are only available while a subscription is active.

create table if not exists public.training_coaches (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 80),
  specialty text not null default 'تدريب أونلاين' check (char_length(specialty) between 2 and 120),
  avatar_url text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.training_programs (
  id bigint generated always as identity primary key,
  slug text not null unique check (slug ~ '^[a-z0-9-]{3,80}$'),
  title text not null check (char_length(title) between 3 and 140),
  coach_name text not null check (char_length(coach_name) between 2 and 80),
  coach_id uuid references public.training_coaches(user_id) on delete set null,
  price_iqd integer not null check (price_iqd > 0),
  billing_period text not null default 'month' check (billing_period in ('session', 'week', 'month')),
  is_online boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.training_subscriptions (
  id uuid primary key default gen_random_uuid(),
  trainee_id uuid not null references auth.users(id) on delete cascade,
  program_id bigint not null references public.training_programs(id) on delete restrict,
  coach_id uuid references public.training_coaches(user_id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'active', 'paused', 'expired', 'cancelled')),
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status <> 'active' or (coach_id is not null and starts_at is not null and ends_at is not null and ends_at > starts_at))
);

create unique index if not exists training_subscription_open_request_idx
  on public.training_subscriptions (trainee_id, program_id)
  where status in ('pending', 'active', 'paused');

create index if not exists training_subscriptions_trainee_idx
  on public.training_subscriptions (trainee_id, status, created_at desc);

create index if not exists training_subscriptions_coach_idx
  on public.training_subscriptions (coach_id, status, created_at desc)
  where coach_id is not null;

create table if not exists public.training_messages (
  id bigint generated always as identity primary key,
  subscription_id uuid not null references public.training_subscriptions(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text,
  image_path text,
  message_type text not null default 'text' check (message_type in ('text', 'image', 'mixed')),
  created_at timestamptz not null default now(),
  check (body is null or char_length(btrim(body)) between 1 and 2000),
  check (image_path is null or char_length(image_path) between 10 and 500),
  check (body is not null or image_path is not null)
);

create index if not exists training_messages_subscription_time_idx
  on public.training_messages (subscription_id, created_at, id);

alter table public.training_coaches enable row level security;
alter table public.training_programs enable row level security;
alter table public.training_subscriptions enable row level security;
alter table public.training_messages enable row level security;

create policy "Public can view active training coaches"
  on public.training_coaches for select
  to anon, authenticated
  using (is_active = true);

create policy "Public can view active training programs"
  on public.training_programs for select
  to anon, authenticated
  using (is_active = true);

create policy "Participants can view their subscriptions"
  on public.training_subscriptions for select
  to authenticated
  using ((select auth.uid()) = trainee_id or (select auth.uid()) = coach_id);

create policy "Trainees can request a subscription"
  on public.training_subscriptions for insert
  to authenticated
  with check (
    (select auth.uid()) = trainee_id
    and status = 'pending'
    and starts_at is null
    and ends_at is null
    and coach_id is not distinct from (
      select p.coach_id
      from public.training_programs p
      where p.id = program_id and p.is_active = true and p.is_online = true
    )
  );

create policy "Active participants can read training messages"
  on public.training_messages for select
  to authenticated
  using (
    exists (
      select 1
      from public.training_subscriptions s
      where s.id = subscription_id
        and s.status = 'active'
        and s.starts_at <= now()
        and s.ends_at > now()
        and ((select auth.uid()) = s.trainee_id or (select auth.uid()) = s.coach_id)
    )
  );

create policy "Active participants can send training messages"
  on public.training_messages for insert
  to authenticated
  with check (
    (select auth.uid()) = sender_id
    and exists (
      select 1
      from public.training_subscriptions s
      where s.id = subscription_id
        and s.status = 'active'
        and s.starts_at <= now()
        and s.ends_at > now()
        and ((select auth.uid()) = s.trainee_id or (select auth.uid()) = s.coach_id)
    )
  );

grant select on public.training_coaches, public.training_programs to anon, authenticated;
grant select, insert on public.training_subscriptions, public.training_messages to authenticated;
grant usage, select on sequence public.training_programs_id_seq to authenticated;
grant usage, select on sequence public.training_messages_id_seq to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'training-chat',
  'training-chat',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create policy "Training participants can read chat images"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'training-chat'
    and exists (
      select 1
      from public.training_subscriptions s
      where s.id::text = (storage.foldername(name))[1]
        and s.status = 'active'
        and s.starts_at <= now()
        and s.ends_at > now()
        and ((select auth.uid()) = s.trainee_id or (select auth.uid()) = s.coach_id)
    )
  );

create policy "Training participants can upload chat images"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'training-chat'
    and (storage.foldername(name))[2] = (select auth.uid())::text
    and owner_id = (select auth.uid())::text
    and exists (
      select 1
      from public.training_subscriptions s
      where s.id::text = (storage.foldername(name))[1]
        and s.status = 'active'
        and s.starts_at <= now()
        and s.ends_at > now()
        and ((select auth.uid()) = s.trainee_id or (select auth.uid()) = s.coach_id)
    )
  );

insert into public.training_programs (slug, title, coach_name, price_iqd, billing_period, is_online, is_active)
values
  ('muscle-strength-online', 'بناء العضلات والقوة', 'الكابتن محمد جاسم', 60000, 'month', true, true),
  ('fat-loss-online', 'خسارة الدهون واللياقة', 'الكابتن زهراء علي', 50000, 'month', true, true),
  ('mobility-recovery-online', 'الحركة والاستشفاء', 'الكابتن أحمد قيس', 20000, 'session', true, true)
on conflict (slug) do update
set title = excluded.title,
    coach_name = excluded.coach_name,
    price_iqd = excluded.price_iqd,
    billing_period = excluded.billing_period,
    is_online = excluded.is_online,
    is_active = excluded.is_active,
    updated_at = now();

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'training_messages'
  ) then
    alter publication supabase_realtime add table public.training_messages;
  end if;
end
$$;
