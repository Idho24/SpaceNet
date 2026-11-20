begin;
do $test$
declare
  customer uuid;
  admin_id uuid:=gen_random_uuid();
  item_id uuid:=gen_random_uuid();
  email_address text:='announcement-test-'||gen_random_uuid()::text||'@example.invalid';
begin
  select p.id into customer from public.profiles p join auth.users u on u.id=p.id
    where p.customer_id is not null and not exists(select 1 from support_private.admin_emails a where a.email=lower(u.email)) limit 1;
  if customer is null then raise exception 'No linked customer fixture available'; end if;
  insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    values(admin_id,email_address,now(),'{"provider":"google"}','{}',now(),now());
  insert into support_private.admin_emails(email) values(email_address);
  set local role authenticated;
  perform set_config('request.jwt.claim.sub',customer::text,true);
  begin
    perform public.save_service_announcement(item_id,0,'outage','Gangguan pengujian','Pengumuman yang hanya dipakai untuk pengujian.','Area uji','in_progress',false);
    raise exception 'Customer can publish announcements';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.save_service_announcement(item_id,0,'outage','Gangguan pengujian','Pengumuman yang hanya dipakai untuk pengujian.','Area uji','in_progress',false);
  perform public.save_service_announcement(item_id,0,'outage','Gangguan pengujian','Pengumuman yang hanya dipakai untuk pengujian.','Area uji','in_progress',false);
  if (select version from public.service_announcements where id=item_id)<>1 then raise exception 'Retry created an extra revision'; end if;
  perform set_config('request.jwt.claim.sub',customer::text,true);
  if not exists(select 1 from public.service_announcements where id=item_id) then raise exception 'Customer cannot read announcement'; end if;
  perform public.read_service_announcement(item_id,1);
  if (select version from public.service_announcement_reads where announcement_id=item_id)<>1 then raise exception 'Read state not stored'; end if;
  begin
    perform public.read_service_announcement(item_id,99);
    raise exception 'Client can mark unseen future revisions read';
  exception when invalid_parameter_value then null; end;
  begin
    update public.service_announcements set status='resolved' where id=item_id;
    raise exception 'Client can directly edit announcement';
  exception when insufficient_privilege then null; end;
  insert into public.notification_preferences(user_id,service_enabled) values(customer,false)
    on conflict(user_id) do update set service_enabled=false;
  begin
    insert into public.notification_preferences(user_id,service_enabled) values(admin_id,false);
    raise exception 'Client can modify another user preference';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  if exists(select 1 from public.service_announcements where id=item_id)
    or exists(select 1 from public.service_announcement_reads where announcement_id=item_id)
    or exists(select 1 from public.notification_preferences where user_id=customer) then
    raise exception 'Unlinked account can read customer data';
  end if;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  if exists(select 1 from public.service_announcement_reads where announcement_id=item_id) then raise exception 'Read state leaks between accounts'; end if;
  perform public.save_service_announcement(item_id,1,'outage','Gangguan pengujian','Koneksi telah pulih setelah perbaikan jaringan.','Area uji','resolved',false);
  begin
    perform public.save_service_announcement(item_id,1,'outage','Gangguan pengujian','Pembaruan dari versi lama yang harus ditolak.','Area uji','in_progress',false);
    raise exception 'Stale update overwrote current status';
  exception when serialization_failure then null; end;
  perform set_config('request.jwt.claim.sub',customer::text,true);
  if not exists(select 1 from public.service_announcements a join public.service_announcement_reads r on r.announcement_id=a.id
    where a.id=item_id and a.version>r.version and a.status='resolved') then raise exception 'New status does not become unread'; end if;
  perform public.read_service_announcement(item_id,2);
  perform public.read_service_announcement(item_id,1);
  if (select version from public.service_announcement_reads where announcement_id=item_id)<>2 then raise exception 'Read state regressed'; end if;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.save_service_announcement(item_id,2,'outage','Gangguan pengujian','Koneksi telah pulih setelah perbaikan jaringan.','Area uji','resolved',true);
  if not exists(select 1 from public.service_announcements where id=item_id and archived) then raise exception 'Admin cannot see archive'; end if;
  perform set_config('request.jwt.claim.sub',customer::text,true);
  if exists(select 1 from public.service_announcements where id=item_id) then raise exception 'Archive still visible to customer'; end if;
  if has_function_privilege('anon','public.save_service_announcement(uuid,integer,text,text,text,text,text,boolean)','execute') then raise exception 'Anon can call publishing RPC'; end if;
  reset role;
end;
$test$;
rollback;
select 'PASS: admin-only publishing, retry safety, customer visibility, persistent per-user reads, unread updates, stale revision checks, archive visibility, preference isolation. No announcements published; all fixtures rolled back.' as result;
