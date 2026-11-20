create extension if not exists pg_net with schema extensions;
create table support_private.push_config (
 id boolean primary key default true check(id),
 enabled boolean not null default false,
 worker_secret text not null default encode(extensions.gen_random_bytes(32),'hex'),
 endpoint text not null
);
insert into support_private.push_config(endpoint) values('https://jenqyryusfuxgswvftvc.supabase.co/functions/v1/dispatch-service-push');
create table support_private.push_devices (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 session_id uuid not null references auth.sessions(id) on delete cascade,
 token text not null unique check(char_length(token) between 40 and 4096),
 updated_at timestamptz not null default now()
);
create index push_devices_user_idx on support_private.push_devices(user_id);
create index push_devices_session_idx on support_private.push_devices(session_id);
create table support_private.push_jobs (
 id uuid primary key default gen_random_uuid(),
 device_id uuid not null references support_private.push_devices(id) on delete cascade,
 user_id uuid not null references auth.users(id) on delete cascade,
 announcement_id uuid not null references public.service_announcements(id) on delete cascade,
 version integer not null,
 state text not null default 'pending' check(state in ('pending','processing','sent','skipped','failed')),
 attempts integer not null default 0,
 available_at timestamptz not null default now(),
 lease_id uuid,
 lease_until timestamptz,
 created_at timestamptz not null default now(),
 error_code text,
 unique(device_id,announcement_id,version)
);
create index push_jobs_available_idx on support_private.push_jobs(state,available_at);
create index push_jobs_user_idx on support_private.push_jobs(user_id);
create index push_jobs_announcement_idx on support_private.push_jobs(announcement_id);
alter table support_private.push_config enable row level security;
alter table support_private.push_devices enable row level security;
alter table support_private.push_jobs enable row level security;
revoke all on support_private.push_config,support_private.push_devices,support_private.push_jobs from public,anon,authenticated;

create function support_private.register_push(p_token text) returns void
language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); v_session uuid:=(auth.jwt()->>'session_id')::uuid;
begin
 if v_uid is null or not exists(select 1 from public.profiles where id=v_uid and customer_id is not null)
   or not exists(select 1 from auth.sessions where id=v_session and user_id=v_uid and (not_after is null or not_after>now())) then
   raise exception 'Login dan hubungkan ID pelanggan terlebih dahulu.' using errcode='42501';
 end if;
 if p_token is null or char_length(p_token) not between 40 and 4096 then raise exception 'Token perangkat tidak valid.' using errcode='22023'; end if;
 -- Token possession identifies an installation; moving accounts replaces its old binding.
 insert into support_private.push_devices(user_id,session_id,token) values(v_uid,v_session,p_token)
 on conflict(token) do update set user_id=excluded.user_id,session_id=excluded.session_id,updated_at=now();
end;
$$;
create function public.register_push_device(p_token text) returns void language sql security invoker set search_path='' as $$
 select support_private.register_push(p_token);
$$;
create function support_private.unregister_push(p_token text) returns void language sql security definer set search_path='' as $$
 delete from support_private.push_devices where user_id=(select auth.uid()) and token=p_token;
$$;
create function public.unregister_push_device(p_token text) returns void language sql security invoker set search_path='' as $$
 select support_private.unregister_push(p_token);
$$;
create function support_private.push_enabled() returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((select enabled from support_private.push_config where id),false) and auth.uid() is not null;
$$;
create function public.service_push_enabled() returns boolean language sql stable security invoker set search_path='' as $$
 select support_private.push_enabled();
$$;
revoke all on function support_private.register_push(text),public.register_push_device(text),support_private.unregister_push(text),
 public.unregister_push_device(text),support_private.push_enabled(),public.service_push_enabled() from public,anon;
grant execute on function support_private.register_push(text),public.register_push_device(text),support_private.unregister_push(text),
 public.unregister_push_device(text),support_private.push_enabled(),public.service_push_enabled() to authenticated;

create function support_private.enqueue_service_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.archived or (tg_op='UPDATE' and new.version=old.version) then return new; end if;
 insert into support_private.push_jobs(device_id,user_id,announcement_id,version)
 select d.id,d.user_id,new.id,new.version from support_private.push_devices d
 join public.profiles p on p.id=d.user_id and p.customer_id is not null
 join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
 left join public.notification_preferences n on n.user_id=d.user_id
 where coalesce(n.service_enabled,true) and (s.not_after is null or s.not_after>now())
 on conflict do nothing;
 return new;
