--
-- Upgrades pre-v2.50 databases to 2.50 format -- not many changes, though.
--
SET work_mem=131072;

ALTER TABLE exif_info RENAME COLUMN tag TO key;
CREATE INDEX exif_info_key ON exif_info ( key );
CLUSTER exif_info_key ON exif_info;

CREATE TABLE tags (
    image integer NOT NULL REFERENCES images (id) ON DELETE CASCADE,
    tag varchar NOT NULL,

    PRIMARY KEY ( image, tag )
);
CREATE INDEX tags_tag ON tags ( tag );

GRANT SELECT,INSERT,DELETE ON TABLE tags TO pr0n;
