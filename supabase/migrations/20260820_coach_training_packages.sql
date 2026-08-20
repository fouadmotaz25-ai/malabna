alter table public.training_programs
  add column if not exists description text not null default '',
  add column if not exists sessions_count integer not null default 4,
  add column if not exists max_trainees integer not null default 30;

alter table public.training_programs
  drop constraint if exists training_programs_description_check,
  drop constraint if exists training_programs_sessions_count_check,
  drop constraint if exists training_programs_max_trainees_check;

alter table public.training_programs
  add constraint training_programs_description_check check (char_length(description) <= 1000),
  add constraint training_programs_sessions_count_check check (sessions_count between 1 and 60),
  add constraint training_programs_max_trainees_check check (max_trainees between 1 and 1000);

drop policy if exists "Coaches can view their training programs" on public.training_programs;
create policy "Coaches can view their training programs"
  on public.training_programs for select
  to authenticated
  using ((select auth.uid()) = coach_id);

drop policy if exists "Coaches can create their training programs" on public.training_programs;
create policy "Coaches can create their training programs"
  on public.training_programs for insert
  to authenticated
  with check (
    (select auth.uid()) = coach_id
    and exists (
      select 1 from public.training_coaches c
      where c.user_id = (select auth.uid()) and c.is_active = true
    )
  );

drop policy if exists "Coaches can update their training programs" on public.training_programs;
create policy "Coaches can update their training programs"
  on public.training_programs for update
  to authenticated
  using ((select auth.uid()) = coach_id)
  with check (
    (select auth.uid()) = coach_id
    and exists (
      select 1 from public.training_coaches c
      where c.user_id = (select auth.uid()) and c.is_active = true
    )
  );

grant select, insert, update on public.training_programs to authenticated;
grant usage, select on sequence public.training_programs_id_seq to authenticated;
