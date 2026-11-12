-- RPC khusus mode pengujian: menghubungkan akun pelanggan tanpa
-- memeriksa phone_confirmed_at di auth.users.
-- Berguna saat SUPABASE_ENABLE_PHONE_OTP = false (OTP mock lokal).
--
-- PENTING: Fungsi ini hanya digunakan oleh aplikasi saat mode pengujian
-- (debug build tanpa SMS provider aktif). Di produksi, gunakan
-- link_customer() yang memverifikasi nomor ponsel terlebih dahulu.

create or replace function public.link_customer_testing(p_customer_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_existing_customer_id text;
begin
  if v_user_id is null then
    raise exception 'Authentication is required.';
  end if;

  -- Pastikan customer_id ada di tabel customers
  if not exists (
    select 1
      from public.customers as customer
     where customer.customer_id = p_customer_id
  ) then
    raise exception 'ID pelanggan tidak ditemukan di database.';
  end if;

  -- Periksa apakah user sudah terhubung ke customer lain
  select profile.customer_id
    into v_existing_customer_id
    from public.profiles as profile
   where profile.id = v_user_id;

  if v_existing_customer_id is not null
     and v_existing_customer_id <> p_customer_id then
    raise exception 'Akun ini sudah terhubung ke pelanggan lain.';
  end if;

  -- Hubungkan tanpa memeriksa verifikasi nomor ponsel
  insert into public.profiles (id, customer_id, updated_at)
  values (v_user_id, p_customer_id, now())
  on conflict (id) do update
    set customer_id = excluded.customer_id,
        updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.link_customer_testing(text) from public, anon;
grant execute on function public.link_customer_testing(text) to authenticated;

-- RPC publik untuk validasi customer_id + phone di mode pengujian.
-- Mengembalikan true jika customer_id dan phone cocok di tabel customers.
-- Callable oleh anon agar demo user (tanpa Supabase auth) bisa validasi.
create or replace function public.validate_customer_phone(
  p_customer_id text,
  p_phone text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  return exists (
    select 1
      from public.customers as c
     where c.customer_id = p_customer_id
       and c.phone = p_phone
  );
end;
$$;

revoke all on function public.validate_customer_phone(text, text) from public;
grant execute on function public.validate_customer_phone(text, text) to anon, authenticated;

-- RPC publik untuk mengambil data customer setelah validasi berhasil (mode pengujian).
-- Hanya mengembalikan data yang dibutuhkan oleh UI.
create or replace function public.get_customer_for_testing(p_customer_id text)
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result json;
begin
  select json_build_object(
    'customer_id', c.customer_id,
    'name', c.name,
    'phone', c.phone,
    'email', c.email,
    'address', c.address,
    'active_package', c.active_package,
    'subscription_status', c.subscription_status,
    'installation_date', c.installation_date,
    'expiry_date', c.expiry_date,
    'created_at', c.created_at,
    'updated_at', c.updated_at
  )
  into v_result
  from public.customers as c
  where c.customer_id = p_customer_id;

  return v_result;
end;
$$;

revoke all on function public.get_customer_for_testing(text) from public;
grant execute on function public.get_customer_for_testing(text) to anon, authenticated;
