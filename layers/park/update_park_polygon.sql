DROP TRIGGER IF EXISTS tigger_store ON osm_park_polygon;
DROP TRIGGER IF EXISTS tigger_flag ON osm_park_polygon;
DROP TRIGGER IF EXISTS tigger_refresh ON park_polygon.updates;

ALTER TABLE osm_park_polygon
    ADD COLUMN IF NOT EXISTS geometry_point geometry;
ALTER TABLE osm_park_polygon_gen_z13
    ADD COLUMN IF NOT EXISTS geometry_point geometry;
ALTER TABLE osm_park_polygon_gen_z12
    ADD COLUMN IF NOT EXISTS geometry_point geometry;
ALTER TABLE osm_park_polygon_gen_z11
    ADD COLUMN IF NOT EXISTS geometry_point geometry;
ALTER TABLE osm_park_polygon_gen_z10
    ADD COLUMN IF NOT EXISTS geometry_point geometry;
ALTER TABLE osm_park_polygon_gen_z9
    ADD COLUMN IF NOT EXISTS geometry_point geometry;
ALTER TABLE osm_park_polygon_gen_z8
    ADD COLUMN IF NOT EXISTS geometry_point geometry;
ALTER TABLE osm_park_polygon_gen_z7
    ADD COLUMN IF NOT EXISTS geometry_point geometry;
ALTER TABLE osm_park_polygon_gen_z6
    ADD COLUMN IF NOT EXISTS geometry_point geometry;
ALTER TABLE osm_park_polygon_gen_z5
    ADD COLUMN IF NOT EXISTS geometry_point geometry;

CREATE SCHEMA IF NOT EXISTS park_polygon;

CREATE TABLE IF NOT EXISTS park_polygon.osm_ids
(
    osm_id bigint PRIMARY KEY
);

-- etldoc:  osm_park_polygon_gen_z4 -> osm_park_polygon_dissolve_z4
DROP MATERIALIZED VIEW IF EXISTS osm_park_polygon_dissolve_z4 CASCADE;
CREATE MATERIALIZED VIEW osm_park_polygon_dissolve_z4 AS
(
  SELECT min(osm_id) AS osm_id,
         ST_Union(geometry) AS geometry
  FROM (
        SELECT ST_ClusterDBSCAN(geometry, 0, 1) OVER() AS cluster,
               osm_id,
               geometry
        FROM osm_park_polygon_gen_z4
  ) park_cluster
  GROUP BY cluster
);
CREATE UNIQUE INDEX IF NOT EXISTS osm_park_polygon_dissolve_idx ON osm_park_polygon_dissolve_z4 (osm_id);


-- etldoc:  osm_park_polygon ->  osm_park_polygon
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z13
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z12
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z11
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z10
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z9
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z8
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z7
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z6
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z5
-- etldoc:  osm_park_polygon ->  osm_park_polygon_gen_z4
CREATE OR REPLACE FUNCTION update_osm_park_polygon(full_update bool) RETURNS void AS
$$
BEGIN
    UPDATE osm_park_polygon
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(SELECT NULL FROM park_polygon.osm_ids WHERE park_polygon.osm_ids.osm_id = osm_park_polygon.osm_id)
    );

    UPDATE osm_park_polygon_gen_z13
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z13.osm_id
        )
    );

    UPDATE osm_park_polygon_gen_z12
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z12.osm_id
        )
    );

    UPDATE osm_park_polygon_gen_z11
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z11.osm_id
        )
    );

    UPDATE osm_park_polygon_gen_z10
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z10.osm_id
        )
    );

    UPDATE osm_park_polygon_gen_z9
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z9.osm_id
        )
    );

    UPDATE osm_park_polygon_gen_z8
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z8.osm_id
        )
    );

    UPDATE osm_park_polygon_gen_z7
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z7.osm_id
        )
    );

    UPDATE osm_park_polygon_gen_z6
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z6.osm_id
        )
    );

    UPDATE osm_park_polygon_gen_z5
    SET tags           = update_tags(tags, geometry),
        geometry_point = st_centroid(geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z5.osm_id
        )
    );

    UPDATE osm_park_polygon_gen_z4
    SET tags = update_tags(tags, geometry)
    WHERE (
        full_update IS TRUE OR
        EXISTS(
            SELECT NULL
            FROM park_polygon.osm_ids
            WHERE park_polygon.osm_ids.osm_id = osm_park_polygon_gen_z4.osm_id
        )
    );
