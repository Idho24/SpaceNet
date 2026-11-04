create table if not exists public.customers (
  customer_id text primary key,
  name text not null,
  phone text not null check (phone ~ '^\+[1-9][0-9]{7,14}$'),
  email text not null,
  address text not null,
  active_package text not null,
  subscription_status text not null,
  installation_date timestamptz not null,
  expiry_date timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  customer_id text unique references public.customers(customer_id),
  full_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.customers enable row level security;
alter table public.profiles enable row level security;

drop policy if exists "Customers readable by linked owner" on public.customers;
create policy "Customers readable by linked owner"
  on public.customers
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.profiles
      where profiles.id = (select auth.uid())
        and profiles.customer_id = customers.customer_id
    )
  );

drop policy if exists "Users can read their profile" on public.profiles;
create policy "Users can read their profile"
  on public.profiles
  for select
  to authenticated
  using (id = (select auth.uid()));

revoke all on public.customers from anon, authenticated;
revoke all on public.profiles from anon, authenticated;
grant select on public.customers, public.profiles to authenticated;

create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function public.create_profile_for_new_user() from public, anon, authenticated;

drop trigger if exists create_profile_after_signup on auth.users;
create trigger create_profile_after_signup
  after insert on auth.users
  for each row execute function public.create_profile_for_new_user();

create or replace function public.link_customer(p_customer_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_verified_phone text;
  v_existing_customer_id text;
begin
  if v_user_id is null then
    raise exception 'Authentication is required.';
  end if;

  select users.phone
    into v_verified_phone
    from auth.users as users
   where users.id = v_user_id
     and users.phone_confirmed_at is not null;

  if v_verified_phone is null then
    raise exception 'Verify your phone number with Supabase Auth before linking.';
  end if;

  if not exists (
    select 1
      from public.customers as customer
     where customer.customer_id = p_customer_id
       and customer.phone = v_verified_phone
  ) then
    raise exception 'Customer ID and verified phone number do not match.';
  end if;

  select profile.customer_id
    into v_existing_customer_id
    from public.profiles as profile
   where profile.id = v_user_id;

  if v_existing_customer_id is not null
     and v_existing_customer_id <> p_customer_id then
    raise exception 'This account is already linked to a customer.';
  end if;

  insert into public.profiles (id, customer_id, updated_at)
  values (v_user_id, p_customer_id, now())
  on conflict (id) do update
    set customer_id = excluded.customer_id,
        updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.link_customer(text) from public, anon;
grant execute on function public.link_customer(text) to authenticated;
