-- Run once per database, connected to it, with -v chaosdesk_db=<name>
ALTER DATABASE :"chaosdesk_db" OWNER TO chaosdesk_owner;
ALTER SCHEMA public OWNER TO chaosdesk_owner;
ALTER DEFAULT PRIVILEGES FOR ROLE chaosdesk_owner
	GRANT SELECT ON TABLES TO chaosdesk_admin;
ALTER DEFAULT PRIVILEGES FOR ROLE chaosdesk_owner
	GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO chaosdesk_app;
ALTER DEFAULT PRIVILEGES FOR ROLE chaosdesk_owner
	GRANT USAGE ON SEQUENCES TO chaosdesk_app;

ALTER DEFAULT PRIVILEGES FOR ROLE chaosdesk_owner REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
