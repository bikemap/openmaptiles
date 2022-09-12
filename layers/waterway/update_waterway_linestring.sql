DROP TRIGGER IF EXISTS trigger_store_waterway_linestring ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_flag_waterway_linestring ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_store ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_flag ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_refresh ON waterway_linestring.updates;

CREATE SCHEMA IF NOT EXISTS waterway_linestring;

CREATE TABLE IF NOT EXISTS waterway_linestring.osm_ids
(
    osm_id bigint PRIMARY KEY
);


CREATE OR REPLACE FUNCTION update_waterway_linestring(full_update bool) RETURNS void AS $$
BEGIN
    UPDATE osm_waterway_linestring
    SET tags = update_tags(tags, geometry)
    WHERE (
        full_update OR
        EXISTS(
            SELECT NULL
            FROM waterway_linestring.osm_ids
            WHERE waterway_linestring.osm_ids.osm_id = osm_waterway_linestring.osm_id
        )
    );
END;
$$ LANGUAGE plpgsql;

SELECT update_waterway_linestring(TRUE);

-- Handle updates

CREATE OR REPLACE FUNCTION waterway_linestring.store() RETURNS trigger AS
$$
BEGIN
    INSERT INTO waterway_linestring.osm_ids VALUES (NEW.osm_id) ON CONFLICT (osm_id) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS waterway_linestring.updates
(
    id serial PRIMARY KEY,
    t text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION waterway_linestring.flag() RETURNS trigger AS
$$
BEGIN
    INSERT INTO waterway_linestring.updates(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION waterway_linestring.refresh() RETURNS trigger AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh waterway_linestring';

    PERFORM update_waterway_linestring(FALSE);

    -- noinspection SqlWithoutWhere
    DELETE FROM waterway_linestring.osm_ids;
    -- noinspection SqlWithoutWhere
    DELETE FROM waterway_linestring.updates;

    RAISE LOG 'Refresh waterway_linestring done in %', age(clock_timestamp(), t);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_store_waterway_linestring
    AFTER INSERT OR UPDATE
    ON osm_waterway_linestring
    FOR EACH ROW
EXECUTE PROCEDURE waterway_linestring.store();

CREATE TRIGGER trigger_flag_waterway_linestring
    AFTER INSERT OR UPDATE
    ON osm_waterway_linestring
    FOR EACH STATEMENT
EXECUTE PROCEDURE waterway_linestring.flag();

CREATE CONSTRAINT TRIGGER trigger_refresh
    AFTER INSERT
    ON waterway_linestring.updates
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE waterway_linestring.refresh();
