CREATE TABLE events (
    id character varying NOT NULL PRIMARY KEY,
    date character varying NOT NULL,
    name character varying NOT NULL,
    vhost character varying NOT NULL,
    last_update timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- In a separate table to avoid deadlocks.
CREATE TABLE last_picture_cache ( 
   event varchar PRIMARY KEY references events ( id ),
   last_picture timestamp without time zone
);

CREATE TABLE images (
    id serial NOT NULL PRIMARY KEY,
    event character varying NOT NULL REFERENCES events(id),
    filename character varying NOT NULL,
    width integer DEFAULT -1 NOT NULL,
    height integer DEFAULT -1 NOT NULL,
    uploadedby character varying NOT NULL,
    date timestamp without time zone,
    takenby character varying NOT NULL,
    selected boolean DEFAULT false
);
CREATE UNIQUE INDEX unique_filenames ON images USING btree (event, filename);

CREATE TABLE deleted_images (
    id integer NOT NULL,
    event character varying(32) NOT NULL,
    filename character varying(255) NOT NULL,
    width integer DEFAULT -1 NOT NULL,
    height integer DEFAULT -1 NOT NULL,
    uploadedby character varying(32),
    date timestamp without time zone,
    takenby character varying(32) NOT NULL,
    selected boolean
);

CREATE TABLE fake_files (
    event character varying(32) NOT NULL REFERENCES events(id),
    filename character varying(255) NOT NULL,
    expires_at timestamp without time zone NOT NULL,

    PRIMARY KEY ( event, filename )
);

CREATE TABLE shadow_files (
    event character varying(32) NOT NULL,
    filename character varying(255) NOT NULL,
    id integer NOT NULL,
    expires_at timestamp without time zone NOT NULL
);

CREATE TABLE users (
    username character varying(32) NOT NULL,
    sha1password character(28) NOT NULL,
    vhost character varying(32) NOT NULL
);

CREATE TABLE exif_info (
    image integer NOT NULL REFERENCES images (id),
    tag varchar NOT NULL,
    value varchar NOT NULL,

    PRIMARY KEY ( image, tag )
);
    

GRANT INSERT ON TABLE deleted_images TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE events TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE fake_files TO pr0n;
GRANT SELECT,UPDATE ON TABLE images_id_seq TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE images TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE shadow_files TO pr0n;
GRANT SELECT ON TABLE users TO pr0n;
GRANT SELECT,INSERT,DELETE ON TABLE exif_info TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE last_picture_cache TO pr0n;
