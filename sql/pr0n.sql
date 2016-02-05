CREATE TABLE events (
    event character varying NOT NULL,
    "date" character varying NOT NULL,
    name character varying NOT NULL,
    vhost character varying NOT NULL,
    hidden boolean NOT NULL DEFAULT false,

    PRIMARY KEY (vhost, event)
);

-- In a separate table to avoid deadlocks.
CREATE TABLE last_picture_cache ( 
   vhost varchar NOT NULL,
   event varchar NOT NULL,
   last_picture timestamp without time zone,
   last_update timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,

   PRIMARY KEY (vhost,event),
   FOREIGN KEY (vhost,event) REFERENCES events(vhost,event)
);

CREATE SEQUENCE imageid_seq;

CREATE TABLE images (
    id integer DEFAULT nextval('imageid_seq') NOT NULL PRIMARY KEY,
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
    is_render boolean NOT NULL DEFAULT false,  -- Is this a render of another picture? (If so, don't show it separately.)
    render_id integer,  -- If not NULL, show this picture instead of ourselves for all JPEG-creation purposes.

    FOREIGN KEY (vhost,event) REFERENCES events (vhost,event),
    FOREIGN KEY (vhost,event,render_id) REFERENCES images (vhost,event,id),

    -- Redundant with the primary key, but the foreign key needs it.
    UNIQUE (vhost,event,id),

    CHECK (NOT (is_render AND (render_id IS NOT NULL)))
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
    selected boolean,
    model character varying,
    lens character varying
    is_render boolean NOT NULL,
    render_id integer,
);

CREATE TABLE users (
    username character varying NOT NULL,
    vhost character varying NOT NULL,
    cryptpassword character varying NOT NULL
);

-- Mainly used for manual queries -- usually too slow to be very useful
-- for web views in the long run.
CREATE TABLE exif_info (
    image integer NOT NULL REFERENCES images (id) ON DELETE CASCADE,
    key varchar NOT NULL,
    value varchar NOT NULL,

    PRIMARY KEY ( image, key )
);

CLUSTER exif_info_pkey ON exif_info;

GRANT INSERT ON TABLE deleted_images TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE events TO pr0n;
GRANT SELECT,UPDATE ON TABLE imageid_seq TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE images TO pr0n;
GRANT SELECT,UPDATE ON TABLE users TO pr0n;
GRANT SELECT,INSERT,DELETE ON TABLE exif_info TO pr0n;
GRANT INSERT,SELECT,UPDATE,DELETE ON TABLE last_picture_cache TO pr0n;
