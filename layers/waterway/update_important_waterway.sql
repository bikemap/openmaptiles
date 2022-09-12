DROP TRIGGER IF EXISTS trigger_important_waterway_linestring_store ON osm_important_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_store_waterway_linestring ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_flag_waterway_linestring ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_store ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_flag ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_refresh ON waterway_important.updates;

-- We merge the waterways by name like the highways
-- This helps to drop not important rivers (since they do not have a name)
-- and also makes it possible to filter out too short rivers

CREATE INDEX IF NOT EXISTS osm_waterway_linestring_waterway_partial_idx
    ON osm_waterway_linestring (name, waterway, ST_IsValid(geometry))
    WHERE name <> ''
      AND waterway = 'river'
      AND ST_IsValid(geometry);

CREATE TABLE IF NOT EXISTS osm_important_waterway_linestring (
    id SERIAL,
    geometry geometry('LineString'),
    parent_osm_ids bigint[],
    name varchar,
    name_en varchar,
    name_de varchar,
    tags hstore
);

CREATE TABLE IF NOT EXISTS osm_important_waterway_linestring_gen_z11
(LIKE osm_important_waterway_linestring);
ALTER TABLE osm_important_waterway_linestring_gen_z11 DROP COLUMN IF EXISTS parent_osm_ids;

CREATE TABLE IF NOT EXISTS osm_important_waterway_linestring_gen_z10
(LIKE osm_important_waterway_linestring_gen_z11);

CREATE TABLE IF NOT EXISTS osm_important_waterway_linestring_gen_z9
(LIKE osm_important_waterway_linestring_gen_z10);

TRUNCATE osm_important_waterway_linestring;

-- etldoc: osm_waterway_linestring ->  osm_important_waterway_linestring
INSERT INTO osm_important_waterway_linestring (geometry, parent_osm_ids, name, name_en, name_de, tags)
SELECT (ST_Dump(ST_LineMerge(ST_Collect(geometry)))).geom AS geometry,
       array_agg(osm_id) as parent_osm_ids,
       name,
       name_en,
       name_de,
       slice_language_tags(tags) AS tags
FROM (
    SELECT *,
          ST_ClusterDBSCAN(geometry, 0, 1) OVER (
              PARTITION BY name, name_en, name_de, slice_language_tags(tags)
          ) AS cluster,
          rank() OVER (
              ORDER BY name, name_en, name_de, slice_language_tags(tags)
          ) as cluster_id
    FROM osm_waterway_linestring
    WHERE name <> '' AND waterway = 'river' AND ST_IsValid(geometry)
) q
GROUP BY cluster_id, cluster, name, name_en, name_de, slice_language_tags(tags);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_name_network' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_important_waterway_linestring ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_important_waterway_linestring_gen_z11' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_important_waterway_linestring_gen_z11 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_important_waterway_linestring_gen_z10' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_important_waterway_linestring_gen_z10 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_important_waterway_linestring_gen_z9' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_important_waterway_linestring_gen_z9 ADD PRIMARY KEY (id);
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_geometry_idx
    ON osm_important_waterway_linestring USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_parent_osm_ids_idx
    ON osm_important_waterway_linestring USING gin (parent_osm_ids);
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_update_idx
    ON osm_important_waterway_linestring (id, ST_Length(geometry)) WHERE ST_Length(geometry) > 1000;

CREATE SCHEMA IF NOT EXISTS waterway_important;

CREATE TABLE IF NOT EXISTS waterway_important.changes_z9_z10_z11
(
    is_old boolean,
    id integer,
    PRIMARY KEY (id, is_old)
);

