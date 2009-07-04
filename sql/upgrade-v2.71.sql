--
-- Upgrades pre-v2.71 databases to 2.71 format.
--
ALTER TABLE last_picture_cache ADD COLUMN last_update TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now();
ALTER TABLE events DROP COLUMN last_update;
ALTER TABLE users ADD COLUMN digest_ha1_hex character(32);
ALTER TABLE users ALTER COLUMN sha1password TYPE character(27);

GRANT UPDATE ON TABLE users TO pr0n;
