--
-- Upgrades pre-v2.40 databases to 2.40 format -- basically, the unique event identifier
-- has changed from (event) to (vhost,event) and we need to handle that.
--

ALTER TABLE events RENAME COLUMN id TO event;

-- Create the new index that will eventually replace the old one
CREATE UNIQUE INDEX events_pkey2 ON events ( vhost, event );

-- Add a vhost column to the images table, populate it, and make a new foreign
-- key constraint
ALTER TABLE images ADD COLUMN vhost varchar;
UPDATE images SET vhost=( SELECT vhost FROM events WHERE event=images.event );
ALTER TABLE images ADD FOREIGN KEY (vhost, event) REFERENCES events (vhost,event);
ALTER TABLE images ALTER COLUMN vhost SET NOT NULL;

-- Same for fake_files
ALTER TABLE fake_files ADD COLUMN vhost varchar;
UPDATE fake_files SET vhost=( SELECT vhost FROM events WHERE event=fake_files.event );
ALTER TABLE fake_files ADD FOREIGN KEY (vhost, event) REFERENCES events (vhost,event);
ALTER TABLE fake_files ALTER COLUMN vhost SET NOT NULL;

-- and last_picture_cache
ALTER TABLE last_picture_cache ADD COLUMN vhost varchar;
UPDATE last_picture_cache SET vhost=( SELECT vhost FROM events WHERE event=last_picture_cache.event );
ALTER TABLE last_picture_cache ADD FOREIGN KEY (vhost, event) REFERENCES events (vhost,event);
ALTER TABLE last_picture_cache ALTER COLUMN vhost SET NOT NULL;

ALTER TABLE last_picture_cache DROP CONSTRAINT last_picture_cache_pkey;
ALTER TABLE last_picture_cache ADD PRIMARY KEY (vhost,event);

-- and deleted_images
ALTER TABLE deleted_images ADD COLUMN vhost varchar;
UPDATE deleted_images SET vhost=( SELECT vhost FROM events WHERE event=deleted_images.event );

-- and shadow_files
ALTER TABLE shadow_files ADD COLUMN vhost varchar;
UPDATE shadow_files SET vhost=( SELECT vhost FROM events WHERE event=shadow_files.event );
ALTER TABLE shadow_files ALTER COLUMN vhost SET NOT NULL;

-- Drop the old index
ALTER TABLE events DROP CONSTRAINT events_pkey CASCADE;

-- Finally, fix up some unique constraints
DROP INDEX unique_filenames;
CREATE UNIQUE INDEX unique_filenames ON images (vhost,event,filename);

ALTER TABLE fake_files DROP CONSTRAINT fake_files_pkey;
ALTER TABLE fake_files ADD PRIMARY KEY (vhost,event,filename);

-- And some old sillyness from waaay back (the MySQL days)
ALTER TABLE deleted_images ALTER COLUMN event TYPE varchar;
ALTER TABLE deleted_images ALTER COLUMN filename TYPE varchar;
ALTER TABLE deleted_images ALTER COLUMN uploadedby TYPE varchar;
ALTER TABLE deleted_images ALTER COLUMN takenby TYPE varchar;

ALTER TABLE fake_files ALTER COLUMN event TYPE varchar;
ALTER TABLE fake_files ALTER COLUMN filename TYPE varchar;

ALTER TABLE shadow_files ALTER COLUMN event TYPE varchar;
ALTER TABLE shadow_files ALTER COLUMN filename TYPE varchar;

ALTER TABLE users ALTER COLUMN username TYPE varchar;
ALTER TABLE users ALTER COLUMN vhost TYPE varchar;

-- Reclaim space from the old indexes
VACUUM FULL ANALYZE;

