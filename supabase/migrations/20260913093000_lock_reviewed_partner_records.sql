create or replace function public.protect_partner_controlled_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if (select auth.role()) = 'authenticated'
     and current_setting('app.partner_review_transition', true) is distinct from 'on' then
    if old.user_id is distinct from new.user_id or
       old.partner_role is distinct from new.partner_role or
       old.invite_code_id is distinct from new.invite_code_id or
       old.status is distinct from new.status or
       old.commission_rate is distinct from new.commission_rate or
       old.settlement_cycle is distinct from new.settlement_cycle or
       old.approved_at is distinct from new.approved_at or
       old.review_notes is distinct from new.review_notes or
       old.rejection_reason is distinct from new.rejection_reason then
      raise exception 'PARTNER_CONTROLLED_FIELDS';
    end if;
    if old.status in ('under_review','approved','suspended') and (
       old.business_name is distinct from new.business_name or
       old.legal_name is distinct from new.legal_name or
       old.authorized_person is distinct from new.authorized_person or
       old.phone is distinct from new.phone or
       old.governorate is distinct from new.governorate or
       old.district is distinct from new.district or
       old.address is distinct from new.address or
       old.registration_number is distinct from new.registration_number or
       old.tax_number is distinct from new.tax_number or
       old.contract_version is distinct from new.contract_version or
       old.contract_accepted_at is distinct from new.contract_accepted_at
    ) then
      raise exception 'REVIEWED_PROFILE_LOCKED';
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop policy if exists "partners upload own verification documents" on public.partner_documents;
create policy "partners upload own verification documents"
on public.partner_documents for insert to authenticated
with check (
  (select auth.uid()) = partner_id and
  exists (
    select 1 from public.partner_profiles p
    where p.user_id = (select auth.uid()) and p.status in ('pending','rejected')
  )
);

drop policy if exists "partners delete pending verification documents" on public.partner_documents;
create policy "partners delete pending verification documents"
on public.partner_documents for delete to authenticated
using (
  (select auth.uid()) = partner_id and status in ('pending','rejected') and
  exists (
    select 1 from public.partner_profiles p
    where p.user_id = (select auth.uid()) and p.status in ('pending','rejected')
  )
);

drop policy if exists "partners upload own official documents" on storage.objects;
create policy "partners upload own official documents"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'partner-documents' and
  (storage.foldername(name))[1] = (select auth.uid())::text and
  owner_id = (select auth.uid())::text and
  storage.extension(name) = any(array['jpg','jpeg','png','webp','pdf']) and
  exists (
    select 1 from public.partner_profiles p
    where p.user_id = (select auth.uid()) and p.status in ('pending','rejected')
  )
);

alter table public.partner_settlements
  add constraint partner_settlements_nonnegative_net
  check (gross_iqd >= platform_commission_iqd + gateway_fees_iqd);
