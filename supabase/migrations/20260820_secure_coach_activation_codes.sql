create schema if not exists private;

create extension if not exists pgcrypto with schema extensions;

create table if not exists private.coach_activation_codes (
  id bigint generated always as identity primary key,
  code_hash text not null unique check (code_hash ~ '^[0-9a-f]{64}$'),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  used_at timestamptz,
  used_by uuid references auth.users(id) on delete set null,
  check ((used_at is null and used_by is null) or (used_at is not null and used_by is not null))
);

create table if not exists private.training_coach_contacts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  phone text not null unique check (phone ~ '^9647[0-9]{9}$'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists private.coach_activation_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now(),
  succeeded boolean not null default false
);

create index if not exists coach_activation_attempts_user_time_idx
  on private.coach_activation_attempts (user_id, attempted_at desc);

create index if not exists coach_activation_codes_available_idx
  on private.coach_activation_codes (code_hash)
  where is_active = true and used_at is null;

alter table private.coach_activation_codes enable row level security;
alter table private.training_coach_contacts enable row level security;
alter table private.coach_activation_attempts enable row level security;

revoke all on schema private from public, anon, authenticated;
revoke all on all tables in schema private from public, anon, authenticated;
revoke all on all sequences in schema private from public, anon, authenticated;

create or replace function public.activate_training_coach(
  p_name text,
  p_phone text,
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_name text := btrim(coalesce(p_name, ''));
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_code_hash text;
  v_code_id bigint;
  v_attempt_id bigint;
begin
  if v_user_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if exists (
    select 1 from public.training_coaches c
    where c.user_id = v_user_id and c.is_active = true
  ) then
    return jsonb_build_object('ok', true, 'already_active', true);
  end if;

  if char_length(v_name) < 2 or char_length(v_name) > 80 then
    return jsonb_build_object('ok', false, 'message', 'اكتب اسم الكابتن بصورة صحيحة');
  end if;

  if left(v_phone, 1) = '0' then
    v_phone := '964' || substring(v_phone from 2);
  elsif left(v_phone, 3) <> '964' and left(v_phone, 1) = '7' then
    v_phone := '964' || v_phone;
  end if;

  if v_phone !~ '^9647[0-9]{9}$' then
    return jsonb_build_object('ok', false, 'message', 'اكتب رقم هاتف عراقي صحيح');
  end if;

  if char_length(btrim(coalesce(p_code, ''))) > 64 then
    return jsonb_build_object('ok', false, 'message', 'كود التفعيل غير صحيح أو مستخدم');
  end if;

  if exists (
    select 1 from private.training_coach_contacts c
    where c.phone = v_phone and c.user_id <> v_user_id
  ) then
    return jsonb_build_object('ok', false, 'message', 'رقم الهاتف مرتبط بحساب كابتن آخر');
  end if;

  if (
    select count(*)
    from private.coach_activation_attempts a
    where a.user_id = v_user_id
      and a.attempted_at > now() - interval '1 hour'
  ) >= 10 then
    return jsonb_build_object('ok', false, 'message', 'محاولات كثيرة. حاول بعد ساعة');
  end if;

  insert into private.coach_activation_attempts (user_id)
  values (v_user_id)
  returning id into v_attempt_id;

  v_code_hash := encode(extensions.digest(upper(btrim(coalesce(p_code, ''))), 'sha256'), 'hex');

  update private.coach_activation_codes
  set used_at = now(), used_by = v_user_id
  where code_hash = v_code_hash
    and is_active = true
    and used_at is null
  returning id into v_code_id;

  if v_code_id is null then
    return jsonb_build_object('ok', false, 'message', 'كود التفعيل غير صحيح أو مستخدم');
  end if;

  insert into private.training_coach_contacts (user_id, phone)
  values (v_user_id, v_phone)
  on conflict (user_id) do update
  set phone = excluded.phone, updated_at = now();

  insert into public.training_coaches (user_id, display_name, specialty, is_active)
  values (v_user_id, v_name, 'تدريب أونلاين', true)
  on conflict (user_id) do update
  set display_name = excluded.display_name,
      is_active = true,
      updated_at = now();

  update private.coach_activation_attempts
  set succeeded = true
  where id = v_attempt_id;

  return jsonb_build_object('ok', true, 'already_active', false);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'message', 'تعذر تفعيل الحساب بهذه البيانات');