CREATE OR REPLACE FUNCTION insert_important_waterway_linestring_gen(full_update bool) RETURNS void AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh waterway z9 z10 z11';

    ANALYZE VERBOSE waterway_important.changes_z9_z10_z11;

    DELETE FROM osm_important_waterway_linestring_gen_z11
    USING waterway_important.changes_z9_z10_z11
    WHERE full_update IS TRUE OR (
        waterway_important.changes_z9_z10_z11.is_old IS TRUE AND
        waterway_important.changes_z9_z10_z11.id = osm_important_waterway_linestring_gen_z11.id
    );

    -- etldoc: osm_important_waterway_linestring -> osm_important_waterway_linestring_gen_z11
    INSERT INTO osm_important_waterway_linestring_gen_z11 (geometry, id, name, name_en, name_de, tags)
    SELECT ST_Simplify(geometry, ZRes(12)) AS geometry,
        id,
        name,
        name_en,
        name_de,
        tags
    FROM osm_important_waterway_linestring
    WHERE (
        full_update OR
        EXISTS(
            SELECT NULL
            FROM waterway_important.changes_z9_z10_z11
            WHERE waterway_important.changes_z9_z10_z11.is_old IS FALSE AND
                  waterway_important.changes_z9_z10_z11.id = osm_important_waterway_linestring.id
        )
    ) AND ST_Length(geometry) > 1000
    ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, name = excluded.name, name_en = excluded.name_en,
                                   name_de = excluded.name_de, tags = excluded.tags;

    ANALYZE VERBOSE osm_important_waterway_linestring_gen_z11;

    DELETE FROM osm_important_waterway_linestring_gen_z10
    USING waterway_important.changes_z9_z10_z11
    WHERE full_update IS TRUE OR (
        waterway_important.changes_z9_z10_z11.is_old IS TRUE AND
        waterway_important.changes_z9_z10_z11.id = osm_important_waterway_linestring_gen_z10.id
    );

    -- etldoc: osm_important_waterway_linestring_gen_z11 -> osm_important_waterway_linestring_gen_z10
    INSERT INTO osm_important_waterway_linestring_gen_z10 (geometry, id, name, name_en, name_de, tags)
    SELECT ST_Simplify(geometry, ZRes(11)) AS geometry,
        id,
        name,
        name_en,
        name_de,
        tags
    FROM osm_important_waterway_linestring_gen_z11
    WHERE (
        full_update OR
        EXISTS(
            SELECT NULL
            FROM waterway_important.changes_z9_z10_z11
            WHERE waterway_important.changes_z9_z10_z11.is_old IS FALSE AND
                  waterway_important.changes_z9_z10_z11.id = osm_important_waterway_linestring_gen_z11.id
        )
    ) AND ST_Length(geometry) > 4000
    ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, name = excluded.name, name_en = excluded.name_en,
                                   name_de = excluded.name_de, tags = excluded.tags;

    ANALYZE VERBOSE osm_important_waterway_linestring_gen_z10;

    DELETE FROM osm_important_waterway_linestring_gen_z9
    USING waterway_important.changes_z9_z10_z11
    WHERE full_update IS TRUE OR (
        waterway_important.changes_z9_z10_z11.is_old IS TRUE AND
        waterway_important.changes_z9_z10_z11.id = osm_important_waterway_linestring_gen_z9.id
    );

    -- etldoc: osm_important_waterway_linestring_gen_z10 -> osm_important_waterway_linestring_gen_z9
    INSERT INTO osm_important_waterway_linestring_gen_z9 (geometry, id, name, name_en, name_de, tags)
    SELECT ST_Simplify(geometry, ZRes(10)) AS geometry,
        id,
        name,
        name_en,
        name_de,
        tags
    FROM osm_important_waterway_linestring_gen_z10
    WHERE (
        full_update OR
        EXISTS(
            SELECT NULL
            FROM waterway_important.changes_z9_z10_z11
            WHERE waterway_important.changes_z9_z10_z11.is_old IS FALSE AND
                  waterway_important.changes_z9_z10_z11.id = osm_important_waterway_linestring_gen_z10.id
        )
    ) AND ST_Length(geometry) > 8000
    ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, name = excluded.name, name_en = excluded.name_en,
                                   name_de = excluded.name_de, tags = excluded.tags;

    ANALYZE VERBOSE osm_important_waterway_linestring_gen_z9;

    DELETE FROM waterway_important.changes_z9_z10_z11;

    RAISE LOG 'Refresh waterway z9 z10 z11 done in %', age(clock_timestamp(), t);
END;
$$ LANGUAGE plpgsql;

TRUNCATE osm_important_waterway_linestring_gen_z11;
TRUNCATE osm_important_waterway_linestring_gen_z10;
TRUNCATE osm_important_waterway_linestring_gen_z9;

SELECT insert_important_waterway_linestring_gen(TRUE);

CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z11_geometry_idx
    ON osm_important_waterway_linestring_gen_z11 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z11_update_idx
    ON osm_important_waterway_linestring_gen_z11 (id, ST_Length(geometry))
    WHERE ST_Length(geometry) > 4000;

CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z10_geometry_idx
    ON osm_important_waterway_linestring_gen_z10 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z10_update_idx
    ON osm_important_waterway_linestring_gen_z10 (id, ST_Length(geometry))
    WHERE ST_Length(geometry) > 8000;

CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z9_geometry_idx
    ON osm_important_waterway_linestring_gen_z9 USING gist (geometry);


-- Handle updates

CREATE TABLE IF NOT EXISTS waterway_important.changes
(
    osm_id bigint,
    is_old boolean,
    PRIMARY KEY (is_old, osm_id)
);

CREATE INDEX IF NOT EXISTS waterway_important_changes_is_old_idx ON waterway_important.changes (is_old);

CREATE OR REPLACE FUNCTION waterway_important.store() RETURNS trigger AS
$$
BEGIN
    IF (tg_op IN ('DELETE', 'UPDATE')) AND OLD.name <> '' AND OLD.waterway = 'river' THEN
        INSERT INTO waterway_important.changes(is_old, osm_id)
        VALUES (TRUE, old.osm_id);
    END IF;
    IF (tg_op IN ('UPDATE', 'INSERT')) AND NEW.name <> '' AND NEW.waterway = 'river' THEN
        INSERT INTO waterway_important.changes(is_old, osm_id)
        VALUES (FALSE, new.osm_id);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION waterway_important.important_waterway_linestring_store() RETURNS trigger AS
