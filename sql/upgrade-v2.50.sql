--
-- Upgrades pre-v2.50 databases to 2.50 format.
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

-- width/height -1 => NULL
ALTER TABLE images ALTER COLUMN width DROP NOT NULL;
ALTER TABLE images ALTER COLUMN height DROP NOT NULL;
ALTER TABLE images ALTER COLUMN width SET DEFAULT NULL;
ALTER TABLE images ALTER COLUMN height SET DEFAULT NULL;
UPDATE images SET width=NULL,height=NULL WHERE width=-1 OR height=-1;
ALTER TABLE images ADD CONSTRAINT width_height_nullity CHECK ((width IS NULL) = (height IS NULL));

ALTER TABLE deleted_images ALTER COLUMN width DROP NOT NULL;
ALTER TABLE deleted_images ALTER COLUMN height DROP NOT NULL;
ALTER TABLE deleted_images ALTER COLUMN width SET DEFAULT NULL;
ALTER TABLE deleted_images ALTER COLUMN height SET DEFAULT NULL;
UPDATE deleted_images SET width=NULL,height=NULL WHERE width=-1 OR height=-1;
ALTER TABLE deleted_images ADD CONSTRAINT width_height_nullity CHECK ((width IS NULL) = (height IS NULL));

-- model/lens denormalization (reduce usage of exif_info)
ALTER TABLE images ADD COLUMN model varchar;
ALTER TABLE images ADD COLUMN lens varchar;
UPDATE images SET lens=COALESCE(
    TRIM((
        SELECT value FROM exif_info WHERE key='Lens' AND images.id=exif_info.image
    )),
    TRIM((
        SELECT value FROM exif_info WHERE key='LensSpec' AND images.id=exif_info.image
    ))
), model=TRIM((
    SELECT value FROM exif_info WHERE key='Model' AND images.id=exif_info.image
));
UPDATE images SET model=NULL WHERE model='';
UPDATE images SET lens=NULL WHERE lens='';

ALTER TABLE deleted_images ADD COLUMN model varchar;
ALTER TABLE deleted_images ADD COLUMN lens varchar;
UPDATE deleted_images SET lens=COALESCE(
    TRIM((
        SELECT value FROM exif_info WHERE key='Lens' AND deleted_images.id=exif_info.image
    )),
    TRIM((
        SELECT value FROM exif_info WHERE key='LensSpec' AND deleted_images.id=exif_info.image
    ))
), model=TRIM((
    SELECT value FROM exif_info WHERE key='Model' AND deleted_images.id=exif_info.image
));
UPDATE deleted_images SET model=NULL WHERE model='';
UPDATE deleted_images SET lens=NULL WHERE lens='';

