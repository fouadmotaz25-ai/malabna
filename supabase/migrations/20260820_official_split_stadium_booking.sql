alter table public.partner_stadiums alter column owner_id drop not null;
alter table public.partner_stadiums add column if not exists is_demo boolean not null default false;

alter table public.stadium_bookings
  add column if not exists total_iqd integer not null default 0,
  add column if not exists payment_status text not null default 'cash_due';

alter table public.stadium_bookings
  drop constraint if exists stadium_bookings_payment_method_check,
  drop constraint if exists stadium_bookings_total_iqd_check,
  drop constraint if exists stadium_bookings_payment_status_check;

alter table public.stadium_bookings
  add constraint stadium_bookings_payment_method_check check (payment_method = any (array['cash'::text, 'split'::text])),
  add constraint stadium_bookings_total_iqd_check check (total_iqd >= 0),
  add constraint stadium_bookings_payment_status_check check (payment_status = any (array['cash_due'::text, 'awaiting_shares'::text, 'paid'::text, 'cancelled'::text]));

create table if not exists public.stadium_booking_shares (
  id bigint generated always as identity primary key,
  booking_id bigint not null references public.stadium_bookings(id) on delete cascade,
  player_name text not null check (char_length(btrim(player_name)) between 2 and 80),
  player_phone text not null check (player_phone ~ '^\+?[0-9]{8,15}$'),
  amount_iqd integer not null check (amount_iqd > 0),
  payment_reference uuid not null default gen_random_uuid() unique,
  status text not null default 'pending' check (status = any (array['pending'::text, 'paid'::text, 'cancelled'::text])),
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.stadium_booking_shares enable row level security;
drop policy if exists "Booking participants read payment shares" on public.stadium_booking_shares;
create policy "Booking participants read payment shares"
  on public.stadium_booking_shares for select to authenticated
  using (exists (
    select 1 from public.stadium_bookings b
    left join public.stadium_time_slots ts on ts.id = b.slot_id
    left join public.partner_stadiums s on s.id = ts.stadium_id
    where b.id = stadium_booking_shares.booking_id
      and (b.customer_id = (select auth.uid()) or s.owner_id = (select auth.uid()))
  ));

create index if not exists stadium_booking_shares_booking_idx on public.stadium_booking_shares (booking_id, status);
create index if not exists stadium_booking_shares_reference_idx on public.stadium_booking_shares (payment_reference);
revoke all on public.stadium_booking_shares from anon;
grant select on public.stadium_booking_shares to authenticated;

drop function if exists public.book_stadium_slot_internal(uuid, bigint);
create or replace function public.book_stadium_slot_internal(
  p_user_id uuid,
  p_slot_id bigint,
  p_payment_method text,
  p_players jsonb default '[]'::jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_slot_date date;
  v_slot_status text;
  v_price integer;
  v_booking_id bigint;
  v_player jsonb;
  v_player_count integer;
  v_base_share integer;
  v_remainder integer;
  v_index integer := 0;
  v_shares jsonb := '[]'::jsonb;
  v_share_id bigint;
  v_share_amount integer;
  v_name text;
  v_phone text;
begin
  if p_user_id is null or not exists (select 1 from auth.users where id = p_user_id) then raise exception 'INVALID_USER'; end if;
  if p_payment_method not in ('cash', 'split') then raise exception 'INVALID_PAYMENT_METHOD'; end if;

  select ts.slot_date, ts.status, s.price_iqd::integer into v_slot_date, v_slot_status, v_price
  from public.stadium_time_slots ts
  join public.partner_stadiums s on s.id = ts.stadium_id and s.is_active = true
  where ts.id = p_slot_id for update of ts;

  if not found then raise exception 'SLOT_NOT_FOUND'; end if;
  if v_slot_date < current_date then raise exception 'PAST_SLOT'; end if;
  if v_price <= 0 then raise exception 'INVALID_STADIUM_PRICE'; end if;
  if v_slot_status <> 'available' or exists (select 1 from public.stadium_bookings where slot_id = p_slot_id and status = 'confirmed') then
    raise exception 'SLOT_ALREADY_BOOKED';
  end if;

  if p_payment_method = 'split' then
    if jsonb_typeof(p_players) <> 'array' then raise exception 'INVALID_PLAYERS'; end if;
    v_player_count := jsonb_array_length(p_players);
    if v_player_count < 2 or v_player_count > 22 then raise exception 'INVALID_PLAYER_COUNT'; end if;
  else
    v_player_count := 0;
  end if;

  insert into public.stadium_bookings(slot_id, customer_id, status, payment_method, total_iqd, payment_status)
  values (p_slot_id, p_user_id, 'confirmed', p_payment_method, v_price,
    case when p_payment_method = 'cash' then 'cash_due' else 'awaiting_shares' end)
  returning id into v_booking_id;

  if p_payment_method = 'split' then
    v_base_share := v_price / v_player_count;
    v_remainder := v_price - (v_base_share * v_player_count);
    for v_player in select value from jsonb_array_elements(p_players) loop
      v_index := v_index + 1;
      v_name := btrim(coalesce(v_player->>'name', ''));
      v_phone := regexp_replace(coalesce(v_player->>'phone', ''), '[^0-9+]', '', 'g');
      if char_length(v_name) not between 2 and 80 or v_phone !~ '^\+?[0-9]{8,15}$' then raise exception 'INVALID_PLAYER_DATA'; end if;
      v_share_amount := v_base_share + case when v_index = 1 then v_remainder else 0 end;
      insert into public.stadium_booking_shares(booking_id, player_name, player_phone, amount_iqd)
      values (v_booking_id, v_name, v_phone, v_share_amount) returning id into v_share_id;
      v_shares := v_shares || jsonb_build_array(jsonb_build_object('id', v_share_id, 'player_name', v_name, 'amount_iqd', v_share_amount, 'status', 'pending'));
    end loop;
  end if;

  update public.stadium_time_slots set status = 'booked', updated_at = now() where id = p_slot_id;
  return jsonb_build_object('booking_id', v_booking_id, 'slot_id', p_slot_id, 'status', 'confirmed',
    'payment_method', p_payment_method,
    'payment_status', case when p_payment_method = 'cash' then 'cash_due' else 'awaiting_shares' end,
    'total_iqd', v_price, 'shares', v_shares);
end;
$$;

revoke all on function public.book_stadium_slot_internal(uuid, bigint, text, jsonb) from public, anon, authenticated;
grant execute on function public.book_stadium_slot_internal(uuid, bigint, text, jsonb) to service_role;

with inserted as (
  insert into public.partner_stadiums(owner_id,name,area,price_iqd,pitch_size,image_url,features,rating,is_active,is_demo)
  select null,'ملعب NextMove التجريبي','بيئة اختبار نظام الحجز',50000,'خماسي',
    'https://images.unsplash.com/photo-1574629810360-7efbbe195018?auto=format&fit=crop&w=1200&q=85',
    array['تجربة الحجز الرسمي','لا يمثل منشأة تجارية']::text[],5.0,true,true
  where not exists (select 1 from public.partner_stadiums where is_demo = true)
  returning id
), demo as (
  select id from inserted union all select id from public.partner_stadiums where is_demo = true order by id limit 1
)
insert into public.stadium_time_slots(stadium_id,slot_date,start_time,status)
select demo.id,d::date,t::time,'available' from demo
cross join generate_series(current_date,current_date+13,interval '1 day') d
cross join unnest(array['10:00','11:00','12:00','13:00','14:00','15:00','16:00','17:00','18:00','19:00','20:00','21:00','22:00','23:00','00:00','01:00','02:00']::text[]) t
on conflict (stadium_id,slot_date,start_time) do nothing;
