DROP TRIGGER IF EXISTS trigger_important_waterway_linestring_store ON osm_important_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_store_waterway_linestring ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_flag_waterway_linestring ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_store ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_flag_from_delete ON osm_waterway_linestring;
DROP TRIGGER IF EXISTS trigger_refresh ON waterway_important.updates;
DROP TRIGGER IF EXISTS trigger_flag_from_update_insert ON waterway_linestring.updates;

-- We merge the waterways by name like the highways
-- This helps to drop not important rivers (since they do not have a name)
-- and also makes it possible to filter out too short rivers

-- Index for filling and updating osm_important_waterway_linestring table
CREATE INDEX IF NOT EXISTS osm_waterway_linestring_waterway_update_idx
    ON osm_waterway_linestring (name, waterway, ST_IsValid(geometry));

CREATE TABLE IF NOT EXISTS osm_important_waterway_linestring (
    id SERIAL,
    geometry geometry('LineString'),
    source_ids bigint[],
    name varchar,
    name_en varchar,
    name_de varchar,
    tags hstore
);

-- Create osm_important_waterway_linestring_gen_z11 as a copy of osm_important_waterway_linestring but drop the
-- "source_ids" column. This can be done because z10 and z9 tables are only simplified and not merged, therefore
-- relations to sources are direct via the id column.
CREATE TABLE IF NOT EXISTS osm_important_waterway_linestring_gen_z11
(LIKE osm_important_waterway_linestring);
ALTER TABLE osm_important_waterway_linestring_gen_z11 DROP COLUMN IF EXISTS source_ids;

-- Create osm_important_waterway_linestring_gen_z10 as a copy of osm_important_waterway_linestring_gen_z11
CREATE TABLE IF NOT EXISTS osm_important_waterway_linestring_gen_z10
(LIKE osm_important_waterway_linestring_gen_z11);

-- Create osm_important_waterway_linestring_gen_z9 as a copy of osm_important_waterway_linestring_gen_z10
CREATE TABLE IF NOT EXISTS osm_important_waterway_linestring_gen_z9
(LIKE osm_important_waterway_linestring_gen_z10);

-- Create OneToMany-Relation-Table storing relations of a Merged-LineString in table
-- osm_important_waterway_linestring to Source-LineStrings from table osm_waterway_linestring
CREATE TABLE IF NOT EXISTS osm_important_waterway_linestring_source_ids(
    id int,
    source_id bigint,
    PRIMARY KEY (id, source_id)
);

-- Create temporary Merged-LineString to Source-LineStrings-ID table to temporarily store relations before they have
-- been intersected
CREATE TEMPORARY TABLE initial_osm_important_waterway_linestring_source_ids
(LIKE osm_important_waterway_linestring_source_ids INCLUDING INDEXES);

-- Ensure tables are emtpy if they haven't been created
TRUNCATE osm_important_waterway_linestring;
TRUNCATE osm_important_waterway_linestring_source_ids;