end;
$$;

revoke all on function public.activate_training_coach(text, text, text) from public, anon;
grant execute on function public.activate_training_coach(text, text, text) to authenticated;

insert into private.coach_activation_codes (code_hash)
values
  ('2a11363e3bac2ff3a787dd7ce8cdf9567a5492bcae09d8f468662a379265e96b'),
  ('f31b1808f57a7e5fbb8ea9df056c4dbe2bdf351feafc820000cb6660c284c9ec'),
  ('c3ca4bfceb1f155e7d33c7e93e364928ecef36041f1a5f7ff697003f01bd244e'),
  ('46cb2c29e35e302a52963a78720f55b291e11fe48751a512d0ed5626baa8cf55'),
  ('85047a3a506239bbe00391040150554b8a00a6fb09474ffaa1fd034b88360aaf'),
  ('d7423bb1ad094085e4dbe57b1ed67d3e993edd54e526fac7af3aadb6a01c52c5'),
  ('0e72d312aee1d0556d0e99fed32a2a7f05f32bf34198c6b3056440c006e50748'),
  ('f90e83537f12db7ed5cd1d6897935ff40b6f042abf8064666b49f7761cc3aeca'),
  ('9be41172780323afb8240655f81144810b1369103e379decfac40b8be7c422e2'),
  ('39323e5948a3001e9099d776cf4164d83b4948e626a2f9d72f4716b53095391c'),
  ('f1e9ff6c5b66c09e0d5d7e8fbfd0d4a88caa5d97250c95205c71f8281129862b'),
  ('3f21a5abc81552df31a55389a27e4dc99314f54182c06cc72cf1d8208fbb6082'),
  ('0017009492fad58abcb242695a590decdecb2232a35a7db759e259bf628bfabd'),
  ('f407ad573971e28eed7a08edec40729c385fa355e91f39168a769f737e23e0a9'),
  ('9935fa7a9ede73c0cafa92148cbc4e14296957ea25327029460c7357dcc7067b'),
  ('8997b291daf71328b52bb8f97d4cddb05454bc3d79bcea201e5d36ff75bb0d93'),
  ('76b5b09028040aacfa9b725f5c43434b564240c24139660345844a9c42f75a35'),
  ('f293662d7e71810ecb3326b0287933d1b3a4ffefcbb42668f4592340cc0b832a'),
  ('200daeffca189a4290b2d21aede3a062929d8749b533e367e6bfa84dade1ace6'),
  ('ed48a06e5d5195ab0aa42538c7eb62f6537d2de664625716c1507102ca27057c'),
  ('597dbd7c4975d89d6b6cd9fccff0c6650710bdd00bc9c11130d0d3b3fc75ee62'),
  ('a0ab1762fe0bc57952c16fdba7052ea317c927e3102ac28bfc00c0bec90c0b32'),
  ('6f8e23d6026b744f7e88443039483ed65513965707ea05828f610f6db40f585f'),
  ('5b83519049514073701af37db570ce8712cb32eb105eb157ff120cd35f762959'),
  ('6d12ab1b28b52778718fd8ea4be16c1c6b9cccdc20d5624e549fb354b7502e41'),
  ('c2204a650e39bb8b51158785773a9c7d0423c55e4dd86a917f55fc3b697aca90'),
  ('cd50533a5f03ff09e2e789e67052bbe6a8d2438c8d21e201f888f77151ae4264'),
  ('660acf87473ba55fcacdd8b8d76b9daf84c1c7eb95c507adc31bc5012333ee49'),
  ('6185de853a6e4af1ffb8fd3af2015a0fdbbd2536765c82fc10879bee9d623dce'),
  ('3a3c2a58921178acaed3890681cf68b6cad1061e53f66744e6ac2f77b556391b'),
  ('3c11496c97f3049b0aa37b0f77a4fb49e18c2e179c7e72080e6369f1b6d2af47'),
  ('17b67fe9c7f45fa1940c1a8ae051beb9bfc4aff8869dc94f60790c2ae867b49c'),
  ('5ae2b5f1d67defa85a5210ecad9d99af7387483cc789670731cbbf06347c0050'),
  ('2abe9253e354fe84b44a233a9c1715ba9e967fdb724725ac96122e7b284074cd'),
  ('ce31653aee5e08546306aeb2321d9bf1f15f553bfb71a0442d09afb945b41add'),
  ('d9ce0fe20bbfb331e27d9b290b2682d8fe1c2f7f3839b94577dc54bd0683152c'),
  ('388c2956b71124588733640d5f591099f1f5309e45e12a74ce154efb3be5f265'),
  ('c6c02676e107b09e6dfae4e867395a149b38c3cc231ac82b7fa08ab7702430ea'),
  ('e04d3f1a4ce5ec341dc36fa0e0e6a4de7fa4ffb5621458abbb8aefea382288d5'),
  ('ffe3b0dc62de4cdfcd12015486dffa3411f337a74ed2722292c52ed4964f69ee'),
  ('b78b6c10e66b367e4e6c111612277ce862308808dd97a9323fa49ac809a4e7ee'),
  ('a28babb1ada61d5403f710ac3153a2d1c55e677875342b7e7c6e849b1d3a0f6d'),
  ('f3c799a7495e2143f86bebfb93c8729b5fd21dd9e1bb3c7a52bb7ad131c4f932'),
  ('e95442485cc7f4c86b64863ea4c7247b5ee4b2fa479549973758960b7f26d2ec'),
  ('353c6a7f93c53809643ae4877ac52af571b187c26b687248c6e353750840f686'),
  ('1f9d541c0a31e606b08545ee0a98d2267dddb0e22437847911d85d20cfa36459'),
  ('89dfd95ce23ecbc635c0275dcadd061e13b28d4745f273ce2d7ff15222bb0205'),
  ('55b8a8631145f2fd1f667b15feebf4a2a3f84c13807643c8704ab1e39289d91b'),
  ('8bf8e8273ff143e5eb21acc9d55b54a81293936072b4ccd89e2d11aa114e8d4c'),
  ('33f958a82430d6d2b94844fd83eb667ed82a94f1a814118c951a3bc2730bf7f5'),
  ('6934e327cb65e1dde25b7d5f85550a34493249ad18a87f57e19c4ccc026485b7'),
  ('fc7de93a88ba5c928165771f1156f3ff9a197c8cfff4af1da3cdb9b201152329'),
  ('94f7970c7f9e96fdc3a7fdfbd9df60f133dd6f00b29a39958add98651a498a50'),
  ('f0188b805c7ea82d6793140b394967686f731806bb9933e9f87c42cccf3abf20'),
  ('8a8cf8088382c26fd3f5e62e54158d83f8e76ef3fd3526c20baeb76be855ca0c'),
  ('f5ece3bb039a891104ac653c736254d7fe54025504d1a9fecafecddf93aa58c6'),
  ('0ba36a2ece1e83d01bb012daec8f3291270443577cd7f5f7d28f69172ed0a676'),
  ('84bf9fbf7bbdb0fd469733020d730ea2485f05b828d137a6238a8bcd536a876b'),
  ('cc2cd1e916e75435d2a43eca9e9f9ee7e1a69759b72ad8d835cf132bf3f92745'),
  ('8c905b95c23c05cd75d0164c173e1bd48e50519e4804e82137cd42e137c12b93'),
  ('661d1678f8888e0942db734b5c0e7edd27eed51ffbcaf080c290289e8a53afe0'),
  ('45c479a2bdacd156db6103c4212a81b81b307b20a4555b21f5f3af62138fefe1'),
  ('405c8f205cdc54e98da20571cb7936b2f571f7915eb8dc273f7cf17fd5574868'),
  ('f26f43b7322a20e328a33609e2a863a0e01a646650139c9ba42bf97f5f4f9212'),
  ('0ea16bd84a172149deb9ea1662d2a732acc220fa7964394a3e592127822e22c4'),
  ('6a7e3249a937840996575d5620a15b2534ff101f9d4da6e524c1634583905fe7'),
  ('6b2182eb18ebcfa3c613a2238df831a3cf3ee06d450da94fae675a4e8fe60dec'),
  ('71d909474c5f0e56a5d98aeadcf672ee4c33f82e8ce4312e8851a98d8f6e7cc5'),
  ('b97d9f31c8ea19c8f21af2595ce093075ce5fd26771afa35f901f49fb291447f'),
  ('9df8df6b82765dce3c3647ffdd78683c5a5def8ab77a259640ba69ab13672729'),
  ('ee022765dd9ca48d64f4e59292b6a34f78d91b0f01d1f1fde9c39424a2b87cf7'),
  ('c2953fb14ad55a5683b7d58f37452f169297e3ca2567b2da5051bc611cf77784'),
  ('b08ee1f1d8712af3926562be3aa28ad967cf441b88582335c91e6881f7ca4e50'),
  ('3eb3d79db4bee498801d1cdd5621dd2dbd4ac4144cd135b3974ea9b9c62f3f09'),
  ('fd484b71292b46efbde89d870f2c08ed854e7799abd4cdbb34ce4203c43ff428'),
  ('b44be58f41eafa3bc0f65e5194ae29d109b9e6ca7939ef5b864ec7854dd81efe'),
  ('05500f9154ccc5e77c1d03c9c24661d5196451764fb8e151c1bbae0d0cb77efb'),
  ('46c1de74262dcf460c82644e38230d409965675a133c7e555024afd9f27d57db'),
  ('52fede54f8db457593083e117a099186be4a34a09e9754ff764f6eab9ef9ccb2'),
  ('cf1845aad13983402381eeb6aca8493c6e6603f989eed0459f1aff7e67b8e0fa'),
  ('0ac1e9f273a9b7479ff39e07945138d2fc606ca00824d4485d2da8602af45c93'),
  ('15100ea2c631cfce54ad5ea8c78d9781df5e2ce35cc2430d1ef70e58aa5c2f7a'),
  ('d7864afc82a5ef8f2823f778e91de4dc9c488672055aec30e0123018c8a70773'),
  ('53482d063324c1f5b1b11f2457c5886d6846ca781f72181fd226ce7ef1a23083'),
  ('e827994ce70911dee128f791000269c4ff3b4269ef77bb831ba8c9ffa90dac57'),
  ('6a2030f9d33867b82c1b2c7758f74fb61da12d6ac1008acab8f589a75492f9f4'),
  ('252d32e621d1914ca22a24123a81699ca83cc421ab7048f1363cd92f56c1e68d'),
  ('fc42c45fad2f461455fe3cd7c9e296d8be032bebe1760efa4e8ca3fb99d553a3'),
  ('70d8af3f4be8f4ecf9612e4537d36dc024d4f58331b139dbd070bd2d24e049d3'),
  ('0e62364e9c83295f54f4c16c8b968798c5d883adc7ac94d0fa09fe86fd75d48f'),
  ('e8751638db4be6cbd1b10c64efcda24f489f59256522fd36cecffead9b537be2'),
  ('98e61bc2bdf210a711e54f98ccb0f6ad28e42ffcf10f369229261680e2ff9207'),
  ('b0a700d68f0402811a805d80c6dea49d352c8090cebcf129fe7e5fc4a0127c96'),
  ('121103d612ddf8e4800772a26e98b26439d68a5ae46761a6356bdb603b57f6fe'),
  ('24928ce758139ffaf237cf1917551c044833fa681e865adc9ac17a0423f650a9'),
  ('db9832663721db333a570aba7344ea9a62429d69cdaba3baf00ece5da6b15444'),
  ('d48effe750f5fc705953cdfa0b35f3a3ec8130577df825dbea28599df91ab534'),
  ('7d42dc923a9bc5ed5e8a38c30ded2ee62ad3db90a5e0969c7a770ed02281f402'),
  ('8885dc3c1cd07d2be9b2b681c963f75d9e185a9c7136745e58edb560e4ddeda1'),
  ('5b745e589ca3c1080cfedab5e32d3930bdad7f12350dab6300739d3188d998ff')
on conflict (code_hash) do nothing;
