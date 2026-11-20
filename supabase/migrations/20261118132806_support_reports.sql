-- Customer reports, staff processing, and private attachments.
create schema if not exists support_private;
revoke all on schema support_private from public, anon, authenticated;
grant usage on schema support_private to authenticated;

create table support_private.admin_emails (
  email text primary key check (email = lower(email))
);
alter table support_private.admin_emails enable row level security;
revoke all on support_private.admin_emails from public, anon, authenticated;

create function support_private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u join support_private.admin_emails a on a.email = lower(u.email)
    where u.id = (select auth.uid()) and u.email_confirmed_at is not null
      and u.is_anonymous is not true
  );
$$;
revoke all on function support_private.is_admin() from public, anon;
grant execute on function support_private.is_admin() to authenticated;

create function public.is_support_admin() returns boolean
language sql stable security invoker set search_path = '' as $$
  select support_private.is_admin();
$$;
revoke all on function public.is_support_admin() from public, anon;
grant execute on function public.is_support_admin() to authenticated;

create table public.support_tickets (
  id uuid primary key,
  ticket_number bigint generated always as identity unique,
  user_id uuid not null references auth.users(id),
  customer_id text not null references public.customers(customer_id),
  customer_name text not null,
  category text not null check (category in ('Internet mati','Internet lambat','LOS merah','Router bermasalah','Koneksi tidak stabil','Lainnya')),
  description text not null check (char_length(btrim(description)) between 8 and 500),
  photo_path text,
  status text not null default 'open' check (status in ('open','review','in_progress','resolved','cancelled')),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index support_tickets_user_created_idx on public.support_tickets(user_id, created_at desc);
create index support_tickets_status_created_idx on public.support_tickets(status, created_at desc);
create index support_tickets_customer_idx on public.support_tickets(customer_id);
create table public.support_ticket_events (
  id bigint generated always as identity primary key,
  ticket_id uuid not null references public.support_tickets(id) on delete cascade,
  actor_id uuid not null references auth.users(id),
  actor_role text not null check (actor_role in ('customer','admin')),
  status text not null,
  message text not null check (char_length(message) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index support_events_ticket_idx on public.support_ticket_events(ticket_id,id);
create index support_events_actor_idx on public.support_ticket_events(actor_id);
alter table public.support_tickets enable row level security;
alter table public.support_ticket_events enable row level security;
revoke all on public.support_tickets, public.support_ticket_events from public, anon, authenticated;
grant select on public.support_tickets, public.support_ticket_events to authenticated;
create policy support_tickets_read on public.support_tickets for select to authenticated
using (user_id = (select auth.uid()) or (select support_private.is_admin()));
create policy support_events_read on public.support_ticket_events for select to authenticated
using ((select support_private.is_admin()) or exists (
  select 1 from public.support_tickets t
  where t.id = support_ticket_events.ticket_id and t.user_id = (select auth.uid())
));

-- Only these guarded functions may create/update reports; ownership and audit fields are server-owned.
create function support_private.create_ticket(p_id uuid, p_category text, p_description text, p_photo_path text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_customer public.customers%rowtype; v_existing public.support_tickets%rowtype;
begin
  if v_uid is null then raise exception 'Silakan login kembali.' using errcode='42501'; end if;
  select c.* into v_customer from public.customers c join public.profiles p on p.customer_id=c.customer_id where p.id=v_uid;
  if not found then raise exception 'Hubungkan ID pelanggan terlebih dahulu.' using errcode='42501'; end if;
  -- Repeating a request after a lost network response returns the same ticket.
  perform pg_advisory_xact_lock(hashtextextended(p_id::text, 0));
  select * into v_existing from public.support_tickets where id=p_id;
  if found then
    if v_existing.user_id=v_uid and v_existing.category=p_category
      and v_existing.description=btrim(p_description) and v_existing.photo_path is not distinct from p_photo_path then return p_id; end if;
    raise exception 'ID laporan sudah digunakan.' using errcode='23505';
  end if;
  if p_photo_path is not null and (p_photo_path not like v_uid::text || '/' || p_id::text || '/%'
      or not exists (select 1 from storage.objects where bucket_id='support-attachments' and name=p_photo_path)) then
    raise exception 'Lampiran belum berhasil diunggah.' using errcode='22023';
  end if;
  insert into public.support_tickets(id,user_id,customer_id,customer_name,category,description,photo_path)
    values(p_id,v_uid,v_customer.customer_id,v_customer.name,p_category,btrim(p_description),p_photo_path);
  insert into public.support_ticket_events(ticket_id,actor_id,actor_role,status,message)
    values(p_id,v_uid,'customer','open','Laporan diterima. Menunggu pemeriksaan tim dukungan.');
  return p_id;
end;
$$;
create function support_private.update_ticket(p_id uuid, p_expected_version integer, p_status text, p_message text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_ticket public.support_tickets%rowtype; v_admin boolean := support_private.is_admin(); v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Silakan login kembali.' using errcode='42501'; end if;
  select * into v_ticket from public.support_tickets where id=p_id for update;
  if not found or (not v_admin and v_ticket.user_id<>v_uid) then
    raise exception 'Laporan tidak ditemukan atau akses ditolak.' using errcode='42501';
  end if;
  if p_expected_version is distinct from v_ticket.version then
    raise exception 'Laporan baru saja diperbarui. Muat ulang sebelum menyimpan.' using errcode='40001';
  end if;
  if p_status is null or p_status not in ('open','review','in_progress','resolved','cancelled') then
    raise exception 'Status laporan tidak valid.' using errcode='22023';
  end if;
  if not v_admin and (v_ticket.status in ('resolved','cancelled') or
      (p_status<>v_ticket.status and p_status<>'cancelled')) then
    raise exception 'Hanya admin yang dapat memperbarui proses laporan.' using errcode='42501';
  end if;
  if p_message is null or char_length(btrim(p_message)) not between 1 and 1000 then
    raise exception 'Catatan wajib diisi, maksimal 1000 karakter.' using errcode='22023';
  end if;
  update public.support_tickets set status=p_status,version=version+1,updated_at=clock_timestamp() where id=p_id;
  insert into public.support_ticket_events(ticket_id,actor_id,actor_role,status,message)
    values(p_id,v_uid,case when v_admin then 'admin' else 'customer' end,p_status,btrim(p_message));
end;
$$;
revoke all on function support_private.create_ticket(uuid,text,text,text), support_private.update_ticket(uuid,integer,text,text) from public, anon;
grant execute on function support_private.create_ticket(uuid,text,text,text), support_private.update_ticket(uuid,integer,text,text) to authenticated;
create function public.create_support_ticket(p_id uuid,p_category text,p_description text,p_photo_path text default null)
returns uuid language sql security invoker set search_path = '' as $$
 select support_private.create_ticket(p_id,p_category,p_description,p_photo_path);
$$;
create function public.update_support_ticket(p_id uuid,p_expected_version integer,p_status text,p_message text)
returns void language sql security invoker set search_path = '' as $$
 select support_private.update_ticket(p_id,p_expected_version,p_status,p_message);
$$;
revoke all on function public.create_support_ticket(uuid,text,text,text), public.update_support_ticket(uuid,integer,text,text) from public, anon;
grant execute on function public.create_support_ticket(uuid,text,text,text), public.update_support_ticket(uuid,integer,text,text) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('support-attachments','support-attachments',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy support_photo_insert on storage.objects for insert to authenticated
with check (bucket_id='support-attachments' and (storage.foldername(name))[1]=(select auth.uid())::text
  and exists(select 1 from public.profiles where id=(select auth.uid()) and customer_id is not null));
create policy support_photo_read on storage.objects for select to authenticated
using (bucket_id='support-attachments' and ((storage.foldername(name))[1]=(select auth.uid())::text
  or (select support_private.is_admin())));
-- Report attachments cannot be overwritten or deleted by clients.
