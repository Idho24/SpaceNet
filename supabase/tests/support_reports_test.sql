-- Runs as postgres; all report/user/admin fixtures are rolled back.
begin;
do $test$
declare
  owner_id uuid;
  other_id uuid := gen_random_uuid();
  admin_id uuid := gen_random_uuid();
  report_id uuid := gen_random_uuid();
  cancelled_id uuid := gen_random_uuid();
  test_email text := 'support-test-' || gen_random_uuid()::text || '@example.invalid';
begin
  if not exists(select 1 from storage.buckets where id='support-attachments' and not public and file_size_limit=5242880) then
    raise exception 'Attachment bucket is not private or lacks the size limit';
  end if;
  select id into owner_id from public.profiles where customer_id is not null limit 1;
  if owner_id is null then raise exception 'A linked customer is required for this test'; end if;
  insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    values(admin_id,test_email,now(),'{"provider":"google","providers":["google"]}','{}',now(),now());
  insert into support_private.admin_emails(email) values(test_email);

  set local role authenticated;
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  if public.is_support_admin() then raise exception 'Customer unexpectedly has admin rights'; end if;
  perform public.create_support_ticket(cancelled_id,'Internet lambat','Laporan yang akan dibatalkan.',null);
  perform public.update_support_ticket(cancelled_id,1,'cancelled','Koneksi telah pulih sebelum diperiksa.');
  if (select status from public.support_tickets where id=cancelled_id) <> 'cancelled' then
    raise exception 'Customer cannot cancel their open report';
  end if;
  perform public.create_support_ticket(report_id,'Internet mati','Koneksi pengujian terputus.',null);
  perform public.create_support_ticket(report_id,'Internet mati','Koneksi pengujian terputus.',null);
  if (select count(*) from public.support_tickets where id=report_id) <> 1
      or (select count(*) from public.support_ticket_events where ticket_id=report_id) <> 1 then
    raise exception 'Create retry was not idempotent';
  end if;
  begin
    perform public.update_support_ticket(report_id,1,'resolved','Bukan admin.');
    raise exception 'Customer can resolve tickets';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.support_tickets set status='resolved' where id=report_id;
    raise exception 'Direct client update was allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.create_support_ticket(gen_random_uuid(),'Internet mati','Lampiran milik orang lain.','another-user/photo.jpg');
    raise exception 'Foreign attachment was accepted';
  exception when invalid_parameter_value then null;
  end;
  perform set_config('request.jwt.claim.sub',other_id::text,true);
  if exists(select 1 from public.support_tickets where id=report_id)
    or exists(select 1 from public.support_ticket_events where ticket_id=report_id) then
    raise exception 'Another customer can read this report or its events';
  end if;
  begin
    perform public.update_support_ticket(report_id,1,'cancelled','Percobaan akun lain.');
    raise exception 'Another customer can change this report';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  if not public.is_support_admin() then raise exception 'Confirmed allowlisted admin not recognized'; end if;
  if not exists(select 1 from public.support_tickets where id=report_id) then raise exception 'Admin cannot read customer report'; end if;
  perform public.update_support_ticket(report_id,1,'review','Tim sedang memeriksa jaringan.');
  begin
    perform public.update_support_ticket(report_id,1,'in_progress','Versi lama.');
    raise exception 'Stale update overwrote newer status';
  exception when serialization_failure then null;
  end;
  begin
    perform public.update_support_ticket(report_id,2,'invalid','Status tidak valid.');
    raise exception 'Invalid status was accepted';
  exception when invalid_parameter_value then null;
  end;
  perform public.update_support_ticket(report_id,2,'in_progress','Teknisi sedang menangani gangguan.');
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  if (select status from public.support_tickets where id=report_id) <> 'in_progress'
    or not exists(select 1 from public.support_ticket_events where ticket_id=report_id and actor_role='admin' and status='in_progress') then
    raise exception 'Admin status or notes missing from customer view';
  end if;
  perform public.update_support_ticket(report_id,3,'in_progress','Terima kasih, saya menunggu teknisi.');
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.update_support_ticket(report_id,4,'resolved','Koneksi sudah normal.');
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  begin
    perform public.update_support_ticket(report_id,5,'cancelled','Membatalkan laporan selesai.');
    raise exception 'Customer changed a closed report';
  exception when insufficient_privilege then null;
  end;
  if (select count(*) from public.support_ticket_events where ticket_id=report_id) <> 5 then
    raise exception 'Audit trail does not match successful updates';
  end if;
  if has_function_privilege('anon','public.create_support_ticket(uuid,text,text,text)','execute')
    or has_table_privilege('anon','public.support_tickets','select') then
    raise exception 'Anonymous access is enabled';
  end if;
  reset role;
  update auth.users set email_confirmed_at=null where id=admin_id;
  set local role authenticated;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  if public.is_support_admin() then raise exception 'Unverified admin email was trusted'; end if;
  reset role;
end;
$test$;
rollback;
select 'PASS: idempotent create, customer isolation, admin processing, audit trail, version conflicts, closed reports, private attachments, verified admin email; fixtures rolled back' as result;
