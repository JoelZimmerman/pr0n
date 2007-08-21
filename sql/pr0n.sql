CREATE TABLE events (
    event character varying NOT NULL,
    "date" character varying NOT NULL,
    name character varying NOT NULL,
    vhost character varying NOT NULL,
    last_update timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (vhost, event)
);

-- In a separate table to avoid deadlocks.
CREATE TABLE last_picture_cache ( 
   vhost varchar NOT NULL,
   event varchar NOT NULL,
   last_picture timestamp without time zone,

   PRIMARY KEY (vhost,event),
   FOREIGN KEY (vhost,event) REFERNECES events(vhost,event)
);

CREATE TABLE images (
    id serial NOT NULL PRIMARY KEY,
    vhost character varying NOT NULL,
    event character varying NOT NULL,
    filename character varying NOT NULL,
    width integer,
    height integer,
    uploadedby character varying NOT NULL,
    "date" timestamp without time zone,
    takenby character varying NOT NULL,
    selected boolean DEFAULT false,
    model character varying,
    lens character varying,

    FOREIGN KEY (vhost,event) REFERENCES events (vhost,event)
);
CREATE UNIQUE INDEX unique_filenames ON images USING btree (vhost, event, filename);

CREATE TABLE deleted_images (
    id integer NOT NULL,
    vhost character varying,
    event character varying NOT NULL,
    filename character varying NOT NULL,
    width integer,
    height integer,
    uploadedby character varying,
    "date" timestamp without time zone,
    takenby character varying NOT NULL,
    selected boolean
);

CREATE TABLE fake_files (
    vhost character varying NOT NULL,
    event character varying NOT NULL,
    filename character varying NOT NULL,
    expires_at timestamp without time zone NOT NULL,

    PRIMARY KEY ( vhost, event, filename ),
    FOREIGN KEY (vhost,event) REFERENCES events (vhost,event)
);

CREATE TABLE shadow_files (
    vhost character varying NOT NULL,
    event character varying NOT NULL,
    filename character varying NOT NULL,
    id integer NOT NULL,
    expires_at timestamp without time zone NOT NULL
);

CREATE TABLE users (
    username character varying NOT NULL,
    sha1password character(28) NOT NULL,
    vhost character varying NOT NULL
);

-- Mainly used for manual queries -- usually too slow to be very useful
-- for web views in the long run.
CREATE TABLE exif_info (
    image integer NOT NULL REFERENCES images (id) ON DELETE CASCADE,
    key varchar NOT NULL,
    value varchar NOT NULL,

    PRIMARY KEY ( image, key )
);

CREATE INDEX exif_info_key ON exif_info ( key );
CLUSTER exif_info_key ON exif_info;

CREATE TABLE tags (
    image integer NOT NULL REFERENCES images (id) ON DELETE CASCADE,
    tag varchar NOT NULL,

    PRIMARY KEY ( image, tag )
);
CREATE INDEX tags_tag ON tags ( tag );

GRANT INSERT ON TABLE deleted_images TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE events TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE fake_files TO pr0n;
GRANT SELECT,UPDATE ON TABLE images_id_seq TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE images TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE shadow_files TO pr0n;
GRANT SELECT ON TABLE users TO pr0n;
GRANT SELECT,INSERT,DELETE ON TABLE exif_info TO pr0n;
GRANT SELECT,INSERT,DELETE ON TABLE tags TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE last_picture_cache TO pr0n;
