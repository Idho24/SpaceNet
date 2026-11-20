create table public.service_announcements (
  id uuid primary key,
  kind text not null check (kind in ('maintenance','outage')),
  title text not null check (char_length(btrim(title)) between 5 and 120),
  message text not null check (char_length(btrim(message)) between 10 and 2000),
  area text not null check (char_length(btrim(area)) between 1 and 160),
  status text not null check (status in ('scheduled','in_progress','resolved')),
  archived boolean not null default false,
  version integer not null default 1,
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index announcements_updated_idx on public.service_announcements(updated_at desc,id);
create index announcements_creator_idx on public.service_announcements(created_by);
create index announcements_updater_idx on public.service_announcements(updated_by);
create table public.service_announcement_reads (
  user_id uuid not null references auth.users(id) on delete cascade,
  announcement_id uuid not null references public.service_announcements(id) on delete cascade,
  version integer not null check (version>0),
  primary key(user_id,announcement_id)
);
create index announcement_reads_item_idx on public.service_announcement_reads(announcement_id);
create table public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  service_enabled boolean not null default true
);
alter table public.service_announcements enable row level security;
alter table public.service_announcement_reads enable row level security;
alter table public.notification_preferences enable row level security;
revoke all on public.service_announcements, public.service_announcement_reads, public.notification_preferences from public,anon,authenticated;
grant select on public.service_announcements,public.service_announcement_reads,public.notification_preferences to authenticated;
grant insert,update on public.notification_preferences to authenticated;
create policy announcements_read on public.service_announcements for select to authenticated
using ((select support_private.is_admin()) or (not archived and exists (
 select 1 from public.profiles where id=(select auth.uid()) and customer_id is not null
)));
create policy announcement_reads_own on public.service_announcement_reads for select to authenticated
using (user_id=(select auth.uid()));
create policy notification_preferences_read on public.notification_preferences for select to authenticated using (user_id=(select auth.uid()));
create policy notification_preferences_insert on public.notification_preferences for insert to authenticated with check (user_id=(select auth.uid()));
create policy notification_preferences_update on public.notification_preferences for update to authenticated
using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));

create function support_private.save_announcement(p_id uuid,p_version integer,p_kind text,p_title text,p_message text,p_area text,p_status text,p_archived boolean)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_old public.service_announcements%rowtype;
begin
 if auth.uid() is null or not support_private.is_admin() then
   raise exception 'Hanya admin yang dapat menerbitkan pengumuman.' using errcode='42501';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id::text,1));
 select * into v_old from public.service_announcements where id=p_id for update;
 if found then
   -- Same payload after a lost response is safe to retry.
   if v_old.kind=p_kind and v_old.title=btrim(p_title) and v_old.message=btrim(p_message)
     and v_old.area=btrim(p_area) and v_old.status=p_status and v_old.archived=p_archived then return p_id; end if;
   if v_old.version is distinct from p_version then
     raise exception 'Pengumuman telah berubah. Muat ulang sebelum menyimpan.' using errcode='40001';
   end if;
   update public.service_announcements set kind=p_kind,title=btrim(p_title),message=btrim(p_message),area=btrim(p_area),
     status=p_status,archived=p_archived,version=version+1,updated_by=auth.uid(),updated_at=clock_timestamp() where id=p_id;
 else
   if p_version is distinct from 0 then raise exception 'Pengumuman tidak ditemukan.' using errcode='22023'; end if;
   insert into public.service_announcements(id,kind,title,message,area,status,archived,created_by,updated_by)
     values(p_id,p_kind,btrim(p_title),btrim(p_message),btrim(p_area),p_status,p_archived,auth.uid(),auth.uid());
 end if;
 return p_id;
end;
$$;
create function public.save_service_announcement(p_id uuid,p_version integer,p_kind text,p_title text,p_message text,p_area text,p_status text,p_archived boolean default false)
returns uuid language sql security invoker set search_path='' as $$
 select support_private.save_announcement(p_id,p_version,p_kind,p_title,p_message,p_area,p_status,p_archived);
$$;

create function support_private.read_announcement(p_id uuid,p_version integer)
returns void language plpgsql security definer set search_path='' as $$
declare v_current integer;
begin
 if auth.uid() is null or not (support_private.is_admin() or exists (
   select 1 from public.profiles where id=auth.uid() and customer_id is not null
 )) then raise exception 'Akses notifikasi ditolak.' using errcode='42501'; end if;
 select version into v_current from public.service_announcements where id=p_id and not archived;
 if not found or p_version is null or p_version<1 or p_version>v_current then
   raise exception 'Versi notifikasi tidak valid.' using errcode='22023';
 end if;
 insert into public.service_announcement_reads(user_id,announcement_id,version) values(auth.uid(),p_id,p_version)
 on conflict(user_id,announcement_id) do update set version=greatest(service_announcement_reads.version,excluded.version);
end;
$$;
create function public.read_service_announcement(p_id uuid,p_version integer)
returns void language sql security invoker set search_path='' as $$
 select support_private.read_announcement(p_id,p_version);
$$;
revoke all on function support_private.save_announcement(uuid,integer,text,text,text,text,text,boolean),
 public.save_service_announcement(uuid,integer,text,text,text,text,text,boolean),
 support_private.read_announcement(uuid,integer),public.read_service_announcement(uuid,integer) from public,anon;
grant execute on function support_private.save_announcement(uuid,integer,text,text,text,text,text,boolean),
 public.save_service_announcement(uuid,integer,text,text,text,text,text,boolean),
 support_private.read_announcement(uuid,integer),public.read_service_announcement(uuid,integer) to authenticated;
