alter table public.partner_profiles
  drop constraint if exists partner_profiles_partner_role_check;

alter table public.partner_profiles
  add constraint partner_profiles_partner_role_check
  check (partner_role = any (array[
    'merchant'::text,
    'stadium_owner'::text,
    'restaurant'::text,
    'gym_owner'::text
  ]));

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
as $$
declare
  v_invite public.partner_invite_codes%rowtype;
begin
  if p_user_id is null or not exists (
    select 1 from auth.users where id = p_user_id
  ) then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_partner_role not in ('merchant', 'stadium_owner', 'restaurant', 'gym_owner') then
    raise exception 'INVALID_ROLE';
  end if;

  if char_length(btrim(p_business_name)) < 2
     or char_length(btrim(p_business_name)) > 120 then
    raise exception 'INVALID_BUSINESS_NAME';
  end if;

  if exists (
    select 1 from public.partner_profiles where user_id = p_user_id
  ) then
    raise exception 'ALREADY_PARTNER';
  end if;

  select * into v_invite
  from public.partner_invite_codes
  where code_hash = encode(
    extensions.digest(convert_to(upper(btrim(p_code)), 'UTF8'), 'sha256'),
    'hex'
  )
    and used_by is null
    and (expires_at is null or expires_at > now())
  for update;

  if v_invite.id is null or not (
    v_invite.partner_role = p_partner_role
    or (p_partner_role = 'restaurant' and v_invite.partner_role = 'merchant')
    or (p_partner_role = 'gym_owner' and v_invite.partner_role = 'stadium_owner')
  ) then
    raise exception 'INVALID_OR_USED_CODE';
  end if;

  insert into public.partner_profiles(
    user_id,
    partner_role,
    business_name,
    status,
    invite_code_id
  ) values (
    p_user_id,
    p_partner_role,
    btrim(p_business_name),
    'approved',
    v_invite.id
  );

  update public.partner_invite_codes
  set used_by = p_user_id,
      used_at = now()
  where id = v_invite.id;

  return jsonb_build_object(
    'ok', true,
    'role', p_partner_role,
    'status', 'approved',
    'business_name', btrim(p_business_name)
  );
end;
$$;

revoke all on function public.redeem_partner_code_internal(uuid, text, text, text)
  from public, anon, authenticated;
grant execute on function public.redeem_partner_code_internal(uuid, text, text, text)
  to service_role;
