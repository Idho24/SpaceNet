-- Operator-only setup. Verified login is required; this does not create credentials.
insert into support_private.admin_emails(email)
values ('spacenetlite@gmail.com') on conflict do nothing;
