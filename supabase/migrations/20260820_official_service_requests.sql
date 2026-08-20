create table if not exists public.training_booking_requests (
  id bigint generated always as identity primary key,
  trainee_id uuid not null references auth.users(id) on delete cascade,
  program_title text not null check (
    program_title = any (array[
      'أكاديمية تطوير المهارات'::text,
      'تدريب فردي للمحترفين'::text,
      'أساسيات وتكتيك البادل'::text
    ])
  ),
  trainee_name text not null check (char_length(btrim(trainee_name)) between 2 and 80),
  trainee_phone text not null check (trainee_phone ~ '^\+?[0-9]{8,15}$'),
  training_date date not null,
  training_time time without time zone not null,
  notes text not null default '' check (char_length(notes) <= 500),
  status text not null default 'pending' check (
    status = any (array['pending'::text, 'confirmed'::text, 'completed'::text, 'cancelled'::text])
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.validate_training_booking_request()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if new.training_date < current_date then
    raise exception 'PAST_TRAINING_DATE';
  end if;
  new.trainee_id := (select auth.uid());
  new.status := 'pending';
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists validate_training_booking_request_before_insert on public.training_booking_requests;
create trigger validate_training_booking_request_before_insert
before insert on public.training_booking_requests
for each row execute function public.validate_training_booking_request();

revoke all on function public.validate_training_booking_request() from public, anon, authenticated;

alter table public.training_booking_requests enable row level security;

drop policy if exists "Trainees create own training booking requests" on public.training_booking_requests;
create policy "Trainees create own training booking requests"
  on public.training_booking_requests for insert
  to authenticated
  with check ((select auth.uid()) = trainee_id and status = 'pending');

drop policy if exists "Trainees read own training booking requests" on public.training_booking_requests;
create policy "Trainees read own training booking requests"
  on public.training_booking_requests for select
  to authenticated
  using ((select auth.uid()) = trainee_id);

create index if not exists training_booking_requests_trainee_created_idx
  on public.training_booking_requests (trainee_id, created_at desc);
create index if not exists training_booking_requests_status_date_idx
  on public.training_booking_requests (status, training_date, training_time);

revoke all on public.training_booking_requests from anon;
grant select, insert on public.training_booking_requests to authenticated;
grant usage, select on sequence public.training_booking_requests_id_seq to authenticated;

create table if not exists public.nutrition_plan_orders (
  id bigint generated always as identity primary key,
  customer_id uuid not null references auth.users(id) on delete cascade,
  plan_code text not null check (plan_code = any (array['weekly_6'::text, 'monthly_30'::text, 'monthly_60'::text])),
  plan_name text generated always as (
    case plan_code
      when 'weekly_6' then 'اشتراك أسبوعي — 6 وجبات'
      when 'monthly_30' then 'اشتراك شهري — 30 وجبة'
      when 'monthly_60' then 'اشتراك شهري — 60 وجبة'
    end
  ) stored,
  meals_count integer generated always as (
    case plan_code when 'weekly_6' then 6 when 'monthly_30' then 30 when 'monthly_60' then 60 end
  ) stored,
  total_iqd integer generated always as (
    case plan_code when 'weekly_6' then 54000 when 'monthly_30' then 240000 when 'monthly_60' then 450000 end
  ) stored,
  customer_name text not null check (char_length(btrim(customer_name)) between 2 and 80),
  customer_phone text not null check (customer_phone ~ '^\+?[0-9]{8,15}$'),
  nutrition_goal text not null check (
    nutrition_goal = any (array['لياقة عامة'::text, 'بناء العضلات'::text, 'خسارة الوزن'::text, 'المحافظة على الوزن'::text])
  ),
  preferred_delivery_time text not null check (
    preferred_delivery_time = any (array['الغداء'::text, 'بعد التمرين'::text, 'العشاء'::text])
  ),
  status text not null default 'pending' check (
    status = any (array['pending'::text, 'confirmed'::text, 'active'::text, 'completed'::text, 'cancelled'::text])
  ),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.prepare_nutrition_plan_order()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  new.customer_id := (select auth.uid());
  new.status := 'pending';
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists prepare_nutrition_plan_order_before_insert on public.nutrition_plan_orders;
create trigger prepare_nutrition_plan_order_before_insert
before insert on public.nutrition_plan_orders
for each row execute function public.prepare_nutrition_plan_order();

revoke all on function public.prepare_nutrition_plan_order() from public, anon, authenticated;

alter table public.nutrition_plan_orders enable row level security;

drop policy if exists "Customers create own nutrition plan orders" on public.nutrition_plan_orders;
create policy "Customers create own nutrition plan orders"
  on public.nutrition_plan_orders for insert
  to authenticated
  with check ((select auth.uid()) = customer_id and status = 'pending');

drop policy if exists "Customers read own nutrition plan orders" on public.nutrition_plan_orders;
create policy "Customers read own nutrition plan orders"
  on public.nutrition_plan_orders for select
  to authenticated
  using ((select auth.uid()) = customer_id);

create index if not exists nutrition_plan_orders_customer_created_idx
  on public.nutrition_plan_orders (customer_id, created_at desc);
create index if not exists nutrition_plan_orders_status_created_idx
  on public.nutrition_plan_orders (status, created_at desc);

revoke all on public.nutrition_plan_orders from anon;
grant select, insert on public.nutrition_plan_orders to authenticated;
grant usage, select on sequence public.nutrition_plan_orders_id_seq to authenticated;
