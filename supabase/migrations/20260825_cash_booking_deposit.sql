alter table public.stadium_bookings
  add column if not exists deposit_required_iqd integer not null default 0,
  add column if not exists deposit_paid_iqd integer not null default 0,
  add column if not exists deposit_payment_reference text,
  add column if not exists deposit_paid_at timestamptz;

alter table public.stadium_bookings
  alter column payment_status set default 'deposit_pending',
  drop constraint if exists stadium_bookings_payment_status_check,
  drop constraint if exists stadium_bookings_deposit_amounts_check;

alter table public.stadium_bookings
  add constraint stadium_bookings_payment_status_check check (
    payment_status = any (array[
      'deposit_pending'::text,
      'deposit_paid'::text,
      'cash_due'::text,
      'awaiting_shares'::text,
      'paid'::text,
      'cancelled'::text
    ])
  ),
  add constraint stadium_bookings_deposit_amounts_check check (
    deposit_required_iqd >= 0
    and deposit_paid_iqd >= 0
    and deposit_paid_iqd <= total_iqd
    and deposit_required_iqd <= total_iqd
  );

create unique index if not exists stadium_bookings_deposit_reference_idx
  on public.stadium_bookings (deposit_payment_reference)
  where deposit_payment_reference is not null;

create unique index if not exists stadium_bookings_one_confirmed_slot_idx
  on public.stadium_bookings (slot_id)
  where status = 'confirmed';

create or replace function private.enforce_stadium_cash_deposit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.payment_method = 'cash' and new.status = 'confirmed' then
    if new.deposit_required_iqd <> 5000
       or new.deposit_paid_iqd < 5000
       or new.payment_status not in ('deposit_paid', 'paid')
       or new.deposit_payment_reference is null
       or char_length(btrim(new.deposit_payment_reference)) < 8
       or new.deposit_paid_at is null then
      raise exception 'CASH_DEPOSIT_REQUIRED';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists stadium_cash_deposit_guard on public.stadium_bookings;
create trigger stadium_cash_deposit_guard
before insert or update on public.stadium_bookings
for each row execute function private.enforce_stadium_cash_deposit();

create or replace function public.confirm_cash_deposit_booking_internal(
  p_user_id uuid,
  p_slot_id bigint,
  p_payment_reference text,
  p_deposit_iqd integer default 5000
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_slot_date date;
  v_slot_status text;
  v_price integer;
  v_booking_id bigint;
  v_existing public.stadium_bookings%rowtype;
  v_reference text := btrim(coalesce(p_payment_reference, ''));
begin
  if p_user_id is null or not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'INVALID_USER';
  end if;
  if p_deposit_iqd <> 5000 then raise exception 'INVALID_DEPOSIT_AMOUNT'; end if;
  if char_length(v_reference) < 8 or char_length(v_reference) > 200 then
    raise exception 'INVALID_PAYMENT_REFERENCE';
  end if;

  select * into v_existing
  from public.stadium_bookings
  where deposit_payment_reference = v_reference;

  if found then
    if v_existing.customer_id <> p_user_id or v_existing.slot_id <> p_slot_id then
      raise exception 'PAYMENT_REFERENCE_CONFLICT';
    end if;
    return jsonb_build_object(
      'booking_id', v_existing.id,
      'slot_id', v_existing.slot_id,
      'status', v_existing.status,
      'payment_method', v_existing.payment_method,
      'payment_status', v_existing.payment_status,
      'total_iqd', v_existing.total_iqd,
      'deposit_paid_iqd', v_existing.deposit_paid_iqd,
      'remaining_iqd', greatest(v_existing.total_iqd - v_existing.deposit_paid_iqd, 0)
    );
  end if;

  select ts.slot_date, ts.status, s.price_iqd::integer
    into v_slot_date, v_slot_status, v_price
  from public.stadium_time_slots ts
  join public.partner_stadiums s
    on s.id = ts.stadium_id
   and s.is_active = true
   and s.is_demo = false
  where ts.id = p_slot_id
  for update of ts;

  if not found then raise exception 'SLOT_NOT_FOUND'; end if;
  if v_slot_date < current_date then raise exception 'PAST_SLOT'; end if;
  if v_price < 5000 then raise exception 'INVALID_STADIUM_PRICE'; end if;
  if v_slot_status <> 'available' or exists (
    select 1 from public.stadium_bookings
    where slot_id = p_slot_id and status = 'confirmed'
  ) then
    raise exception 'SLOT_ALREADY_BOOKED';
  end if;

  insert into public.stadium_bookings(
    slot_id,
    customer_id,
    status,
    payment_method,
    total_iqd,
    payment_status,
    deposit_required_iqd,
    deposit_paid_iqd,
    deposit_payment_reference,
    deposit_paid_at
  ) values (
    p_slot_id,
    p_user_id,
    'confirmed',
    'cash',
    v_price,
    'deposit_paid',
    5000,
    5000,
    v_reference,
    now()
  ) returning id into v_booking_id;

  update public.stadium_time_slots
  set status = 'booked', updated_at = now()
  where id = p_slot_id;

  return jsonb_build_object(
    'booking_id', v_booking_id,
    'slot_id', p_slot_id,
    'status', 'confirmed',
    'payment_method', 'cash',
    'payment_status', 'deposit_paid',
    'total_iqd', v_price,
    'deposit_paid_iqd', 5000,
    'remaining_iqd', v_price - 5000
  );
end;
$$;

revoke all on function public.confirm_cash_deposit_booking_internal(uuid, bigint, text, integer)
  from public, anon, authenticated;
grant execute on function public.confirm_cash_deposit_booking_internal(uuid, bigint, text, integer)
  to service_role;
