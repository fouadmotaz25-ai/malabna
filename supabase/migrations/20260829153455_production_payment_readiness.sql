-- Final production preparation before connecting a commercial payment provider.
-- Payment references are written only by a future trusted provider webhook.

alter table public.product_orders
  add column if not exists payment_status text not null default 'awaiting_gateway',
  add column if not exists payment_provider text,
  add column if not exists payment_reference text,
  add column if not exists paid_at timestamptz;

alter table public.meal_orders
  add column if not exists payment_status text not null default 'awaiting_gateway',
  add column if not exists payment_provider text,
  add column if not exists payment_reference text,
  add column if not exists paid_at timestamptz;

alter table public.nutrition_plan_orders
  add column if not exists payment_status text not null default 'awaiting_gateway',
  add column if not exists payment_provider text,
  add column if not exists payment_reference text,
  add column if not exists paid_at timestamptz;

alter table public.training_subscriptions
  add column if not exists total_iqd integer not null default 0,
  add column if not exists payment_status text not null default 'awaiting_gateway',
  add column if not exists payment_provider text,
  add column if not exists payment_reference text,
  add column if not exists paid_at timestamptz;

alter table public.product_orders
  drop constraint if exists product_orders_payment_status_check,
  add constraint product_orders_payment_status_check check (payment_status in ('awaiting_gateway','pending','paid','failed','refunded','cancelled'));
alter table public.meal_orders
  drop constraint if exists meal_orders_payment_status_check,
  add constraint meal_orders_payment_status_check check (payment_status in ('awaiting_gateway','pending','paid','failed','refunded','cancelled'));
alter table public.nutrition_plan_orders
  drop constraint if exists nutrition_plan_orders_payment_status_check,
  add constraint nutrition_plan_orders_payment_status_check check (payment_status in ('awaiting_gateway','pending','paid','failed','refunded','cancelled'));
alter table public.training_subscriptions
  drop constraint if exists training_subscriptions_payment_status_check,
  add constraint training_subscriptions_payment_status_check check (payment_status in ('awaiting_gateway','pending','paid','failed','refunded','cancelled')),
  drop constraint if exists training_subscriptions_total_iqd_check,
  add constraint training_subscriptions_total_iqd_check check (total_iqd >= 0);

create unique index if not exists product_orders_payment_reference_idx on public.product_orders (payment_reference) where payment_reference is not null;
create unique index if not exists meal_orders_payment_reference_idx on public.meal_orders (payment_reference) where payment_reference is not null;
create unique index if not exists nutrition_plan_orders_payment_reference_idx on public.nutrition_plan_orders (payment_reference) where payment_reference is not null;
create unique index if not exists training_subscriptions_payment_reference_idx on public.training_subscriptions (payment_reference) where payment_reference is not null;

create index if not exists coach_activation_codes_used_by_idx on private.coach_activation_codes (used_by) where used_by is not null;
create index if not exists training_messages_sender_id_idx on public.training_messages (sender_id);
create index if not exists training_programs_coach_id_idx on public.training_programs (coach_id);
create index if not exists training_subscriptions_program_id_idx on public.training_subscriptions (program_id);

drop index if exists public.stadium_bookings_one_confirmed_slot_idx;

drop policy if exists "Coaches can view their training programs" on public.training_programs;
drop policy if exists "Public can view active training programs" on public.training_programs;
create policy "Visible training programs"
on public.training_programs for select
to anon, authenticated
using (is_active = true or (select auth.uid()) = coach_id);

create or replace function private.prepare_training_subscription_payment()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_price integer;
  v_coach uuid;
begin
  select p.price_iqd, p.coach_id into v_price, v_coach
  from public.training_programs p
  where p.id = new.program_id and p.is_active = true and p.is_online = true;
  if not found then raise exception 'PROGRAM_NOT_AVAILABLE'; end if;
  new.trainee_id := (select auth.uid());
  new.coach_id := v_coach;
  new.total_iqd := v_price;
  new.payment_status := 'awaiting_gateway';
  new.payment_provider := null;
  new.payment_reference := null;
  new.paid_at := null;
  return new;
end;
$$;

drop trigger if exists prepare_training_subscription_payment_before_insert on public.training_subscriptions;
create trigger prepare_training_subscription_payment_before_insert
before insert on public.training_subscriptions
for each row execute function private.prepare_training_subscription_payment();
