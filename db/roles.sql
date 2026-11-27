-- Create roles safely if they do not exist
DO $$
BEGIN
	IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'chaosdesk_owner') THEN
		CREATE ROLE chaosdesk_owner WITH LOGIN NOSUPERUSER NOBYPASSRLS;
	END IF;
	IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'chaosdesk_app') THEN
		CREATE ROLE chaosdesk_app WITH LOGIN NOSUPERUSER NOBYPASSRLS;
	END IF;
	IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'chaosdesk_admin') THEN
		CREATE ROLE chaosdesk_admin WITH LOGIN NOSUPERUSER BYPASSRLS;
	END IF;
END
$$;

ALTER ROLE chaosdesk_owner WITH PASSWORD :'owner_password';
ALTER ROLE chaosdesk_app WITH PASSWORD :'app_password';
ALTER ROLE chaosdesk_admin WITH PASSWORD :'admin_password';
