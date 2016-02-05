set work_mem to 1048576;

alter table images add column is_render boolean NOT NULL DEFAULT false;
alter table images add column render_id integer;
CREATE UNIQUE INDEX unique_id_for_render ON images USING btree (vhost, event, id);
alter table images add foreign key (render_id,vhost,event) REFERENCES images (id,vhost,event);
alter table images add check (NOT (is_render AND (render_id IS NOT NULL)));

alter table deleted_images add column is_render boolean NOT NULL DEFAULT false;
alter table deleted_images add column render_id integer;

drop index exif_info_key;
alter table exif_info drop constraint exif_info_pkey;
alter table exif_info add primary key ( image, key );