$$
BEGIN
    IF (tg_op = 'DELETE') THEN
        INSERT INTO waterway_important.changes_z9_z10_z11 (is_old, id) VALUES (TRUE, old.id) ON CONFLICT DO NOTHING ;
    END IF;

    IF (tg_op = 'UPDATE' OR tg_op = 'INSERT') THEN
        INSERT INTO waterway_important.changes_z9_z10_z11 (is_old, id) VALUES (FALSE, new.id) ON CONFLICT DO NOTHING;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS waterway_important.updates
(
    id serial PRIMARY KEY,
    t text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION waterway_important.flag() RETURNS trigger AS
$$
BEGIN
    INSERT INTO waterway_important.updates(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION waterway_important.refresh() RETURNS trigger AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh waterway';

    -- REFRESH osm_important_waterway_linestring

    ANALYZE VERBOSE waterway_important.changes;
    ANALYZE VERBOSE osm_waterway_linestring;

    CREATE TEMPORARY TABLE old_changes AS
    SELECT m.id, m.parent_osm_ids
    FROM osm_important_waterway_linestring m
    WHERE EXISTS(
        SELECT NULL
        FROM waterway_important.changes c
        WHERE c.is_old IS TRUE AND m.parent_osm_ids && ARRAY[c.osm_id]::bigint[]
    );

    CREATE INDEX ON old_changes (id);
    ANALYZE VERBOSE old_changes;

    CREATE TEMPORARY TABLE all_changes AS
    SELECT unnest(old_changes.parent_osm_ids) AS osm_id
    FROM old_changes
    UNION
    SELECT osm_id FROM waterway_important.changes WHERE is_old IS FALSE
    ORDER BY osm_id;

    CREATE INDEX ON all_changes (osm_id);
    ANALYZE VERBOSE all_changes;

    CREATE TEMPORARY TABLE updated_important_waterway_linestrings AS
    WITH changed_linestrings AS (
        SELECT *
        FROM osm_waterway_linestring
        WHERE EXISTS(
            SELECT NULL
            FROM all_changes
            WHERE all_changes.osm_id = osm_waterway_linestring.osm_id
        ) AND (
            name <> '' AND waterway = 'river' AND ST_IsValid(geometry)
        )
    )
    SELECT q.*,
          ST_ClusterDBSCAN(geometry, 0, 1) OVER (
              PARTITION BY name, name_en, name_de, tags
          ) AS cluster,
          rank() OVER (
              ORDER BY name, name_en, name_de, tags
          ) as cluster_id
    FROM (
        SELECT osm_id, NULL::INTEGER AS id, geometry, name, name_en, name_de, slice_language_tags(tags) as tags
        FROM changed_linestrings
        UNION ALL
        SELECT unnest(parent_osm_ids) AS osm_id, id, geometry, name, name_en, name_de, tags
        FROM osm_important_waterway_linestring
        WHERE EXISTS(
            SELECT NULL FROM changed_linestrings
            WHERE ST_Intersects(
                changed_linestrings.geometry, osm_important_waterway_linestring.geometry
            )
        )
    ) q;

    CREATE INDEX ON updated_important_waterway_linestrings (id);
    CREATE INDEX ON updated_important_waterway_linestrings (cluster_id, cluster);
    ANALYZE VERBOSE updated_important_waterway_linestrings;

    DELETE
    FROM osm_important_waterway_linestring m
    USING old_changes
    WHERE old_changes.id = m.id;

    DELETE
    FROM osm_important_waterway_linestring m
    USING updated_important_waterway_linestrings
    WHERE m.id = updated_important_waterway_linestrings.id;

    INSERT INTO osm_important_waterway_linestring (geometry, parent_osm_ids, name, name_en, name_de, tags)
    SELECT (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
           array_agg(osm_id) as parent_osm_ids,
           name,
           name_en,
           name_de,
           tags
    FROM updated_important_waterway_linestrings
    GROUP BY name, name_en, name_de, tags;

    DROP TABLE all_changes;
    DROP TABLE old_changes;
    DROP TABLE updated_important_waterway_linestrings;

    -- noinspection SqlWithoutWhere
    DELETE FROM waterway_important.changes;
    -- noinspection SqlWithoutWhere
    DELETE FROM waterway_important.updates;

    ANALYZE VERBOSE osm_important_waterway_linestring;

    RAISE LOG 'Refresh waterway done in %', age(clock_timestamp(), t);

    PERFORM insert_important_waterway_linestring_gen(FALSE);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_important_waterway_linestring_store
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_important_waterway_linestring
    FOR EACH ROW
EXECUTE PROCEDURE waterway_important.important_waterway_linestring_store();

CREATE TRIGGER trigger_store
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_waterway_linestring
    FOR EACH ROW
EXECUTE PROCEDURE waterway_important.store();

CREATE TRIGGER trigger_flag
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_waterway_linestring
    FOR EACH STATEMENT
EXECUTE PROCEDURE waterway_important.flag();

CREATE CONSTRAINT TRIGGER trigger_refresh
    AFTER INSERT
    ON waterway_important.updates
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE waterway_important.refresh();
