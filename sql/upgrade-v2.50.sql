--
-- Upgrades pre-v2.50 databases to 2.50 format -- not many changes, though.
--
ALTER TABLE exif_info RENAME COLUMN tag TO key;
CREATE INDEX exif_info_key ON exif_info ( key );
CLUSTER exif_info_key ON exif_info;

