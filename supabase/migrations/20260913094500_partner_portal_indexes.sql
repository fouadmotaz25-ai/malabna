create index if not exists partner_documents_partner_created_idx
  on public.partner_documents(partner_id, created_at desc);

create index if not exists partner_settlements_partner_period_idx
  on public.partner_settlements(partner_id, period_end desc);