end;
$$;
revoke all on function support_private.enqueue_service_push() from public,anon,authenticated;
create trigger enqueue_service_push after insert or update on public.service_announcements
 for each row execute function support_private.enqueue_service_push();

create function public.authorize_push_worker(p_secret text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from support_private.push_config where enabled and
 extensions.digest(worker_secret,'sha256')=extensions.digest(p_secret,'sha256'));
$$;
create function public.claim_service_push(p_limit integer default 40)
returns table(job_id uuid,lease_id uuid,token text,announcement_id uuid,version integer,title text,message text,area text,status text)
language plpgsql security definer set search_path='' as $$
begin
 -- Cancel stale revisions, logged-out devices, disabled preferences, and old notices before claiming.
 update support_private.push_jobs j set state='skipped',error_code='NO_LONGER_ELIGIBLE'
 where j.state in ('pending','processing') and (
   j.created_at<now()-interval '24 hours' or not exists(
     select 1 from support_private.push_devices d join auth.sessions s on s.id=d.session_id and s.user_id=d.user_id
     join public.profiles p on p.id=d.user_id and p.customer_id is not null
     join public.service_announcements a on a.id=j.announcement_id and a.version=j.version and not a.archived
     left join public.notification_preferences n on n.user_id=d.user_id
     where d.id=j.device_id and d.user_id=j.user_id and coalesce(n.service_enabled,true)
       and (s.not_after is null or s.not_after>now())
   )
 );
 update support_private.push_jobs set state='failed',error_code='RETRY_LIMIT'
 where state in ('pending','processing') and attempts>=6 and (lease_until is null or lease_until<now());
 return query with candidates as (
   select j.id from support_private.push_jobs j
   where j.attempts<6 and ((j.state='pending' and j.available_at<=now()) or (j.state='processing' and j.lease_until<now()))
   order by j.available_at,j.id for update skip locked limit greatest(1,least(p_limit,100))
 ), claimed as (
   update support_private.push_jobs j set state='processing',attempts=j.attempts+1,lease_id=gen_random_uuid(),lease_until=now()+interval '3 minutes'
   from candidates c where j.id=c.id returning j.*
 ) select c.id,c.lease_id,d.token,a.id,a.version,a.title,a.message,a.area,a.status
 from claimed c join support_private.push_devices d on d.id=c.device_id
 join public.service_announcements a on a.id=c.announcement_id;
end;
$$;
create function public.finish_service_push(p_id uuid,p_lease uuid,p_result text,p_code text default null) returns void
language plpgsql security definer set search_path='' as $$
declare v_job support_private.push_jobs%rowtype;
begin
 select * into v_job from support_private.push_jobs where id=p_id and lease_id=p_lease and state='processing' for update;
 if not found then return; end if;
 if p_result='invalid_token' then
   delete from support_private.push_devices where id=v_job.device_id;
   return;
 end if;
 if p_result not in ('sent','retry','failed') then raise exception 'Invalid push result'; end if;
 update support_private.push_jobs set
   state=case when p_result='retry' and attempts<6 then 'pending' when p_result='sent' then 'sent' else 'failed' end,
   available_at=now()+make_interval(secs=>least(3600,30*power(2,attempts)::integer)),
   lease_until=null,error_code=left(p_code,80)
 where id=p_id;
end;
$$;
revoke all on function public.authorize_push_worker(text),public.claim_service_push(integer),public.finish_service_push(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.authorize_push_worker(text),public.claim_service_push(integer),public.finish_service_push(uuid,uuid,text,text) to service_role;

create function support_private.tick_push_worker() returns void language plpgsql security definer set search_path='' as $$
declare c support_private.push_config%rowtype;
begin
 select * into c from support_private.push_config where id and enabled;
 if not found or not exists(select 1 from support_private.push_jobs where state='pending' and available_at<=now()
   or state='processing' and lease_until<now()) then return; end if;
 perform net.http_post(url:=c.endpoint,headers:=jsonb_build_object('Content-Type','application/json','x-push-secret',c.worker_secret),body:='{}'::jsonb,timeout_milliseconds:=10000);
end;
$$;
revoke all on function support_private.tick_push_worker() from public,anon,authenticated;
select cron.schedule('spacenet-service-push','* * * * *','select support_private.tick_push_worker()');
