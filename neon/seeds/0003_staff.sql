-- Make the demo officer an officer. Run after officer@fasttrack.demo has
-- signed up through Neon Auth (POST /auth/sign-up on the fasttrack function,
-- or the Neon Console → Auth → Users). Does nothing until that user exists.
--
-- To promote someone else, swap the email. Officer rights are only ever
-- granted here, server-side; there is no API that writes to staff.

insert into public.staff (user_id, email)
select u.id, u.email
from neon_auth."user" u
where lower(u.email) = 'officer@fasttrack.demo'
on conflict (user_id) do update set email = excluded.email;
