grant execute on function public.redeem_partner_code_internal(uuid,text,text,text) to service_role;

create or replace function public.protect_partner_controlled_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (select auth.role()) = 'authenticated'
     and current_setting('app.partner_review_transition', true) is distinct from 'on'
     and (
      old.user_id is distinct from new.user_id or
      old.partner_role is distinct from new.partner_role or
      old.invite_code_id is distinct from new.invite_code_id or
      old.status is distinct from new.status or
      old.commission_rate is distinct from new.commission_rate or
      old.settlement_cycle is distinct from new.settlement_cycle or
      old.approved_at is distinct from new.approved_at or
      old.review_notes is distinct from new.review_notes or
      old.rejection_reason is distinct from new.rejection_reason
    ) then
    raise exception 'PARTNER_CONTROLLED_FIELDS';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.submit_partner_application()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_profile public.partner_profiles%rowtype;
  v_has_front boolean;
  v_has_back boolean;
  v_has_business boolean;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into v_profile from public.partner_profiles where user_id = v_uid for update;
  if v_profile.user_id is null then raise exception 'PARTNER_NOT_FOUND'; end if;
  if v_profile.status not in ('pending','rejected') then raise exception 'INVALID_STATUS'; end if;
  if coalesce(char_length(btrim(v_profile.legal_name)),0) < 2
     or coalesce(char_length(btrim(v_profile.authorized_person)),0) < 2
     or coalesce(char_length(btrim(v_profile.phone)),0) < 8
     or coalesce(char_length(btrim(v_profile.governorate)),0) < 2
     or coalesce(char_length(btrim(v_profile.district)),0) < 2
     or coalesce(char_length(btrim(v_profile.address)),0) < 5
     or v_profile.contract_accepted_at is null
     or v_profile.contract_version is distinct from 'NM-PARTNER-1.0' then
    raise exception 'PROFILE_INCOMPLETE';
  end if;

  select
    bool_or(document_type='national_id_front' and status <> 'rejected'),
    bool_or(document_type='national_id_back' and status <> 'rejected'),
    bool_or(document_type in ('business_license','venue_proof') and status <> 'rejected')
  into v_has_front,v_has_back,v_has_business
  from public.partner_documents where partner_id=v_uid;
  if not coalesce(v_has_front,false) or not coalesce(v_has_back,false) or not coalesce(v_has_business,false) then
    raise exception 'DOCUMENTS_INCOMPLETE';
  end if;

  perform set_config('app.partner_review_transition','on',true);
  update public.partner_profiles
  set status='under_review', documents_submitted_at=now(), rejection_reason=null
  where user_id=v_uid;
  return jsonb_build_object('ok',true,'status','under_review','submitted_at',now());
end;
$$;

revoke execute on function public.submit_partner_application() from public, anon;
grant execute on function public.submit_partner_application() to authenticated, service_role;
