alter table images add column is_render boolean NOT NULL DEFAULT false;
alter table images add column render_id integer;
CREATE UNIQUE INDEX unique_id_for_render ON images USING btree (vhost, event, id);
alter table images add foreign key (render_id,vhost,event) REFERENCES images (id,vhost,event);
alter table images add check (NOT (is_render AND (render_id IS NOT NULL)));

alter table deleted_images add column is_render boolean NOT NULL DEFAULT false;
alter table deleted_images add column render_id integer;
