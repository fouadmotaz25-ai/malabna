Warning: p was declared with const; use let for reassignable variables.
-- SwiftPayIQ partner connections and auditable hosted payment links.
-- Merchant API keys are stored in Supabase Vault; app users never receive them.

create extension if not exists supabase_vault with schema vault;
create schema if not exists private;

create table if not exists private.swiftpay_connections (
  partner_user_id uuid primary key references public.partner_profiles(user_id) on delete cascade,
  business_id text not null,
  business_name text,
  api_key_secret_id uuid not null,
  scopes text[] not null default '{}',
  connected_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists private.swiftpay_payment_intents (
  id uuid primary key default gen_random_uuid(),
  order_type text not null check (order_type in ('product','meal','stadium')),
  order_id text not null,
  customer_id uuid not null references auth.users(id) on delete cascade,
  partner_user_id uuid not null references public.partner_profiles(user_id) on delete restrict,
  business_id text not null,
  amount_iqd bigint not null check (amount_iqd > 0),
  payment_link_id text unique,
  payment_id text,
  gateway_txn_id text,
  status text not null default 'pending' check (status in ('pending','paid','failed','refunded')),
  created_at timestamptz not null default now(),
  paid_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (order_type, order_id)
);

alter table public.product_orders add column if not exists payment_status text not null default 'pending';
alter table public.product_orders add column if not exists payment_provider text;
alter table public.product_orders add column if not exists payment_reference text;
alter table public.product_orders add column if not exists paid_at timestamptz;
alter table public.meal_orders add column if not exists payment_status text not null default 'pending';
alter table public.meal_orders add column if not exists payment_provider text;
alter table public.meal_orders add column if not exists payment_reference text;
alter table public.meal_orders add column if not exists paid_at timestamptz;
alter table public.stadium_bookings add column if not exists payment_status text not null default 'pending';
alter table public.stadium_bookings add column if not exists payment_provider text;
alter table public.stadium_bookings add column if not exists deposit_payment_reference text;
alter table public.stadium_bookings add column if not exists deposit_paid_at timestamptz;

revoke all on schema private from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
grant usage on schema private to service_role;
grant all on all tables in schema private to service_role;

create or replace function public.swiftpay_store_merchant_key(
  p_partner_user_id uuid,
  p_api_key text,
  p_business_id text,
  p_business_name text default null,
  p_scopes text[] default '{}'
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_secret_id uuid;
  v_name text := 'swiftpay_merchant_' || p_partner_user_id::text;
begin
  if auth.role() <> 'service_role' then raise exception 'forbidden'; end if;
  if p_api_key is null or p_api_key !~ '^spi_(live|test)_' then raise exception 'invalid merchant key'; end if;
  if p_business_id is null or length(p_business_id) < 3 then raise exception 'invalid business id'; end if;

  select api_key_secret_id into v_secret_id
  from private.swiftpay_connections where partner_user_id = p_partner_user_id;

  if v_secret_id is null then
    v_secret_id := vault.create_secret(p_api_key, v_name, 'SwiftPayIQ merchant API key');
  else
    perform vault.update_secret(v_secret_id, p_api_key, v_name, 'SwiftPayIQ merchant API key');
  end if;

  insert into private.swiftpay_connections(partner_user_id,business_id,business_name,api_key_secret_id,scopes)
  values (p_partner_user_id,p_business_id,p_business_name,v_secret_id,coalesce(p_scopes,'{}'))
  on conflict (partner_user_id) do update set
    business_id = excluded.business_id,
    business_name = excluded.business_name,
    api_key_secret_id = excluded.api_key_secret_id,
    scopes = excluded.scopes,
    connected_at = now(),
    updated_at = now();
end;
$$;

create or replace function public.swiftpay_get_merchant_key(p_partner_user_id uuid)
returns table(api_key text, business_id text, business_name text)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() <> 'service_role' then raise exception 'forbidden'; end if;
  return query
    select ds.decrypted_secret, c.business_id, c.business_name
    from private.swiftpay_connections c
    join vault.decrypted_secrets ds on ds.id = c.api_key_secret_id
    where c.partner_user_id = p_partner_user_id;
end;
$$;

create or replace function public.swiftpay_get_connection_status(p_partner_user_id uuid)
returns table(business_name text, connected_at timestamptz, scopes text[])
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() <> 'service_role' then raise exception 'forbidden'; end if;
  return query select c.business_name,c.connected_at,c.scopes
    from private.swiftpay_connections c where c.partner_user_id=p_partner_user_id;
end;
$$;

create or replace function public.swiftpay_get_pending_payment(p_order_type text,p_order_id text)
returns table(payment_link_id text, amount_iqd bigint)
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() <> 'service_role' then raise exception 'forbidden'; end if;
  return query select p.payment_link_id,p.amount_iqd from private.swiftpay_payment_intents p
    where p.order_type=p_order_type and p.order_id=p_order_id and p.status='pending'
      and p.payment_link_id is not null;
end;
$$;

create or replace function public.swiftpay_save_payment_intent(
  p_order_type text,p_order_id text,p_customer_id uuid,p_partner_user_id uuid,
  p_business_id text,p_amount_iqd bigint,p_payment_link_id text
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.role() <> 'service_role' then raise exception 'forbidden'; end if;
  insert into private.swiftpay_payment_intents(order_type,order_id,customer_id,partner_user_id,business_id,amount_iqd,payment_link_id,status,updated_at)
  values(p_order_type,p_order_id,p_customer_id,p_partner_user_id,p_business_id,p_amount_iqd,p_payment_link_id,'pending',now())
  on conflict(order_type,order_id) do update set customer_id=excluded.customer_id,
    partner_user_id=excluded.partner_user_id,business_id=excluded.business_id,amount_iqd=excluded.amount_iqd,
    payment_link_id=excluded.payment_link_id,status='pending',payment_id=null,gateway_txn_id=null,paid_at=null,updated_at=now();
end;
$$;

create or replace function public.swiftpay_apply_payment_event(
  p_payment_link_id text,
  p_payment_id text,
  p_gateway_txn_id text,
  p_event text,
  p_amount_iqd bigint,
  p_business_id text
) returns boolean
language plpgsql security definer set search_path = '' as $$
declare v_intent private.swiftpay_payment_intents%rowtype;
begin
  if auth.role() <> 'service_role' then raise exception 'forbidden'; end if;
  select * into v_intent from private.swiftpay_payment_intents
  where payment_link_id = p_payment_link_id for update;
  if not found then return false; end if;
  if v_intent.amount_iqd <> p_amount_iqd or v_intent.business_id <> p_business_id then
    raise exception 'payment does not match intent';
  end if;

  if p_event in ('payment.succeeded','payment_link.paid','invoice.paid') then
    if v_intent.status <> 'paid' then
      update private.swiftpay_payment_intents set status='paid',payment_id=p_payment_id,
        gateway_txn_id=p_gateway_txn_id,paid_at=now(),updated_at=now() where id=v_intent.id;
      if v_intent.order_type = 'product' then
        update public.product_orders set payment_status='paid',payment_provider='SwiftPayIQ',
          payment_reference=p_payment_id,paid_at=now() where id::text=v_intent.order_id;
      elsif v_intent.order_type = 'meal' then
        update public.meal_orders set payment_status='paid',payment_provider='SwiftPayIQ',
          payment_reference=p_payment_id,paid_at=now() where id::text=v_intent.order_id;
      elsif v_intent.order_type = 'stadium' then
        update public.stadium_bookings set
          payment_status=case when coalesce(deposit_paid_iqd,0)+p_amount_iqd >= coalesce(nullif(deposit_required_iqd,0),total_iqd) then 'paid' else 'pending' end,
          payment_provider='SwiftPayIQ',deposit_paid_iqd=coalesce(deposit_paid_iqd,0)+p_amount_iqd,
          deposit_payment_reference=p_payment_id,deposit_paid_at=now() where id::text=v_intent.order_id;
      end if;
    end if;
  elsif p_event = 'payment.failed' and v_intent.status = 'pending' then
    update private.swiftpay_payment_intents set status='failed',payment_id=p_payment_id,
      gateway_txn_id=p_gateway_txn_id,updated_at=now() where id=v_intent.id;
    if v_intent.order_type = 'product' then
      update public.product_orders set payment_status='failed',payment_provider='SwiftPayIQ',payment_reference=p_payment_id where id::text=v_intent.order_id;
    elsif v_intent.order_type = 'meal' then
      update public.meal_orders set payment_status='failed',payment_provider='SwiftPayIQ',payment_reference=p_payment_id where id::text=v_intent.order_id;
    end if;
  elsif p_event = 'payment.refunded' then
    update private.swiftpay_payment_intents set status='refunded',payment_id=p_payment_id,
      gateway_txn_id=p_gateway_txn_id,updated_at=now() where id=v_intent.id;
    if v_intent.order_type = 'product' then
      update public.product_orders set payment_status='refunded',payment_provider='SwiftPayIQ',payment_reference=p_payment_id where id::text=v_intent.order_id;
    elsif v_intent.order_type = 'meal' then
      update public.meal_orders set payment_status='refunded',payment_provider='SwiftPayIQ',payment_reference=p_payment_id where id::text=v_intent.order_id;
    end if;
  end if;
  return true;
end;
$$;

revoke all on function public.swiftpay_store_merchant_key(uuid,text,text,text,text[]) from public, anon, authenticated;
revoke all on function public.swiftpay_get_merchant_key(uuid) from public, anon, authenticated;
revoke all on function public.swiftpay_get_connection_status(uuid) from public, anon, authenticated;
revoke all on function public.swiftpay_get_pending_payment(text,text) from public, anon, authenticated;
revoke all on function public.swiftpay_save_payment_intent(text,text,uuid,uuid,text,bigint,text) from public, anon, authenticated;
revoke all on function public.swiftpay_apply_payment_event(text,text,text,text,bigint,text) from public, anon, authenticated;
grant execute on function public.swiftpay_store_merchant_key(uuid,text,text,text,text[]) to service_role;
grant execute on function public.swiftpay_get_merchant_key(uuid) to service_role;
grant execute on function public.swiftpay_get_connection_status(uuid) to service_role;
grant execute on function public.swiftpay_get_pending_payment(text,text) to service_role;
grant execute on function public.swiftpay_save_payment_intent(text,text,uuid,uuid,text,bigint,text) to service_role;
grant execute on function public.swiftpay_apply_payment_event(text,text,text,text,bigint,text) to service_role;