-- etldoc: osm_waterway_linestring ->  osm_important_waterway_linestring
WITH inserted_linestrings AS (
    -- Merge LineStrings from osm_waterway_linestring by grouping them and creating intersecting
    -- clusters of each group via ST_ClusterDBSCAN
    INSERT INTO osm_important_waterway_linestring (geometry, source_ids, name, name_en, name_de, tags)
    SELECT (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
           -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the geometries
           -- to merge. https://postgis.net/docs/ST_Union.html
           -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString
           -- if more than two LineStrings form an intersection or no intersection could be found.
           -- https://postgis.net/docs/ST_LineMerge.html
           -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
           -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
           array_agg(osm_id) as source_ids,
           name,
           name_en,
           name_de,
           slice_language_tags(tags) AS tags
    FROM (
        SELECT *,
               -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points to 1.
               -- https://postgis.net/docs/ST_ClusterDBSCAN.html
               ST_ClusterDBSCAN(geometry, 0, 1) OVER (
                   PARTITION BY name, name_en, name_de, slice_language_tags(tags)
               ) AS cluster,
               -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition starting at 0.
               -- This leads to clusters having the same ID across multiple partitions therefore we generate a
               -- Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the partition columns.
               DENSE_RANK() OVER (ORDER BY name, name_en, name_de, slice_language_tags(tags)) as cluster_group
        FROM osm_waterway_linestring
        WHERE name <> '' AND waterway = 'river' AND ST_IsValid(geometry)
    ) q
    GROUP BY cluster_group, cluster, name, name_en, name_de, slice_language_tags(tags)
    RETURNING id, source_ids
)
-- Store OSM-IDs of Source-LineStrings
INSERT INTO initial_osm_important_waterway_linestring_source_ids (id, source_id)
SELECT id, unnest(source_ids) AS source_id
FROM inserted_linestrings
ON CONFLICT (id, source_id) DO NOTHING;

-- Geometry Index
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_geometry_idx
    ON osm_important_waterway_linestring USING gist (geometry);

-- Create Primary-Keys for osm_important_waterway_linestring and osm_important_waterway_linestring_gen_z11/z10/z9 tables
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_important_waterway_linestring' AND constraint_type = 'PRIMARY KEY'
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

-- Create index on id columns and analyze the initial Merged-LineString to Source-LineStrings-ID Relations table to
-- speed up subsequent queries
CREATE INDEX ON initial_osm_important_waterway_linestring_source_ids (id, source_id);
ANALYZE initial_osm_important_waterway_linestring_source_ids;

-- Index for filling and updating osm_important_waterway_linestring table
CREATE INDEX IF NOT EXISTS osm_waterway_linestring_osm_id_idx ON osm_waterway_linestring (osm_id);

-- Store OSM-IDs of Source-LineStrings by intersecting Merged-LineStrings with their sources. This required because
-- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString if
-- more than two LineStrings form an intersection or no intersection could be found.
-- Execute after indexes have been created on osm_transportation_merge_linestring_gen_z11 to improve performance
INSERT INTO osm_important_waterway_linestring_source_ids (id, source_id)
SELECT m.id, source_id
FROM osm_important_waterway_linestring m, initial_osm_important_waterway_linestring_source_ids s
WHERE (
    EXISTS(
        SELECT NULL
        FROM osm_waterway_linestring
        WHERE m.id = s.id AND
              osm_waterway_linestring.osm_id = s.source_id AND
              ST_Intersects(osm_waterway_linestring.geometry, m.geometry)
    )
) ON CONFLICT (id, source_id) DO NOTHING;

-- Drop temporary tables early to save resources
DROP TABLE initial_osm_important_waterway_linestring_source_ids;

-- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations table
-- Execute after indexes have been created on osm_transportation_merge_linestring_gen_z11 to improve performance
UPDATE osm_important_waterway_linestring SET source_ids = q.source_ids
FROM (
    SELECT id, array_agg(source_id) AS source_ids
    FROM osm_important_waterway_linestring_source_ids
    GROUP BY id
) q
WHERE osm_important_waterway_linestring.id = q.id;

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

    -- Analyze tracking and source tables before performing update
    ANALYZE waterway_important.changes_z9_z10_z11;
    ANALYZE osm_important_waterway_linestring;

    -- Remove entries which have been deleted from source table
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

    -- Analyze source table
    ANALYZE osm_important_waterway_linestring_gen_z11;

    -- Remove entries which have been deleted from source table
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

    -- Analyze source table
    ANALYZE osm_important_waterway_linestring_gen_z10;

    -- Remove entries which have been deleted from source table
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

    -- noinspection SqlWithoutWhere
    DELETE FROM waterway_important.changes_z9_z10_z11;

    RAISE LOG 'Refresh waterway z9 z10 z11 done in %', age(clock_timestamp(), t);
END;
$$ LANGUAGE plpgsql;

-- Ensure tables are emtpy if they haven't been created
TRUNCATE osm_important_waterway_linestring_gen_z11;
TRUNCATE osm_important_waterway_linestring_gen_z10;
TRUNCATE osm_important_waterway_linestring_gen_z9;

-- Indexes which can be utilized during full-update for queries originating from
-- insert_important_waterway_linestring_gen() function
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_update_idx
    ON osm_important_waterway_linestring (id, ST_Length(geometry));

SELECT insert_important_waterway_linestring_gen(TRUE);

-- Indexes for queries originating from insert_important_waterway_linestring_gen() function
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z11_update_idx
    ON osm_important_waterway_linestring_gen_z11 (id, ST_Length(geometry));
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z10_update_idx
    ON osm_important_waterway_linestring_gen_z10 (id, ST_Length(geometry));

-- Geometry Indexes
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z11_geometry_idx
    ON osm_important_waterway_linestring_gen_z11 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z10_geometry_idx
    ON osm_important_waterway_linestring_gen_z10 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_gen_z9_geometry_idx
    ON osm_important_waterway_linestring_gen_z9 USING gist (geometry);


-- Handle updates on
-- -- osm_waterway_linestring -> osm_important_waterway_linestring
-- -- osm_important_waterway_linestring -> osm_important_waterway_linestring_gen_z11
-- -- osm_important_waterway_linestring -> osm_important_waterway_linestring_gen_z10
-- -- osm_important_waterway_linestring -> osm_important_waterway_linestring_gen_z9

CREATE TABLE IF NOT EXISTS waterway_important.changes
(
    osm_id bigint,
    is_old boolean,
    PRIMARY KEY (is_old, osm_id)
);

-- Store IDs of changed elements from osm_waterway_linestring table.
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

-- Store IDs of changed elements from osm_important_waterway_linestring table.
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

    -- Analyze tracking and source tables before performing update
    ANALYZE waterway_important.changes;
    ANALYZE osm_waterway_linestring;

    -- Fetch updated and deleted Merged-LineString from relation-table filtering for each Merged-LineString which
    -- contains an updated Source-LineString.
    -- Additionally attach a list of Source-LineString-IDs to each Merged-LineString in order to unnest them later.
    CREATE TEMPORARY TABLE affected_merged_linestrings AS
    SELECT m.id, array_agg(source_id) AS source_ids
    FROM osm_important_waterway_linestring_source_ids m
    WHERE EXISTS(
        SELECT NULL
        FROM waterway_important.changes c
        WHERE c.is_old IS TRUE AND c.osm_id = m.source_id
    )
    GROUP BY id;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_merged_linestrings (id);
    ANALYZE affected_merged_linestrings;

    -- Delete all Merged-LineStrings which contained an updated or deleted Source-LineString
    DELETE
    FROM osm_important_waterway_linestring m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;
    DELETE
    FROM osm_important_waterway_linestring_source_ids m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;

    -- Analyze the tables affected by the delete-query in order to speed up subsequent queries
    ANALYZE osm_important_waterway_linestring;
    ANALYZE osm_important_waterway_linestring_source_ids;

    -- Create a table containing the IDs of all Source-LineStrings affected by this update
    CREATE TEMPORARY TABLE affected_source_linestrings AS
    -- Get Source-LineString-IDs of deleted or updated elements
    SELECT unnest(affected_merged_linestrings.source_ids) AS osm_id
    FROM affected_merged_linestrings
    UNION
    -- Get Source-LineString-IDs of inserted or updated elements
    SELECT osm_id FROM waterway_important.changes WHERE is_old IS FALSE
    ORDER BY osm_id;

    -- Drop temporary tables early to save resources
    DROP TABLE affected_merged_linestrings;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_source_linestrings (osm_id);
    ANALYZE affected_source_linestrings;

    -- Create a table containing all LineStrings which should be merged
    CREATE TEMPORARY TABLE linestrings_to_merge AS
    -- Add all Source-LineStrings affected by this update
    SELECT osm_id, NULL::INTEGER AS id, geometry, name, name_en, name_de, slice_language_tags(tags) as tags
    FROM osm_waterway_linestring
    WHERE EXISTS(
        SELECT NULL
        FROM affected_source_linestrings
        WHERE affected_source_linestrings.osm_id = osm_waterway_linestring.osm_id
    ) AND (
        name <> '' AND waterway = 'river' AND ST_IsValid(geometry)
    );

    -- Drop temporary tables early to save resources
    DROP TABLE affected_source_linestrings;

    -- Create index on geometry column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge USING GIST (geometry);
    ANALYZE linestrings_to_merge;

    -- Add all Merged-LineStrings intersecting with Source-LineStrings affected by this update
    INSERT INTO linestrings_to_merge
    SELECT unnest(source_ids) AS osm_id, id, geometry, name, name_en, name_de, tags
    FROM osm_important_waterway_linestring
    WHERE EXISTS(
        SELECT NULL FROM linestrings_to_merge
        WHERE ST_Intersects(
            linestrings_to_merge.geometry, osm_important_waterway_linestring.geometry
        )
    );

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge (id);
    ANALYZE linestrings_to_merge;

    -- Delete all Merged-LineStrings intersecting with Source-LineStrings affected by this update.
    -- We can use the linestrings_to_merge table since Source-LineStrings affected by this update and present in the
    -- table will have their ID-Column set to NULL by the previous query.
    DELETE
    FROM osm_important_waterway_linestring m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;
    DELETE
    FROM osm_important_waterway_linestring_source_ids m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;

    -- Create table containing all LineStrings to and create clusters of intersecting LineStrings partitioned by their
    -- groups
    CREATE TEMPORARY TABLE clustered_linestrings_to_merge AS
    SELECT *,
           -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points to 1.
           -- https://postgis.net/docs/ST_ClusterDBSCAN.html
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (PARTITION BY name, name_en, name_de, tags) AS cluster,
           -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition starting at 0.
           -- This leads to clusters having the same ID across multiple partitions therefore we generate a
           -- Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the partition columns.
           DENSE_RANK() OVER (ORDER BY name, name_en, name_de, tags) as cluster_group
    FROM linestrings_to_merge;

    -- Drop temporary tables early to save resources
    DROP TABLE linestrings_to_merge;

    -- Create index on cluster columns and analyze the created table to speed up subsequent queries
    CREATE INDEX ON clustered_linestrings_to_merge (cluster_group, cluster);
    ANALYZE clustered_linestrings_to_merge;

    -- Create temporary Merged-LineString to Source-LineStrings-ID table to temporarily store relations before they have
    -- been intersected
    CREATE TEMPORARY TABLE inserted_relations
    (LIKE osm_important_waterway_linestring_source_ids INCLUDING INDEXES);

    WITH inserted_linestrings AS (
        -- Merge LineStrings of each cluster and insert them
        INSERT INTO osm_important_waterway_linestring (geometry, source_ids, name, name_en, name_de, tags)
        SELECT (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
               -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the geometries
               -- to merge. https://postgis.net/docs/ST_Union.html
               -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString
               -- if more than two LineStrings form an intersection or no intersection could be found.
               -- https://postgis.net/docs/ST_LineMerge.html
               -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
               -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
               array_agg(osm_id) as source_ids,
               name,
               name_en,
               name_de,
               tags
        FROM clustered_linestrings_to_merge
        GROUP BY cluster_group, cluster, name, name_en, name_de, tags
        RETURNING id, source_ids
    )
    -- Store OSM-IDs of Source-LineStrings
    INSERT INTO osm_important_waterway_linestring_source_ids (id, source_id)
    SELECT id, unnest(source_ids) AS source_id
    FROM inserted_linestrings
    ON CONFLICT (id, source_id) DO NOTHING;

    -- Drop temporary tables early to save resources
    DROP TABLE clustered_linestrings_to_merge;

    -- Create index on id columns and analyze the inserted Merged-LineString to Source-LineStrings-ID Relations table to
    -- speed up subsequent queries
    CREATE INDEX ON inserted_relations (id, source_id);
    ANALYZE inserted_relations;

    -- Store OSM-IDs of Source-LineStrings by intersecting Merged-LineStrings with their sources. This required because
    -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString if
    -- more than two LineStrings form an intersection or no intersection could be found.
    -- Execute after indexes have been created on osm_transportation_merge_linestring_gen_z11 to improve performance
    WITH intersected_relations AS (
        INSERT INTO osm_important_waterway_linestring_source_ids (id, source_id)
        SELECT m.id, source_id
        FROM osm_important_waterway_linestring m, inserted_relations s
        WHERE (
            EXISTS(
                SELECT NULL
                FROM osm_waterway_linestring
                WHERE m.id = s.id AND
                      osm_waterway_linestring.osm_id = s.source_id AND
                      ST_Intersects(osm_waterway_linestring.geometry, m.geometry)
            )
        ) ON CONFLICT (id, source_id) DO NOTHING
        RETURNING id, source_id
    )
    -- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations
    -- table
    UPDATE osm_important_waterway_linestring SET source_ids = q.source_ids
    FROM (
        SELECT id, array_agg(source_id) AS source_ids
        FROM intersected_relations
        GROUP BY id
    ) q
    WHERE osm_important_waterway_linestring.id = q.id;

    -- Cleanup
    DROP TABLE inserted_relations;
    -- noinspection SqlWithoutWhere
    DELETE FROM waterway_important.changes;
    -- noinspection SqlWithoutWhere
    DELETE FROM waterway_important.updates;

    RAISE LOG 'Refresh waterway done in %', age(clock_timestamp(), t);

    -- Update z11, z10 and z9 tables
    PERFORM insert_important_waterway_linestring_gen(FALSE);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Indexes for queries originating from waterway_important.refresh() function
CREATE INDEX IF NOT EXISTS waterway_important_changes_is_old_idx ON waterway_important.changes (is_old);
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_source_ids_source_id_idx
    ON osm_important_waterway_linestring_source_ids (source_id);
CREATE INDEX IF NOT EXISTS osm_important_waterway_linestring_source_ids_id_idx
    ON osm_important_waterway_linestring_source_ids (id);
CREATE INDEX IF NOT EXISTS osm_waterway_linestring_osm_id_idx ON osm_waterway_linestring (osm_id);

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

-- waterway_important.refresh depends on waterway_linestring.refresh which will be triggered by INSERT and UPDATE
-- operations to the osm_waterway_linestring table and waterway_linestring.refresh in turn will trigger
-- waterway_important.refresh. (see below)
CREATE TRIGGER trigger_flag_from_delete
    AFTER DELETE
    ON osm_waterway_linestring
    FOR EACH STATEMENT
EXECUTE PROCEDURE waterway_important.flag();

-- waterway_important.refresh depends on waterway_linestring.refresh which will which will be triggered by INSERT and
-- UPDATE operations to the osm_waterway_linestring table and executes a DELETE operation on
-- waterway_linestring.updates as its last step.
CREATE TRIGGER trigger_flag_from_update_insert
    AFTER DELETE
    ON waterway_linestring.updates
    FOR EACH STATEMENT
EXECUTE PROCEDURE waterway_important.flag();

CREATE CONSTRAINT TRIGGER trigger_refresh
    AFTER INSERT
    ON waterway_important.updates
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE waterway_important.refresh();