END;
$$ LANGUAGE plpgsql;

SELECT update_osm_park_polygon(TRUE);

-- Indexes for queries originating from update_osm_park_polygon() function
CREATE INDEX IF NOT EXISTS osm_park_polygon_osm_id_idx ON osm_park_polygon (osm_id);

-- Geometry Indexes
CREATE INDEX IF NOT EXISTS osm_park_polygon_point_geom_idx ON osm_park_polygon USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z13_point_geom_idx ON osm_park_polygon_gen_z13 USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z12_point_geom_idx ON osm_park_polygon_gen_z12 USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z11_point_geom_idx ON osm_park_polygon_gen_z11 USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z10_point_geom_idx ON osm_park_polygon_gen_z10 USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z9_point_geom_idx ON osm_park_polygon_gen_z9 USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z8_point_geom_idx ON osm_park_polygon_gen_z8 USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z7_point_geom_idx ON osm_park_polygon_gen_z7 USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z6_point_geom_idx ON osm_park_polygon_gen_z6 USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z5_point_geom_idx ON osm_park_polygon_gen_z5 USING gist (geometry_point);
CREATE INDEX IF NOT EXISTS osm_park_polygon_gen_z4_polygon_geom_idx ON osm_park_polygon_gen_z4 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_park_polygon_dissolve_z4_polygon_geom_idx ON osm_park_polygon_dissolve_z4 USING gist (geometry);

CREATE OR REPLACE FUNCTION park_polygon.store() RETURNS TRIGGER AS $$
    BEGIN
        INSERT INTO park_polygon.osm_ids VALUES (NEW.osm_id) ON CONFLICT (osm_id) DO NOTHING;
        RETURN NULL;
    END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS park_polygon.updates
(
    id serial PRIMARY KEY,
    t  text,
    UNIQUE (t)
);

CREATE OR REPLACE FUNCTION park_polygon.flag() RETURNS trigger AS
$$
BEGIN
    INSERT INTO park_polygon.updates(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION park_polygon.refresh() RETURNS trigger AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh park_polygon';

    -- Analyze tracking and source tables before performing update
    ANALYZE park_polygon.osm_ids;
    ANALYZE osm_park_polygon;
    ANALYZE osm_park_polygon_gen_z13;
    ANALYZE osm_park_polygon_gen_z12;
    ANALYZE osm_park_polygon_gen_z11;
    ANALYZE osm_park_polygon_gen_z10;
    ANALYZE osm_park_polygon_gen_z9;
    ANALYZE osm_park_polygon_gen_z8;
    ANALYZE osm_park_polygon_gen_z7;
    ANALYZE osm_park_polygon_gen_z6;
    ANALYZE osm_park_polygon_gen_z5;
    ANALYZE osm_park_polygon_gen_z4;

    PERFORM update_osm_park_polygon(FALSE);
    REFRESH MATERIALIZED VIEW osm_park_polygon_dissolve_z4;

    -- noinspection SqlWithoutWhere
    DELETE FROM park_polygon.osm_ids;
    -- noinspection SqlWithoutWhere
    DELETE FROM park_polygon.updates;

    RAISE LOG 'Refresh park_polygon done in %', age(clock_timestamp(), t);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tigger_store
    AFTER INSERT OR UPDATE
    ON osm_park_polygon
    FOR EACH ROW
EXECUTE PROCEDURE park_polygon.store();

CREATE TRIGGER trigger_flag
    AFTER INSERT OR UPDATE
    ON osm_park_polygon
    FOR EACH STATEMENT
EXECUTE PROCEDURE park_polygon.flag();

CREATE CONSTRAINT TRIGGER trigger_refresh
    AFTER INSERT
    ON park_polygon.updates
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE park_polygon.refresh();
