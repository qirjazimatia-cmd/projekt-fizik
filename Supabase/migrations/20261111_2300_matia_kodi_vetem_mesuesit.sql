-- Hyrja më e lehtë (kërkesa e Matias): kodi i dytë me email kërkohet vetëm për mësuesit.
-- Nxënësit dhe prindërit hyjnë me email + fjalëkalim; pastaj app-i hapet me Face ID / Touch ID në pajisje.
-- Mësuesit (që vendosin nota dhe teste) vazhdojnë me kodin me email në çdo hyrje.
-- Për ta kthyer si më parë: update app.settings set value = 'all' where name = 'require_mfa';
insert into app.settings(name, value) values ('require_mfa', 'teacher')
on conflict (name) do update set value = excluded.value;
