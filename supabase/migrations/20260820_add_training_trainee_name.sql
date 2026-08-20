alter table public.training_subscriptions
  add column if not exists trainee_name text
  check (trainee_name is null or char_length(btrim(trainee_name)) between 2 and 80);

