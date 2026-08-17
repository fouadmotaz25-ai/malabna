alter table public.partner_profiles
  drop constraint if exists partner_profiles_partner_role_check;
alter table public.partner_profiles
  add constraint partner_profiles_partner_role_check
  check (partner_role = any (array['merchant'::text, 'stadium_owner'::text, 'restaurant'::text]));

alter table public.market_products
  drop constraint if exists market_products_category_check;
alter table public.market_products
  add constraint market_products_category_check
  check (category = any (array[
    'shoes'::text, 'kits'::text, 'balls'::text, 'equipment'::text, 'accessories'::text,
    'clothing'::text, 'devices'::text, 'supplements'::text
  ]));
alter table public.market_products
  add column if not exists specifications text not null default '';

alter table public.partner_notifications
  drop constraint if exists partner_notifications_kind_check;
alter table public.partner_notifications
  add constraint partner_notifications_kind_check
  check (kind = any (array['stadium_booking'::text, 'product_order'::text, 'meal_order'::text]));

create table if not exists public.restaurant_meals (
  id bigint generated always as identity primary key,
  owner_id uuid not null references public.partner_profiles(user_id) on delete cascade,
  title text not null check (char_length(title) between 2 and 140),
  description text not null default '',
  ingredients text not null check (char_length(ingredients) between 2 and 1200),
  category text not null check (category = any (array['protein'::text, 'diet'::text, 'energy'::text, 'regular'::text, 'drinks'::text])),
  price_iqd integer not null check (price_iqd > 0),
  stock integer not null default 0 check (stock >= 0),
  calories integer check (calories is null or calories between 0 and 10000),
  protein_grams integer check (protein_grams is null or protein_grams between 0 and 1000),
  prep_minutes integer not null default 30 check (prep_minutes between 1 and 1440),
  delivery_available boolean not null default true,
  image_url text,
  image_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.restaurant_meals enable row level security;

create table if not exists public.meal_orders (
  id bigint generated always as identity primary key,
  meal_id bigint not null references public.restaurant_meals(id),
  customer_id uuid not null references auth.users(id),
  restaurant_id uuid not null references auth.users(id),
  quantity integer not null default 1 check (quantity between 1 and 20),
  unit_price_iqd integer not null check (unit_price_iqd > 0),
  total_iqd integer generated always as (quantity * unit_price_iqd) stored,
  status text not null default 'new' check (status = any (array['new'::text, 'confirmed'::text, 'preparing'::text, 'delivering'::text, 'completed'::text, 'cancelled'::text])),
  created_at timestamptz not null default now()
);
alter table public.meal_orders enable row level security;

drop policy if exists "public reads active restaurant meals" on public.restaurant_meals;
create policy "public reads active restaurant meals"
on public.restaurant_meals for select
to anon, authenticated
using (is_active = true or (select auth.uid()) = owner_id);

drop policy if exists "approved restaurants create meals" on public.restaurant_meals;
create policy "approved restaurants create meals"
on public.restaurant_meals for insert
to authenticated
with check (
  (select auth.uid()) = owner_id
  and exists (
    select 1 from public.partner_profiles p
    where p.user_id = (select auth.uid())
      and p.partner_role = 'restaurant'
      and p.status = 'approved'
  )
);

drop policy if exists "restaurants update own meals" on public.restaurant_meals;
create policy "restaurants update own meals"
on public.restaurant_meals for update
to authenticated
using ((select auth.uid()) = owner_id)
with check (
  (select auth.uid()) = owner_id
  and exists (
    select 1 from public.partner_profiles p
    where p.user_id = (select auth.uid())
      and p.partner_role = 'restaurant'
      and p.status = 'approved'
  )
);

drop policy if exists "restaurants delete own meals" on public.restaurant_meals;
create policy "restaurants delete own meals"
on public.restaurant_meals for delete
to authenticated
using ((select auth.uid()) = owner_id);

drop policy if exists "customers and restaurants read meal orders" on public.meal_orders;
create policy "customers and restaurants read meal orders"
on public.meal_orders for select
to authenticated
using ((select auth.uid()) = customer_id or (select auth.uid()) = restaurant_id);

drop policy if exists "customers create own meal orders" on public.meal_orders;
create policy "customers create own meal orders"
on public.meal_orders for insert
to authenticated
with check (
  (select auth.uid()) = customer_id
  and exists (
    select 1 from public.restaurant_meals m
    where m.id = meal_orders.meal_id
      and m.owner_id = meal_orders.restaurant_id
      and m.is_active = true
      and m.price_iqd = meal_orders.unit_price_iqd
      and m.stock >= meal_orders.quantity
  )
);

create or replace function public.prepare_meal_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  meal_owner uuid;
  meal_price integer;
  meal_stock integer;
begin
  if (select auth.uid()) is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select owner_id, price_iqd, stock
  into meal_owner, meal_price, meal_stock
  from public.restaurant_meals
  where id = new.meal_id and is_active = true
  for update;

  if meal_owner is null or meal_stock < new.quantity then
    raise exception 'MEAL_UNAVAILABLE';
  end if;

  new.customer_id := (select auth.uid());
  new.restaurant_id := meal_owner;
  new.unit_price_iqd := meal_price;

  update public.restaurant_meals
  set stock = stock - new.quantity, updated_at = now()
  where id = new.meal_id;

  return new;
end;
$function$;

drop trigger if exists prepare_meal_order_trigger on public.meal_orders;
create trigger prepare_meal_order_trigger
before insert on public.meal_orders
for each row execute function public.prepare_meal_order();

create or replace function public.notify_restaurant_on_order()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  meal_label text;
begin
  select title into meal_label from public.restaurant_meals where id = new.meal_id;
  insert into public.partner_notifications(recipient_id, kind, title, message, reference_id)
  values (
    new.restaurant_id,
    'meal_order',
    'طلب وجبة جديد',
    'طلب جديد: ' || meal_label || ' × ' || new.quantity::text || ' — ' || new.total_iqd::text || ' د.ع',
    new.id
  );
  return new;
end;
$function$;

drop trigger if exists meal_order_partner_notification on public.meal_orders;
create trigger meal_order_partner_notification
after insert on public.meal_orders
for each row execute function public.notify_restaurant_on_order();

revoke all on function public.prepare_meal_order() from public, anon, authenticated;
revoke all on function public.notify_restaurant_on_order() from public, anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('restaurant-meals', 'restaurant-meals', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Approved restaurants upload meal images" on storage.objects;
create policy "Approved restaurants upload meal images"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'restaurant-meals'
  and (storage.foldername(name))[1] = (select auth.uid())::text
  and storage.extension(name) = any (array['jpg'::text,'jpeg'::text,'png'::text,'webp'::text])
  and exists (
    select 1 from public.partner_profiles p
    where p.user_id = (select auth.uid())
      and p.partner_role = 'restaurant'
      and p.status = 'approved'
  )
);

drop policy if exists "Restaurants update own meal images" on storage.objects;
create policy "Restaurants update own meal images"
on storage.objects for update
to authenticated
using (bucket_id = 'restaurant-meals' and owner_id = (select auth.uid())::text)
with check (bucket_id = 'restaurant-meals' and owner_id = (select auth.uid())::text);

drop policy if exists "Restaurants delete own meal images" on storage.objects;
create policy "Restaurants delete own meal images"
on storage.objects for delete
to authenticated
using (bucket_id = 'restaurant-meals' and owner_id = (select auth.uid())::text);

grant select on public.restaurant_meals to anon, authenticated;
grant insert, update, delete on public.restaurant_meals to authenticated;
grant select, insert on public.meal_orders to authenticated;
grant usage, select on sequence public.restaurant_meals_id_seq to authenticated;
grant usage, select on sequence public.meal_orders_id_seq to authenticated;

create or replace function public.redeem_partner_code_internal(
  p_user_id uuid,
  p_code text,
  p_business_name text,
  p_partner_role text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_invite public.partner_invite_codes%rowtype;
begin
  if p_user_id is null or not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_partner_role not in ('merchant','stadium_owner','restaurant') then
    raise exception 'INVALID_ROLE';
  end if;
  if char_length(trim(p_business_name)) < 2 then
    raise exception 'INVALID_BUSINESS_NAME';
  end if;
  if exists (select 1 from public.partner_profiles where user_id = p_user_id) then
    raise exception 'ALREADY_PARTNER';
  end if;

  select * into v_invite
  from public.partner_invite_codes
  where code_hash = encode(extensions.digest(convert_to(upper(trim(p_code)), 'UTF8'), 'sha256'), 'hex')
    and used_by is null
    and (expires_at is null or expires_at > now())
  for update;

  if v_invite.id is null
    or not (
      v_invite.partner_role = p_partner_role
      or (p_partner_role = 'restaurant' and v_invite.partner_role = 'merchant')
    )
  then
    raise exception 'INVALID_OR_USED_CODE';
  end if;

  insert into public.partner_profiles(user_id, partner_role, business_name, status, invite_code_id)
  values (p_user_id, p_partner_role, trim(p_business_name), 'approved', v_invite.id);

  update public.partner_invite_codes
  set used_by = p_user_id, used_at = now()
  where id = v_invite.id;

  return jsonb_build_object(
    'ok', true,
    'role', p_partner_role,
    'status', 'approved',
    'business_name', trim(p_business_name)
  );
end;
$function$;

revoke all on function public.redeem_partner_code_internal(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.redeem_partner_code_internal(uuid,text,text,text) to service_role;

