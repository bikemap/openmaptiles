DROP TRIGGER IF EXISTS trigger_store_transportation_route_member ON osm_route_member;
DROP TRIGGER IF EXISTS trigger_store_transportation_superroute_member ON osm_superroute_member;
DROP TRIGGER IF EXISTS trigger_store_transportation_highway_linestring ON osm_highway_linestring;
DROP TRIGGER IF EXISTS trigger_flag_transportation_name ON transportation_name.network_changes;
DROP TRIGGER IF EXISTS trigger_refresh_network ON transportation_name.updates_network;
DROP TRIGGER IF EXISTS trigger_store_transportation_name_network ON osm_transportation_name_network;
DROP TRIGGER IF EXISTS trigger_store_transportation_name_shipway ON osm_shipway_linestring;
DROP TRIGGER IF EXISTS trigger_store_transportation_name_aerialway ON osm_aerialway_linestring;
DROP TRIGGER IF EXISTS trigger_store_transportation_name_linestring ON osm_transportation_name_linestring;
DROP TRIGGER IF EXISTS trigger_flag_name ON transportation_name.name_changes;
DROP TRIGGER IF EXISTS trigger_flag_shipway ON transportation_name.shipway_changes;
DROP TRIGGER IF EXISTS trigger_flag_aerialway ON transportation_name.aerialway_changes;
DROP TRIGGER IF EXISTS trigger_refresh_name ON transportation_name.updates_name;
DROP TRIGGER IF EXISTS trigger_refresh_shipway ON transportation_name.updates_shipway;
DROP TRIGGER IF EXISTS trigger_refresh_aerialway ON transportation_name.updates_aerialway;

-- Instead of using relations to find out the road names we
-- stitch together the touching ways with the same name
-- to allow for nice label rendering
-- Because this works well for roads that do not have relations as well

-- Indexes for filling and updating osm_transportation_name_linestring table
CREATE INDEX IF NOT EXISTS osm_shipway_linestring_update_partial_idx ON osm_shipway_linestring (name)
    WHERE name <> '';
CREATE INDEX IF NOT EXISTS osm_aerialway_linestring_update_partial_idx ON osm_aerialway_linestring (name)
    WHERE name <> '';
CREATE INDEX IF NOT EXISTS osm_transportation_name_network_update_partial_idx
    ON osm_transportation_name_network (coalesce(tags->'name', ''), coalesce(ref, ''), network_type,
                                        nullif(network_name, ''))
    WHERE coalesce(tags->'name', '') <> '' OR
          coalesce(ref, '') <> '' OR (
              network_type = ANY('{icn,ncn,rcn,lcn}') AND
              nullif(network_name, '') IS NOT NULL
          );

-- etldoc: osm_transportation_name_network ->  osm_transportation_name_linestring
-- etldoc: osm_shipway_linestring ->  osm_transportation_name_linestring
-- etldoc: osm_aerialway_linestring ->  osm_transportation_name_linestring
CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring(
    id SERIAL,
    source integer,
    geometry geometry('LineString'),
    source_ids bigint[],
    tags hstore,
    ref text,
    highway varchar,
    subclass text,
    brunnel text,
    sac_scale varchar,
    "level" integer,
    layer integer,
    indoor boolean,
    network route_network_type,
    network_name text,
    route_1 text,
    route_2 text,
    route_3 text,
    route_4 text,
    route_5 text,
    route_6 text,
    z_order integer,
    route_rank integer
);

-- Create OneToMany-Relation-Table storing relations of a Merged-LineString in table
-- osm_transportation_name_linestring to Source-LineStrings from tables osm_transportation_name_network,
-- osm_shipway_linestring and osm_aerialway_linestring
CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring_source_ids(
    id int,
    source int,
    source_id bigint,
    PRIMARY KEY (id, source, source_id)
);

-- Ensure tables are emtpy if they haven't been created
TRUNCATE osm_transportation_name_linestring;
TRUNCATE osm_transportation_name_linestring_source_ids;

-- Create temporary Merged-LineString to Source-LineStrings-ID table to temporarily store relations before they have
-- been intersected
CREATE TEMPORARY TABLE initial_osm_transportation_name_linestring_source_ids
    (LIKE osm_transportation_name_linestring_source_ids INCLUDING INDEXES);

WITH inserted_linestrings AS (
    INSERT INTO osm_transportation_name_linestring(source, geometry, source_ids, tags, ref, highway, subclass, brunnel,
                                                   sac_scale, "level", layer, indoor, network, network_name, route_1,
                                                   route_2, route_3, route_4, route_5, route_6,z_order, route_rank)
    SELECT source,
           geometry,
           source_ids,
           tags || get_basic_names(tags, geometry) AS tags,
           ref,
           highway,
           subclass,
           brunnel,
           sac_scale,
           "level",
           layer,
           indoor,
           network_type AS network,
           network_name,
           route_1, route_2, route_3, route_4, route_5, route_6,
           z_order,
           route_rank
    FROM (
             -- Merge LineStrings from osm_transportation_name_network by grouping them and creating intersecting
             -- clusters of each group via ST_ClusterDBSCAN
             SELECT (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
                    -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the
                    -- geometries to merge. https://postgis.net/docs/ST_Union.html
                    -- ST_LineMerge only merges across singular intersections and groups its output into a
                    -- MultiLineString if more than two LineStrings form an intersection or no intersection could be
                    -- found. https://postgis.net/docs/ST_LineMerge.html
                    -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
                    -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
                    array_agg(osm_id) AS source_ids,
                    0 AS source,
                    tags,
                    ref,
                    highway,
                    subclass,
                    brunnel,
                    sac_scale,
                    level,
                    layer,
                    indoor,
                    network_type,
                    network_name,
                    route_1, route_2, route_3, route_4, route_5, route_6,
                    min(z_order) AS z_order,
                    min(route_rank) AS route_rank
             FROM (
                 SELECT *,
                        -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points
                        -- to 1. https://postgis.net/docs/ST_ClusterDBSCAN.html
                        ST_ClusterDBSCAN(geometry, 0, 1) OVER (
                            PARTITION BY tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor,
                                         network_type, network_name, route_1, route_2, route_3, route_4, route_5,
                                         route_6
                        ) AS cluster,
                        -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition
                        -- starting at 0. This leads to clusters having the same ID across multiple partitions
                        -- therefore we generate a Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the
                        -- partition columns.
                        DENSE_RANK() OVER (
                            ORDER BY tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor,
                                     network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6
                        ) as cluster_group
                 FROM osm_transportation_name_network
                 WHERE coalesce(tags->'name', '') <> '' OR
                       coalesce(ref, '') <> '' OR (
                           network_type = ANY('{icn,ncn,rcn,lcn}') AND nullif(network_name, '') IS NOT NULL
                       )
             ) q
             GROUP BY cluster_group, cluster, tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor,
                      network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6
             UNION ALL

             -- Merge LineStrings from osm_shipway_linestring by grouping them and creating intersecting
             -- clusters of each group via ST_ClusterDBSCAN
             SELECT (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
                    -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the
                    -- geometries to merge. https://postgis.net/docs/ST_Union.html
                    -- ST_LineMerge only merges across singular intersections and groups its output into a
                    -- MultiLineString if more than two LineStrings form an intersection or no intersection could be
                    -- found. https://postgis.net/docs/ST_LineMerge.html
                    -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
                    -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
                    array_agg(osm_id) AS source_ids,
                    1 AS source,
                    transportation_name_tags(
                        NULL::geometry, tags, name, name_en, name_de
                    ) AS tags,
                    NULL AS ref,
                    'shipway' AS highway,
                    shipway AS subclass,
                    NULL AS brunnel,
                    NULL AS sac_scale,
                    NULL::int AS level,
                    layer,
                    NULL AS indoor,
                    NULL AS network_type,
                    NULL AS network_name,
                    NULL AS route_1,
                    NULL AS route_2,
                    NULL AS route_3,
                    NULL AS route_4,
                    NULL AS route_5,
                    NULL AS route_6,
                    min(z_order) AS z_order,
                    NULL::int AS route_rank
             FROM (
                 SELECT *,
                        -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points
                        -- to 1. https://postgis.net/docs/ST_ClusterDBSCAN.html
                        ST_ClusterDBSCAN(geometry, 0, 1) OVER (
                            PARTITION BY transportation_name_tags(
                                NULL::geometry, tags, name, name_en, name_de
                            ), shipway, layer
                        ) AS cluster,
                        -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition
                        -- starting at 0. This leads to clusters having the same ID across multiple partitions
                        -- therefore we generate a Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the
                        -- partition columns.
                        DENSE_RANK() OVER (
                            ORDER BY transportation_name_tags(
                                NULL::geometry, tags, name, name_en, name_de
                            ), shipway, layer
                        ) as cluster_group
                 FROM osm_shipway_linestring
                 WHERE name <> ''
             ) q
             GROUP BY cluster_group, cluster, transportation_name_tags(
                 NULL::geometry, tags, name, name_en, name_de
             ), shipway, layer
             UNION ALL

             -- Merge LineStrings from osm_aerialway_linestring by grouping them and creating intersecting
             -- clusters of each group via ST_ClusterDBSCAN
             SELECT (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
                    -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the
                    -- geometries to merge. https://postgis.net/docs/ST_Union.html
                    -- ST_LineMerge only merges across singular intersections and groups its output into a
                    -- MultiLineString if more than two LineStrings form an intersection or no intersection could be
                    -- found. https://postgis.net/docs/ST_LineMerge.html
                    -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
                    -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
                    array_agg(osm_id) AS source_ids,
                    2 AS source,
                    transportation_name_tags(
                        NULL::geometry, tags, name, name_en, name_de
                    ) AS tags,
                    NULL AS ref,
                    'aerialway' AS highway,
                    aerialway AS subclass,
                    NULL AS brunnel,
                    NULL AS sac_scale,
                    NULL::int AS level,
                    layer,
                    NULL AS indoor,
                    NULL AS network_type,
                    NULL AS network_name,
                    NULL AS route_1,
                    NULL AS route_2,
                    NULL AS route_3,
                    NULL AS route_4,
                    NULL AS route_5,
                    NULL AS route_6,
                    min(z_order) AS z_order,
                    NULL::int AS route_rank
             FROM (
                 SELECT *,
                        -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points
                        -- to 1. https://postgis.net/docs/ST_ClusterDBSCAN.html
                        ST_ClusterDBSCAN(geometry, 0, 1) OVER (
                            PARTITION BY transportation_name_tags(
                                NULL::geometry, tags, name, name_en, name_de
                            ), aerialway, layer
                        ) AS cluster,
                        -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition
                        -- starting at 0. This leads to clusters having the same ID across multiple partitions
                        -- therefore we generate a Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the
                        -- partition columns.
                        DENSE_RANK() OVER (
                            ORDER BY transportation_name_tags(
                                NULL::geometry, tags, name, name_en, name_de
                            ), aerialway, layer
                        ) as cluster_group
                 FROM osm_aerialway_linestring
                 WHERE name <> ''
             ) q
             GROUP BY cluster_group, cluster, transportation_name_tags(
                 NULL::geometry, tags, name, name_en, name_de
             ), aerialway, layer
         ) AS highway_union
    RETURNING source, id, source_ids
)
-- Store OSM-IDs of Source-LineStrings
INSERT INTO initial_osm_transportation_name_linestring_source_ids (id, source, source_id)
SELECT id, source, unnest(source_ids) AS source_id
FROM inserted_linestrings
ON CONFLICT (id, source, source_id) DO NOTHING;

-- Geometry Index
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_geometry_idx
    ON osm_transportation_name_linestring USING gist (geometry);

-- Create table for simplified LineStrings
CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring_gen1 (
    id integer,
    geometry geometry('LineString'),
    tags hstore,
    ref text,
    highway varchar,
    subclass text,
    brunnel text,
    network route_network_type,
    network_name text,
    route_1 text,
    route_2 text,
    route_3 text,
    route_4 text,
    route_5 text,
    route_6 text,
    z_order integer
);

-- Create osm_transportation_name_linestring_gen2 as a copy of osm_transportation_name_linestring_gen1
CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring_gen2
(LIKE osm_transportation_name_linestring_gen1);

-- Create osm_transportation_name_linestring_gen3 as a copy of osm_transportation_name_linestring_gen2
CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring_gen3
(LIKE osm_transportation_name_linestring_gen2);

-- Create osm_transportation_name_linestring_gen4 as a copy of osm_transportation_name_linestring_gen3
CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring_gen4
(LIKE osm_transportation_name_linestring_gen3);

-- Create Primary-Keys for osm_transportation_name_linestring and
-- osm_transportation_name_linestring_gen1/gen2/gen3/gen4 tables
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_name_linestring' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_name_linestring ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_name_linestring_gen1' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_name_linestring_gen1 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_name_linestring_gen2' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_name_linestring_gen2 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_name_linestring_gen3' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_name_linestring_gen3 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_name_linestring_gen4' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_name_linestring_gen4 ADD PRIMARY KEY (id);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create index on id columns and analyze the initial Merged-LineString to Source-LineStrings-ID Relations table to
-- speed up subsequent queries
CREATE INDEX ON initial_osm_transportation_name_linestring_source_ids(id, source_id);
ANALYZE initial_osm_transportation_name_linestring_source_ids;

-- Store OSM-IDs of Source-LineStrings by intersecting Merged-LineStrings with their sources. This required because
-- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString if
-- more than two LineStrings form an intersection or no intersection could be found.
-- Execute after indexes have been created on osm_transportation_merge_linestring_gen_z11 to improve performance
INSERT INTO osm_transportation_name_linestring_source_ids(id, source, source_id)
SELECT m.id, m.source, source_id
FROM osm_transportation_name_linestring m, initial_osm_transportation_name_linestring_source_ids s
WHERE m.source = 0 AND EXISTS(
    SELECT NULL
    FROM osm_transportation_name_network
    WHERE m.id = s.id AND
          osm_transportation_name_network.osm_id = s.source_id AND
          ST_Intersects(osm_transportation_name_network.geometry, m.geometry)
)
ON CONFLICT (id, source, source_id) DO NOTHING;
INSERT INTO osm_transportation_name_linestring_source_ids(id, source, source_id)
SELECT m.id, m.source, source_id
FROM osm_transportation_name_linestring m, initial_osm_transportation_name_linestring_source_ids s
WHERE m.source = 1 AND EXISTS(
    SELECT NULL
    FROM osm_shipway_linestring
    WHERE m.id = s.id AND
          osm_shipway_linestring.osm_id = s.source_id AND
          ST_Intersects(osm_shipway_linestring.geometry, m.geometry)
)
ON CONFLICT (id, source, source_id) DO NOTHING;
INSERT INTO osm_transportation_name_linestring_source_ids(id, source, source_id)
SELECT m.id, m.source, source_id
FROM osm_transportation_name_linestring m, initial_osm_transportation_name_linestring_source_ids s
WHERE m.source = 2 AND EXISTS(
    SELECT NULL
    FROM osm_aerialway_linestring
    WHERE m.id = s.id AND
          osm_aerialway_linestring.osm_id = s.source_id AND
          ST_Intersects(osm_aerialway_linestring.geometry, m.geometry)
)
ON CONFLICT (id, source, source_id) DO NOTHING;

-- Drop temporary tables early to save resources
DROP TABLE initial_osm_transportation_name_linestring_source_ids;

-- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations table
-- Execute after indexes have been created on osm_transportation_merge_linestring_gen_z11 to improve performance
UPDATE osm_transportation_name_linestring SET source_ids = q.source_ids
FROM (
    SELECT id, array_agg(source_id) AS source_ids
    FROM osm_transportation_name_linestring_source_ids
    GROUP BY id
) q
WHERE osm_transportation_name_linestring.id = q.id;

CREATE SCHEMA IF NOT EXISTS transportation_name;

CREATE TABLE IF NOT EXISTS transportation_name.name_changes_gen
(
    is_old boolean,
    id int,
    PRIMARY KEY (id, is_old)
);

CREATE OR REPLACE FUNCTION update_transportation_name_linestring_gen (full_update bool) RETURNS VOID AS $$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation_name merged';

    -- Analyze tracking and source tables before performing update
    ANALYZE transportation_name.name_changes_gen;
    ANALYZE osm_transportation_name_linestring;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_name_linestring_gen1
    USING transportation_name.name_changes_gen
    WHERE full_update IS TRUE OR (
        transportation_name.name_changes_gen.is_old IS TRUE AND
        transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen1.id
    );

    -- etldoc: osm_transportation_name_linestring -> osm_transportation_name_linestring_gen1
    INSERT INTO osm_transportation_name_linestring_gen1 (id, geometry, tags, ref, highway, subclass, brunnel, network,
                                                         network_name, route_1, route_2, route_3, route_4, route_5,
                                                         route_6, z_order)
    SELECT id, ST_Simplify(geometry, 50) AS geometry, tags, ref, highway, subclass, brunnel, network, network_name,
           route_1, route_2, route_3, route_4, route_5, route_6, z_order
    FROM osm_transportation_name_linestring
    WHERE (
        full_update IS TRUE OR EXISTS (
            SELECT NULL
            FROM transportation_name.name_changes_gen
            WHERE transportation_name.name_changes_gen.is_old IS FALSE AND
                  transportation_name.name_changes_gen.id = osm_transportation_name_linestring.id
        )
    ) AND (
        (
            network IN ('icn', 'ncn', 'rcn') OR
            (highway IN ('motorway', 'trunk') OR highway = 'construction' AND subclass IN ('motorway', 'trunk'))
        ) AND ST_Length(geometry) > 8000
    ) ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, tags = excluded.tags, ref = excluded.ref,
                                     highway = excluded.highway, subclass = excluded.subclass,
                                     brunnel = excluded.brunnel, network = excluded.network,
                                     network_name = excluded.network_name, route_1 = excluded.route_1,
                                     route_2 = excluded.route_2, route_3 = excluded.route_3, route_4 = excluded.route_4,
                                     route_5 = excluded.route_5, route_6 = excluded.route_6, z_order = excluded.z_order;

    -- Analyze source table
    ANALYZE osm_transportation_name_linestring_gen1;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_name_linestring_gen2
    USING transportation_name.name_changes_gen
    WHERE full_update IS TRUE OR (
        transportation_name.name_changes_gen.is_old IS TRUE AND
        transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen2.id
    );

    -- etldoc: osm_transportation_name_linestring_gen1 -> osm_transportation_name_linestring_gen2
    INSERT INTO osm_transportation_name_linestring_gen2 (id, geometry, tags, ref, highway, subclass, brunnel, network,
                                                         network_name, route_1, route_2, route_3, route_4, route_5,
                                                         route_6, z_order)
    SELECT id, ST_Simplify(geometry, 120) AS geometry, tags, ref, highway, subclass, brunnel, network, network_name,
           route_1, route_2, route_3, route_4, route_5, route_6, z_order
    FROM osm_transportation_name_linestring_gen1
    WHERE (
        full_update IS TRUE OR EXISTS (
            SELECT NULL
            FROM transportation_name.name_changes_gen
            WHERE transportation_name.name_changes_gen.is_old IS FALSE AND
                  transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen1.id
        )
    ) AND (
        (
            network IN ('icn', 'ncn', 'rcn') OR
            (highway IN ('motorway', 'trunk') OR highway = 'construction' AND subclass IN ('motorway', 'trunk'))
        ) AND ST_Length(geometry) > 14000
    ) ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, tags = excluded.tags, ref = excluded.ref,
                                     highway = excluded.highway, subclass = excluded.subclass,
                                     brunnel = excluded.brunnel, network = excluded.network,
                                     network_name = excluded.network_name, route_1 = excluded.route_1,
                                     route_2 = excluded.route_2, route_3 = excluded.route_3, route_4 = excluded.route_4,
                                     route_5 = excluded.route_5, route_6 = excluded.route_6, z_order = excluded.z_order;

    -- Analyze source table
    ANALYZE osm_transportation_name_linestring_gen2;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_name_linestring_gen3
    USING transportation_name.name_changes_gen
    WHERE full_update IS TRUE OR (
        transportation_name.name_changes_gen.is_old IS TRUE AND
        transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen3.id
    );

    -- etldoc: osm_transportation_name_linestring_gen2 -> osm_transportation_name_linestring_gen3
    INSERT INTO osm_transportation_name_linestring_gen3 (id, geometry, tags, ref, highway, subclass, brunnel, network,
                                                         network_name, route_1, route_2, route_3, route_4, route_5,
                                                         route_6, z_order)
    SELECT id, ST_Simplify(geometry, 200) AS geometry, tags, ref, highway, subclass, brunnel, network, network_name,
           route_1, route_2, route_3, route_4, route_5, route_6, z_order
    FROM osm_transportation_name_linestring_gen2
    WHERE (
        full_update IS TRUE OR EXISTS (
            SELECT NULL
            FROM transportation_name.name_changes_gen
            WHERE transportation_name.name_changes_gen.is_old IS FALSE AND
                  transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen2.id
        )
    ) AND (
        (
            network IN ('icn', 'ncn') OR
            (highway = 'motorway' OR highway = 'construction' AND subclass = 'motorway')
        ) AND ST_Length(geometry) > 20000
    ) ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, tags = excluded.tags, ref = excluded.ref,
                                     highway = excluded.highway, subclass = excluded.subclass,
                                     brunnel = excluded.brunnel, network = excluded.network,
                                     network_name = excluded.network_name, route_1 = excluded.route_1,
                                     route_2 = excluded.route_2, route_3 = excluded.route_3, route_4 = excluded.route_4,
                                     route_5 = excluded.route_5, route_6 = excluded.route_6, z_order = excluded.z_order;

    -- Analyze source table
    ANALYZE osm_transportation_name_linestring_gen3;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_name_linestring_gen4
    USING transportation_name.name_changes_gen
    WHERE full_update IS TRUE OR (
        transportation_name.name_changes_gen.is_old IS TRUE AND
        transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen4.id
    );

    -- etldoc: osm_transportation_name_linestring_gen3 -> osm_transportation_name_linestring_gen4
    INSERT INTO osm_transportation_name_linestring_gen4 (id, geometry, tags, ref, highway, subclass, brunnel, network,
                                                         route_1, route_2, route_3, route_4, route_5, route_6, z_order)
    SELECT id, ST_Simplify(geometry, 500) AS geometry, tags, ref, highway, subclass, brunnel, network, route_1, route_2,
           route_3, route_4, route_5, route_6, z_order
    FROM osm_transportation_name_linestring_gen3
    WHERE (
        full_update IS TRUE OR EXISTS (
            SELECT NULL
            FROM transportation_name.name_changes_gen
            WHERE transportation_name.name_changes_gen.is_old IS FALSE AND
                  transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen3.id
        )
    ) AND (
        (highway = 'motorway' OR highway = 'construction' AND subclass = 'motorway') AND
        ST_Length(geometry) > 20000
    ) ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, tags = excluded.tags, ref = excluded.ref,
                                     highway = excluded.highway, subclass = excluded.subclass,
                                     brunnel = excluded.brunnel, network = excluded.network, route_1 = excluded.route_1,
                                     route_2 = excluded.route_2, route_3 = excluded.route_3, route_4 = excluded.route_4,
                                     route_5 = excluded.route_5, route_6 = excluded.route_6, z_order = excluded.z_order;

    -- noinspection SqlWithoutWhere
    DELETE FROM transportation_name.name_changes_gen;

    RAISE LOG 'Refresh transportation_name merged done in %', age(clock_timestamp(), t);
END;
$$ LANGUAGE plpgsql;

-- Ensure tables are emtpy if they haven't been created
TRUNCATE osm_transportation_name_linestring_gen1;
TRUNCATE osm_transportation_name_linestring_gen2;
TRUNCATE osm_transportation_name_linestring_gen3;
TRUNCATE osm_transportation_name_linestring_gen4;

-- Indexes which can be utilized during full-update for queries originating from
-- update_transportation_name_linestring_gen() function
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_update_partial_idx
    ON osm_transportation_name_linestring (network, highway, subclass, ST_Length(geometry))
    WHERE (
        network IN ('icn', 'ncn', 'rcn') OR
        (highway IN ('motorway', 'trunk') OR highway = 'construction' AND subclass IN ('motorway', 'trunk'))
    ) AND ST_Length(geometry) > 8000;

SELECT update_transportation_name_linestring_gen(TRUE);

-- Indexes for queries originating from update_transportation_name_linestring_gen() function
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen1_update_partial_idx
    ON osm_transportation_name_linestring_gen1 (network, highway, subclass, ST_Length(geometry))
    WHERE (
        network IN ('icn', 'ncn', 'rcn') OR
        (highway IN ('motorway', 'trunk') OR highway = 'construction' AND subclass IN ('motorway', 'trunk'))
    ) AND ST_Length(geometry) > 14000;
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen2_update_partial_idx
    ON osm_transportation_name_linestring_gen2 (network, highway, subclass, ST_Length(geometry))
    WHERE (
        network IN ('icn', 'ncn') OR
        (highway = 'motorway' OR highway = 'construction' AND subclass = 'motorway')
    ) AND ST_Length(geometry) > 20000;
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen3_update_partial_idx
    ON osm_transportation_name_linestring_gen3 (highway, subclass, ST_Length(geometry))
    WHERE (highway = 'motorway' OR highway = 'construction' AND subclass = 'motorway')
          AND ST_Length(geometry) > 20000;

-- Geometry Indexes
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen1_geometry_idx
    ON osm_transportation_name_linestring_gen1 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen2_geometry_idx
    ON osm_transportation_name_linestring_gen2 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen3_geometry_idx
    ON osm_transportation_name_linestring_gen3 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen4_geometry_idx
    ON osm_transportation_name_linestring_gen4 USING gist (geometry);

-- Handle updates

-- Trigger to update "osm_transportation_name_network" from "osm_route_member" and "osm_highway_linestring"

CREATE TABLE IF NOT EXISTS transportation_name.network_changes
(
    osm_id bigint PRIMARY KEY
);

-- Store IDs of changed elements from osm_route_member table.
CREATE OR REPLACE FUNCTION transportation_name.route_member_store() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation_name.network_changes(osm_id)
    VALUES (CASE WHEN tg_op IN ('DELETE', 'UPDATE') THEN old.member ELSE new.member END)
    ON CONFLICT(osm_id) DO NOTHING;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS transportation_name.superroute_changes
(
    osm_id bigint PRIMARY KEY
);

-- Store IDs of changed elements from osm_superroute_member table.
CREATE OR REPLACE FUNCTION transportation_name.superroute_member_store() RETURNS trigger AS
$$
BEGIN

    INSERT INTO transportation_name.superroute_changes(osm_id) VALUES (
        (CASE WHEN tg_op IN ('DELETE', 'UPDATE') THEN old.osm_id ELSE new.osm_id END)
    ) ON CONFLICT DO NOTHING;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Store IDs of changed elements from osm_highway_linestring table.
CREATE OR REPLACE FUNCTION transportation_name.highway_linestring_store() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation_name.network_changes(osm_id)
    VALUES (CASE WHEN tg_op IN ('DELETE', 'UPDATE') THEN old.osm_id ELSE new.osm_id END)
    ON CONFLICT(osm_id) DO NOTHING;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS transportation_name.updates_network
(
    id serial PRIMARY KEY,
    t text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION transportation_name.flag_network() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation_name.updates_network(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation_name.refresh_network() RETURNS trigger AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation_name_network';

    -- Analyze tracking and source tables before performing update
    ANALYZE transportation_name.network_changes;
    ANALYZE osm_highway_linestring;

    PERFORM update_osm_route_member();

    ANALYZE osm_route_member;

    -- REFRESH osm_transportation_name_network
    DELETE
    FROM osm_transportation_name_network AS n
        USING
            transportation_name.network_changes AS c
    WHERE n.osm_id = c.osm_id;

    UPDATE osm_highway_linestring hl
    SET network = rm.network_type
    FROM transportation_name.network_changes c,
         osm_route_member rm
    WHERE hl.osm_id=c.osm_id
      AND hl.osm_id=rm.member
      AND rm.concurrency_index=1;

    UPDATE osm_highway_linestring_gen_z11 hl
    SET network = rm.network_type
    FROM transportation_name.network_changes c,
         osm_route_member rm
    WHERE hl.osm_id=c.osm_id
      AND hl.osm_id=rm.member
      AND rm.concurrency_index=1;

    INSERT INTO osm_transportation_name_network
    SELECT
        geometry,
        osm_id,
        tags || get_basic_names(tags, geometry) AS tags,
        ref,
        highway,
        subclass,
        brunnel,
        level,
        sac_scale,
        layer,
        indoor,
        network_type,
        network_name,
        route_1, route_2, route_3, route_4, route_5, route_6,
        z_order,
        route_rank
    FROM (
        SELECT hl.geometry,
            hl.osm_id,
            transportation_name_tags(hl.geometry, hl.tags, hl.name, hl.name_en, hl.name_de) AS tags,
            rm1.network_type,
            NULLIF(rm1.name, '') as network_name,
            CASE
                WHEN rm1.network_type IS NOT NULL AND rm1.ref::text <> ''
                    THEN rm1.ref::text
                ELSE NULLIF(hl.ref, '')
                END AS ref,
            hl.highway,
            NULLIF(hl.construction, '') AS subclass,
            brunnel(hl.is_bridge, hl.is_tunnel, hl.is_ford) AS brunnel,
            sac_scale,
            CASE WHEN highway IN ('footway', 'steps') THEN layer END AS layer,
            CASE WHEN highway IN ('footway', 'steps') THEN level END AS level,
            CASE WHEN highway IN ('footway', 'steps') THEN indoor END AS indoor,
	    NULLIF(rm1.network, '') || '=' || COALESCE(rm1.ref, '') AS route_1,
	    NULLIF(rm2.network, '') || '=' || COALESCE(rm2.ref, '') AS route_2,
	    NULLIF(rm3.network, '') || '=' || COALESCE(rm3.ref, '') AS route_3,
	    NULLIF(rm4.network, '') || '=' || COALESCE(rm4.ref, '') AS route_4,
	    NULLIF(rm5.network, '') || '=' || COALESCE(rm5.ref, '') AS route_5,
	    NULLIF(rm6.network, '') || '=' || COALESCE(rm6.ref, '') AS route_6,
            hl.z_order,
            LEAST(rm1.rank, rm2.rank, rm3.rank, rm4.rank, rm5.rank, rm6.rank) AS route_rank
        FROM osm_highway_linestring hl
                JOIN transportation_name.network_changes AS c ON
            hl.osm_id = c.osm_id
		LEFT OUTER JOIN osm_route_member rm1 ON rm1.member = hl.osm_id AND rm1.concurrency_index=1
		LEFT OUTER JOIN osm_route_member rm2 ON rm2.member = hl.osm_id AND rm2.concurrency_index=2
		LEFT OUTER JOIN osm_route_member rm3 ON rm3.member = hl.osm_id AND rm3.concurrency_index=3
		LEFT OUTER JOIN osm_route_member rm4 ON rm4.member = hl.osm_id AND rm4.concurrency_index=4
		LEFT OUTER JOIN osm_route_member rm5 ON rm5.member = hl.osm_id AND rm5.concurrency_index=5
		LEFT OUTER JOIN osm_route_member rm6 ON rm6.member = hl.osm_id AND rm6.concurrency_index=6
	WHERE (hl.name <> '' OR hl.ref <> '' OR rm1.ref <> '' OR rm1.network <> '')
          AND hl.highway <> ''
    ) AS t
    ON CONFLICT DO NOTHING;

    -- noinspection SqlWithoutWhere
    DELETE FROM transportation_name.network_changes;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation_name.updates_network;

    RAISE LOG 'Refresh transportation_name network done in %', age(clock_timestamp(), t);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trigger_store_transportation_route_member
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_route_member
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.route_member_store();

CREATE TRIGGER trigger_store_transportation_superroute_member
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_superroute_member
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.superroute_member_store();

CREATE TRIGGER trigger_store_transportation_highway_linestring
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_highway_linestring
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.highway_linestring_store();

CREATE TRIGGER trigger_flag_transportation_name
    AFTER INSERT
    ON transportation_name.network_changes
    FOR EACH STATEMENT
EXECUTE PROCEDURE transportation_name.flag_network();

CREATE CONSTRAINT TRIGGER trigger_refresh_network
    AFTER INSERT
    ON transportation_name.updates_network
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.refresh_network();

-- Handle updates on
-- osm_transportation_name_network -> osm_transportation_name_linestring
-- osm_shipway_linestring -> osm_transportation_name_linestring
-- osm_aerialway_linestring -> osm_transportation_name_linestring
-- osm_transportation_name_linestring -> osm_transportation_name_linestring_gen1
-- osm_transportation_name_linestring -> osm_transportation_name_linestring_gen2
-- osm_transportation_name_linestring -> osm_transportation_name_linestring_gen3
-- osm_transportation_name_linestring -> osm_transportation_name_linestring_gen4

CREATE TABLE IF NOT EXISTS transportation_name.name_changes
(
    is_old boolean,
    osm_id bigint,
    PRIMARY KEY (osm_id, is_old)
);
CREATE TABLE IF NOT EXISTS transportation_name.shipway_changes
(
    is_old boolean,
    osm_id bigint,
    PRIMARY KEY (osm_id, is_old)
);
CREATE TABLE IF NOT EXISTS transportation_name.aerialway_changes
(
    is_old boolean,
    osm_id bigint,
    PRIMARY KEY (osm_id, is_old)
);

-- Store IDs of changed elements from osm_transportation_name_network table.
CREATE OR REPLACE FUNCTION transportation_name.name_network_store() RETURNS trigger AS
$$
BEGIN
    IF (tg_op IN ('DELETE', 'UPDATE'))
    THEN
        INSERT INTO transportation_name.name_changes(is_old, osm_id)
        VALUES (TRUE, old.osm_id)
        ON CONFLICT (osm_id, is_old) DO NOTHING;
    END IF;
    IF (tg_op IN ('UPDATE', 'INSERT'))
    THEN
        INSERT INTO transportation_name.name_changes(is_old, osm_id)
        VALUES (FALSE, new.osm_id)
        ON CONFLICT (osm_id, is_old) DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Store IDs of changed elements from osm_shipway_linestring table.
CREATE OR REPLACE FUNCTION transportation_name.name_shipway_store() RETURNS trigger AS
$$
BEGIN
    IF (tg_op IN ('DELETE', 'UPDATE'))
    THEN
        INSERT INTO transportation_name.shipway_changes(is_old, osm_id)
        VALUES (TRUE, old.osm_id)
        ON CONFLICT (osm_id, is_old) DO NOTHING;
    END IF;
    IF (tg_op IN ('UPDATE', 'INSERT'))
    THEN
        INSERT INTO transportation_name.shipway_changes(is_old, osm_id)
        VALUES (FALSE, new.osm_id)
        ON CONFLICT (osm_id, is_old) DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Store IDs of changed elements from osm_aerialway_linestring table.
CREATE OR REPLACE FUNCTION transportation_name.name_aerialway_store() RETURNS trigger AS
$$
BEGIN
    IF (tg_op IN ('DELETE', 'UPDATE'))
    THEN
        INSERT INTO transportation_name.aerialway_changes(is_old, osm_id)
        VALUES (TRUE, old.osm_id)
        ON CONFLICT (osm_id, is_old) DO NOTHING;
    END IF;
    IF (tg_op IN ('UPDATE', 'INSERT'))
    THEN
        INSERT INTO transportation_name.aerialway_changes(is_old, osm_id)
        VALUES (FALSE, new.osm_id)
        ON CONFLICT (osm_id, is_old) DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Store IDs of changed elements from osm_transportation_name_linestring table.
CREATE OR REPLACE FUNCTION transportation_name.name_linestring_store() RETURNS trigger AS
$$
BEGIN
    IF (tg_op = 'DELETE')
    THEN
        INSERT INTO transportation_name.name_changes_gen(is_old, id)
        VALUES (TRUE, old.id)
        ON CONFLICT (id, is_old) DO NOTHING;
    END IF;
    IF (tg_op = 'UPDATE' OR tg_op = 'INSERT')
    THEN
        INSERT INTO transportation_name.name_changes_gen(is_old, id)
        VALUES (FALSE, new.id)
        ON CONFLICT (id, is_old) DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS transportation_name.updates_name
(
    id serial PRIMARY KEY,
    t  text,
    UNIQUE (t)
);
CREATE TABLE IF NOT EXISTS transportation_name.updates_shipway
(
    id serial PRIMARY KEY,
    t  text,
    UNIQUE (t)
);
CREATE TABLE IF NOT EXISTS transportation_name.updates_aerialway
(
    id serial PRIMARY KEY,
    t  text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION transportation_name.flag_name() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation_name.updates_name(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation_name.flag_shipway() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation_name.updates_shipway(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation_name.flag_aerialway() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation_name.updates_aerialway(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation_name.refresh_name() RETURNS trigger AS
$BODY$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation_name';

    -- REFRESH osm_transportation_name_linestring from osm_transportation_name_network

    -- Analyze tracking and source tables before performing update
    ANALYZE transportation_name.name_changes;
    ANALYZE osm_transportation_name_network;

    -- Fetch updated and deleted Merged-LineString from relation-table filtering for each Merged-LineString which
    -- contains an updated Source-LineString.
    -- Additionally attach a list of Source-LineString-IDs to each Merged-LineString in order to unnest them later.
    CREATE TEMPORARY TABLE affected_merged_linestrings AS
    SELECT m.id, array_agg(source_id) AS source_ids
    FROM osm_transportation_name_linestring_source_ids m
    WHERE m.source = 0 AND EXISTS(
        SELECT NULL
        FROM transportation_name.name_changes c
        WHERE c.is_old IS TRUE AND c.osm_id = m.source_id
    )
    GROUP BY id;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_merged_linestrings (id);
    ANALYZE affected_merged_linestrings;

    -- Delete all Merged-LineStrings which contained an updated or deleted Source-LineString
    DELETE
    FROM osm_transportation_name_linestring m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;
    DELETE
    FROM osm_transportation_name_linestring_source_ids m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;

    -- Analyze the tables affected by the delete-query in order to speed up subsequent queries
    ANALYZE osm_transportation_name_linestring;
    ANALYZE osm_transportation_name_linestring_source_ids;

    -- Create a table containing the IDs of all Source-LineStrings affected by this update
    CREATE TEMPORARY TABLE affected_source_linestrings AS
    -- Get Source-LineString-IDs of deleted or updated elements
    SELECT unnest(affected_merged_linestrings.source_ids) AS osm_id
    FROM affected_merged_linestrings
    UNION
    -- Get Source-LineString-IDs of inserted or updated elements
    SELECT osm_id FROM transportation_name.name_changes WHERE is_old IS FALSE
    ORDER BY osm_id;

    -- Drop temporary tables early to save resources
    DROP TABLE affected_merged_linestrings;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_source_linestrings (osm_id);
    ANALYZE affected_source_linestrings;

    -- Create a table containing all LineStrings which should be merged
    CREATE TEMPORARY TABLE linestrings_to_merge AS
    -- Add all Source-LineStrings affected by this update
    SELECT osm_id, NULL::INTEGER AS id, geometry, tags, ref, highway, subclass, brunnel, sac_scale, level, layer,
           indoor, network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6,
           z_order, route_rank
    FROM osm_transportation_name_network
    WHERE EXISTS(
        SELECT NULL
        FROM affected_source_linestrings
        WHERE affected_source_linestrings.osm_id = osm_transportation_name_network.osm_id
    ) AND (
        coalesce(tags->'name', '') <> '' OR
        coalesce(ref, '') <> '' OR (
            network_type = ANY('{icn,ncn,rcn,lcn}') AND NULLIF(network_name, '') IS NOT NULL
        )
    );

    -- Drop temporary tables early to save resources
    DROP TABLE affected_source_linestrings;

    -- Create index on geometry column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge USING GIST (geometry);
    ANALYZE linestrings_to_merge;

    -- Add all Merged-LineStrings intersecting with Source-LineStrings affected by this update
    INSERT INTO linestrings_to_merge
    SELECT unnest(source_ids) AS osm_id, id, geometry, tags, ref, highway, subclass, brunnel, sac_scale, level,
           layer, indoor, network AS network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6,
           z_order, route_rank
    FROM osm_transportation_name_linestring
    WHERE EXISTS(
        SELECT NULL FROM linestrings_to_merge
        WHERE osm_transportation_name_linestring.source = 0 AND ST_Intersects(
            linestrings_to_merge.geometry, osm_transportation_name_linestring.geometry
        )
    );

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge (id);
    ANALYZE linestrings_to_merge;

    -- Delete all Merged-LineStrings intersecting with Source-LineStrings affected by this update.
    -- We can use the linestrings_to_merge table since Source-LineStrings affected by this update and present in the
    -- table will have their ID-Column set to NULL by the previous query.
    DELETE
    FROM osm_transportation_name_linestring m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;
    DELETE
    FROM osm_transportation_name_linestring_source_ids m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;

    -- Create table containing all LineStrings to and create clusters of intersecting LineStrings partitioned by their
    -- groups
    CREATE TEMPORARY TABLE clustered_linestrings_to_merge AS
    SELECT *,
           -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points to 1.
           -- https://postgis.net/docs/ST_ClusterDBSCAN.html
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (
               PARTITION BY tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor, network_type,
                            network_name, route_1, route_2, route_3, route_4, route_5, route_6
           ) AS cluster,
           -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition starting at 0.
           -- This leads to clusters having the same ID across multiple partitions therefore we generate a
           -- Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the partition columns.
           DENSE_RANK() OVER (
               ORDER BY tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor, network_type,
                        network_name, route_1, route_2, route_3, route_4, route_5, route_6
           ) as cluster_group
    FROM linestrings_to_merge;

    -- Drop temporary tables early to save resources
    DROP TABLE linestrings_to_merge;

    -- Create index on cluster columns and analyze the created table to speed up subsequent queries
    CREATE INDEX ON clustered_linestrings_to_merge (cluster_group, cluster);
    ANALYZE clustered_linestrings_to_merge;

    -- Create temporary Merged-LineString to Source-LineStrings-ID table to temporarily store relations before they have
    -- been intersected
    CREATE TEMPORARY TABLE inserted_relations
    (LIKE osm_transportation_name_linestring_source_ids INCLUDING INDEXES);

    WITH inserted_linestrings AS (
        -- Merge LineStrings of each cluster and insert them
        INSERT INTO osm_transportation_name_linestring(source, geometry, source_ids, tags, ref, highway, subclass,
                                                       brunnel, sac_scale, "level", layer, indoor, network,
                                                       network_name, route_1, route_2, route_3, route_4, route_5,
                                                       route_6, z_order, route_rank)
        SELECT 0 AS source, (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
               -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the geometries
               -- to merge. https://postgis.net/docs/ST_Union.html
               -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString
               -- if more than two LineStrings form an intersection or no intersection could be found.
               -- https://postgis.net/docs/ST_LineMerge.html
               -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
               -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
               array_agg(osm_id) AS source_ids, tags, ref, highway, subclass, brunnel, sac_scale, level, layer,
               indoor, network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6,
               min(z_order) AS z_order, min(route_rank) AS route_rank
        FROM clustered_linestrings_to_merge
        GROUP BY cluster_group, cluster, tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor,
                 network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6
        RETURNING id, source, source_ids
    )
    -- Store OSM-IDs of Source-LineStrings
    INSERT INTO inserted_relations (id, source, source_id)
    SELECT id, source, unnest(source_ids) AS source_id
    FROM inserted_linestrings
    ON CONFLICT (id, source, source_id) DO NOTHING;

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
        INSERT INTO osm_transportation_name_linestring_source_ids (id, source, source_id)
        SELECT m.id, m.source, source_id
        FROM osm_transportation_name_linestring m, inserted_relations s
        WHERE (
            EXISTS(
                SELECT NULL
                FROM osm_transportation_name_network
                WHERE m.id = s.id AND
                      osm_transportation_name_network.osm_id = s.source_id AND
                      ST_Intersects(osm_transportation_name_network.geometry, m.geometry)
            )
        ) ON CONFLICT (id, source, source_id) DO NOTHING
        RETURNING id, source_id
    )
    -- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations
    -- table
    UPDATE osm_transportation_name_linestring SET source_ids = q.source_ids
    FROM (
        SELECT id, array_agg(source_id) AS source_ids
        FROM intersected_relations
        GROUP BY id
    ) q
    WHERE osm_transportation_name_linestring.id = q.id;

    -- Cleanup
    DROP TABLE inserted_relations;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation_name.name_changes;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation_name.updates_name;

    RAISE LOG 'Refresh transportation_name done in %', age(clock_timestamp(), t);

    -- Update gen1, gen2, gen3 and gen4 tables
    PERFORM update_transportation_name_linestring_gen(FALSE);

    RETURN NULL;
END;
$BODY$ LANGUAGE plpgsql;

-- Indexes for queries originating from transportation_name.refresh_name() function
CREATE INDEX IF NOT EXISTS transportation_name_name_changes_is_old_idx ON transportation_name.name_changes (is_old);

CREATE OR REPLACE FUNCTION transportation_name.refresh_shipway_linestring() RETURNS trigger AS
$BODY$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation_name shiwpway';

    -- REFRESH osm_transportation_name_linestring from osm_shipway_linestring

    -- Analyze tracking and source tables before performing update
    ANALYZE transportation_name.name_changes;
    ANALYZE osm_shipway_linestring;

    -- Fetch updated and deleted Merged-LineString from relation-table filtering for each Merged-LineString which
    -- contains an updated Source-LineString.
    -- Additionally attach a list of Source-LineString-IDs to each Merged-LineString in order to unnest them later.
    CREATE TEMPORARY TABLE affected_merged_linestrings AS
    SELECT m.id, array_agg(source_id) AS source_ids
    FROM osm_transportation_name_linestring_source_ids m
    WHERE m.source = 1 AND EXISTS(
        SELECT NULL
        FROM transportation_name.name_changes c
        WHERE c.is_old IS TRUE AND c.osm_id = m.source_id
    )
    GROUP BY id;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_merged_linestrings (id);
    ANALYZE affected_merged_linestrings;

    -- Delete all Merged-LineStrings which contained an updated or deleted Source-LineString
    DELETE
    FROM osm_transportation_name_linestring m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;
    DELETE
    FROM osm_transportation_name_linestring_source_ids m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;

    -- Analyze the tables affected by the delete-query in order to speed up subsequent queries
    ANALYZE osm_transportation_name_linestring;
    ANALYZE osm_transportation_name_linestring_source_ids;

    -- Create a table containing the IDs of all Source-LineStrings affected by this update
    CREATE TEMPORARY TABLE affected_source_linestrings AS
    -- Get Source-LineString-IDs of deleted or updated elements
    SELECT unnest(affected_merged_linestrings.source_ids) AS osm_id
    FROM affected_merged_linestrings
    UNION
    -- Get Source-LineString-IDs of inserted or updated elements
    SELECT osm_id FROM transportation_name.shipway_changes WHERE is_old IS FALSE
    ORDER BY osm_id;

    -- Drop temporary tables early to save resources
    DROP TABLE affected_merged_linestrings;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_source_linestrings (osm_id);
    ANALYZE affected_source_linestrings;

    -- Create a table containing all LineStrings which should be merged
    CREATE TEMPORARY TABLE linestrings_to_merge AS
    -- Add all Source-LineStrings affected by this update
    SELECT osm_id, NULL::INTEGER AS id, geometry,
           transportation_name_tags(
               NULL::geometry, tags, name, name_en, name_de
           ) AS tags, shipway AS subclass, layer, z_order
    FROM osm_shipway_linestring
    WHERE EXISTS(
        SELECT NULL
        FROM affected_source_linestrings
        WHERE affected_source_linestrings.osm_id = osm_shipway_linestring.osm_id
    ) AND (
        name <> ''
    );

    -- Drop temporary tables early to save resources
    DROP TABLE affected_source_linestrings;

    -- Create index on geometry column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge USING GIST (geometry);
    ANALYZE linestrings_to_merge;

    -- Add all Merged-LineStrings intersecting with Source-LineStrings affected by this update
    INSERT INTO linestrings_to_merge
    SELECT unnest(source_ids) AS osm_id, id, geometry, tags, subclass, layer, z_order
    FROM osm_transportation_name_linestring
    WHERE EXISTS(
        SELECT NULL FROM linestrings_to_merge
        WHERE osm_transportation_name_linestring.source = 1 AND ST_Intersects(
            linestrings_to_merge.geometry, osm_transportation_name_linestring.geometry
        )
    );

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge (id);
    ANALYZE linestrings_to_merge;

    -- Delete all Merged-LineStrings intersecting with Source-LineStrings affected by this update.
    -- We can use the linestrings_to_merge table since Source-LineStrings affected by this update and present in the
    -- table will have their ID-Column set to NULL by the previous query.
    DELETE
    FROM osm_transportation_name_linestring m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;
    DELETE
    FROM osm_transportation_name_linestring_source_ids m
    USING linestrings_to_merge
    WHERE  m.id = linestrings_to_merge.id;

    -- Create table containing all LineStrings to and create clusters of intersecting LineStrings partitioned by their
    -- groups
    CREATE TEMPORARY TABLE clustered_linestrings_to_merge AS
    SELECT *,
           -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points to 1.
           -- https://postgis.net/docs/ST_ClusterDBSCAN.html
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (PARTITION BY tags, subclass, layer) AS cluster,
           -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition starting at 0.
           -- This leads to clusters having the same ID across multiple partitions therefore we generate a
           -- Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the partition columns.
           DENSE_RANK() OVER (ORDER BY tags, subclass, layer) as cluster_group
    FROM linestrings_to_merge;

    -- Drop temporary tables early to save resources
    DROP TABLE linestrings_to_merge;

    -- Create index on cluster columns and analyze the created table to speed up subsequent queries
    CREATE INDEX ON clustered_linestrings_to_merge (cluster_group, cluster);
    ANALYZE clustered_linestrings_to_merge;

    -- Create temporary Merged-LineString to Source-LineStrings-ID table to temporarily store relations before they have
    -- been intersected
    CREATE TEMPORARY TABLE inserted_relations
    (LIKE osm_transportation_name_linestring_source_ids INCLUDING INDEXES);

    WITH inserted_linestrings AS (
        -- Merge LineStrings of each cluster and insert them
        INSERT INTO osm_transportation_name_linestring(source, geometry, source_ids, tags, highway, subclass,
                                                       z_order)
        SELECT 1 AS source, (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
               -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the geometries
               -- to merge. https://postgis.net/docs/ST_Union.html
               -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString
               -- if more than two LineStrings form an intersection or no intersection could be found.
               -- https://postgis.net/docs/ST_LineMerge.html
               -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
               -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
               array_agg(osm_id) AS source_ids, tags, 'shipway' AS highway, subclass, min(z_order) AS z_order
        FROM clustered_linestrings_to_merge
        GROUP BY cluster_group, cluster, tags, subclass, layer
        RETURNING id, source, source_ids
    )
    -- Store OSM-IDs of Source-LineStrings
    INSERT INTO inserted_relations (id, source, source_id)
    SELECT id, source, unnest(source_ids) AS source_id
    FROM inserted_linestrings
    ON CONFLICT (id, source, source_id) DO NOTHING;

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
        INSERT INTO osm_transportation_name_linestring_source_ids (id, source, source_id)
        SELECT m.id, m.source, source_id
        FROM osm_transportation_name_linestring m, inserted_relations s
        WHERE (
            EXISTS(
                SELECT NULL
                FROM osm_shipway_linestring
                WHERE m.id = s.id AND
                      osm_shipway_linestring.osm_id = s.source_id AND
                      ST_Intersects(osm_shipway_linestring.geometry, m.geometry)
            )
        ) ON CONFLICT (id, source, source_id) DO NOTHING
        RETURNING id, source_id
    )
    -- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations
    -- table
    UPDATE osm_transportation_name_linestring SET source_ids = q.source_ids
    FROM (
        SELECT id, array_agg(source_id) AS source_ids
        FROM intersected_relations
        GROUP BY id
    ) q
    WHERE osm_transportation_name_linestring.id = q.id;

    -- Cleanup
    DROP TABLE inserted_relations;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation_name.shipway_changes;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation_name.updates_shipway;

    RAISE LOG 'Refresh transportation_name shipway done in %', age(clock_timestamp(), t);

    -- Update gen1, gen2, gen3 and gen4 tables
    PERFORM update_transportation_name_linestring_gen(FALSE);

    RETURN NULL;
END;
$BODY$ LANGUAGE plpgsql;

-- Indexes for queries originating from transportation_name.refresh_shipway_linestring() function
CREATE INDEX IF NOT EXISTS transportation_name_shipway_changes_is_old_idx
    ON transportation_name.shipway_changes (is_old);

CREATE OR REPLACE FUNCTION transportation_name.refresh_aerialway_linestring() RETURNS trigger AS
$BODY$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation_name aerialway';

    -- REFRESH osm_transportation_name_linestring from osm_aerialway_linestring

    -- Analyze tracking and source tables before performing update
    ANALYZE transportation_name.name_changes;
    ANALYZE osm_aerialway_linestring;

    -- Fetch updated and deleted Merged-LineString from relation-table filtering for each Merged-LineString which
    -- contains an updated Source-LineString.
    -- Additionally attach a list of Source-LineString-IDs to each Merged-LineString in order to unnest them later.
    CREATE TEMPORARY TABLE affected_merged_linestrings AS
    SELECT m.id, array_agg(source_id) AS source_ids
    FROM osm_transportation_name_linestring_source_ids m
    WHERE m.source = 2 AND EXISTS(
        SELECT NULL
        FROM transportation_name.name_changes c
        WHERE c.is_old IS TRUE AND c.osm_id = m.source_id
    )
    GROUP BY id;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_merged_linestrings (id);
    ANALYZE affected_merged_linestrings;

    -- Delete all Merged-LineStrings which contained an updated or deleted Source-LineString
    DELETE
    FROM osm_transportation_name_linestring m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;
    DELETE
    FROM osm_transportation_name_linestring_source_ids m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;

    -- Analyze the tables affected by the delete-query in order to speed up subsequent queries
    ANALYZE osm_transportation_name_linestring;
    ANALYZE osm_transportation_name_linestring_source_ids;

    -- Create a table containing the IDs of all Source-LineStrings affected by this update
    CREATE TEMPORARY TABLE affected_source_linestrings AS
    -- Get Source-LineString-IDs of deleted or updated elements
    SELECT unnest(affected_merged_linestrings.source_ids) AS osm_id
    FROM affected_merged_linestrings
    UNION
    -- Get Source-LineString-IDs of inserted or updated elements
    SELECT osm_id FROM transportation_name.aerialway_changes WHERE is_old IS FALSE
    ORDER BY osm_id;

    -- Drop temporary tables early to save resources
    DROP TABLE affected_merged_linestrings;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_source_linestrings (osm_id);
    ANALYZE affected_source_linestrings;

    -- Create a table containing all LineStrings which should be merged
    CREATE TEMPORARY TABLE linestrings_to_merge AS
    -- Add all Source-LineStrings affected by this update
    SELECT osm_id, NULL::INTEGER AS id, geometry,
           transportation_name_tags(
               NULL::geometry, tags, name, name_en, name_de
           ) AS tags, aerialway AS subclass, layer, z_order
    FROM osm_aerialway_linestring
    WHERE EXISTS(
        SELECT NULL
        FROM affected_source_linestrings
        WHERE affected_source_linestrings.osm_id = osm_aerialway_linestring.osm_id
    ) AND (
        name <> ''
    );

    -- Drop temporary tables early to save resources
    DROP TABLE affected_source_linestrings;

    -- Create index on geometry column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge USING GIST (geometry);
    ANALYZE linestrings_to_merge;

    -- Add all Merged-LineStrings intersecting with Source-LineStrings affected by this update
    INSERT INTO linestrings_to_merge
    SELECT unnest(source_ids) AS osm_id, id, geometry, tags, subclass, layer, z_order
    FROM osm_transportation_name_linestring
    WHERE EXISTS(
        SELECT NULL FROM linestrings_to_merge
        WHERE osm_transportation_name_linestring.source = 2 AND ST_Intersects(
            linestrings_to_merge.geometry, osm_transportation_name_linestring.geometry
        )
    );

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge (id);
    ANALYZE linestrings_to_merge;

    -- Delete all Merged-LineStrings intersecting with Source-LineStrings affected by this update.
    -- We can use the linestrings_to_merge table since Source-LineStrings affected by this update and present in the
    -- table will have their ID-Column set to NULL by the previous query.
    DELETE
    FROM osm_transportation_name_linestring m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;
    DELETE
    FROM osm_transportation_name_linestring_source_ids m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;

    -- Create table containing all LineStrings to and create clusters of intersecting LineStrings partitioned by their
    -- groups
    CREATE TEMPORARY TABLE clustered_linestrings_to_merge AS
    SELECT *,
           -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points to 1.
           -- https://postgis.net/docs/ST_ClusterDBSCAN.html
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (PARTITION BY tags, subclass, layer) AS cluster,
           -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition starting at 0.
           -- This leads to clusters having the same ID across multiple partitions therefore we generate a
           -- Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the partition columns.
           DENSE_RANK() OVER (ORDER BY tags, subclass, layer) as cluster_group
    FROM linestrings_to_merge;

    -- Drop temporary tables early to save resources
    DROP TABLE linestrings_to_merge;

    -- Create index on cluster columns and analyze the created table to speed up subsequent queries
    CREATE INDEX ON clustered_linestrings_to_merge (cluster_group, cluster);
    ANALYZE clustered_linestrings_to_merge;

    -- Create temporary Merged-LineString to Source-LineStrings-ID table to temporarily store relations before they have
    -- been intersected
    CREATE TEMPORARY TABLE inserted_relations
    (LIKE osm_transportation_name_linestring_source_ids INCLUDING INDEXES);

    WITH inserted_linestrings AS (
        -- Merge LineStrings of each cluster and insert them
        INSERT INTO osm_transportation_name_linestring(source, geometry, source_ids, tags, highway, subclass,
                                                       z_order)
        SELECT 2 AS source, (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
               -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the geometries
               -- to merge. https://postgis.net/docs/ST_Union.html
               -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString
               -- if more than two LineStrings form an intersection or no intersection could be found.
               -- https://postgis.net/docs/ST_LineMerge.html
               -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
               -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
               array_agg(osm_id) AS source_ids, tags, 'aerialway' AS highway, subclass, min(z_order) AS z_order
        FROM clustered_linestrings_to_merge
        GROUP BY cluster_group, cluster, tags, subclass, layer
        RETURNING id, source, source_ids
    )
    -- Store OSM-IDs of Source-LineStrings
    INSERT INTO inserted_relations (id, source, source_id)
    SELECT id, source, unnest(source_ids) AS source_id
    FROM inserted_linestrings
    ON CONFLICT (id, source, source_id) DO NOTHING;

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
        INSERT INTO osm_transportation_name_linestring_source_ids (id, source, source_id)
        SELECT m.id, m.source, source_id
        FROM osm_transportation_name_linestring m, inserted_relations s
        WHERE (
            EXISTS(
                SELECT NULL
                FROM osm_aerialway_linestring
                WHERE m.id = s.id AND
                      osm_aerialway_linestring.osm_id = s.source_id AND
                      ST_Intersects(osm_aerialway_linestring.geometry, m.geometry)
            )
        ) ON CONFLICT (id, source, source_id) DO NOTHING
        RETURNING id, source_id
    )
    -- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations
    -- table
    UPDATE osm_transportation_name_linestring SET source_ids = q.source_ids
    FROM (
        SELECT id, array_agg(source_id) AS source_ids
        FROM intersected_relations
        GROUP BY id
    ) q
    WHERE osm_transportation_name_linestring.id = q.id;

    -- Cleanup
    DROP TABLE inserted_relations;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation_name.aerialway_changes;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation_name.updates_aerialway;

    RAISE LOG 'Refresh transportation_name aerialway done in %', age(clock_timestamp(), t);

    -- Update gen1, gen2, gen3 and gen4 tables
    PERFORM update_transportation_name_linestring_gen(FALSE);

    RETURN NULL;
END;
$BODY$ LANGUAGE plpgsql;

-- Indexes for queries originating from transportation_name.refresh_aerialway_linestring() function
CREATE INDEX IF NOT EXISTS transportation_name_aerialway_changes_is_old_idx
    ON transportation_name.aerialway_changes (is_old);

-- Indexes for queries originating from transportation_name.refresh_* functions
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_source_idx
    ON osm_transportation_name_linestring (source);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_source_ids_source_id_idx
    ON osm_transportation_name_linestring_source_ids (source, source_id);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_source_ids_id_idx
    ON osm_transportation_name_linestring_source_ids (id);

CREATE TRIGGER trigger_store_transportation_name_network
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_transportation_name_network
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.name_network_store();

CREATE TRIGGER trigger_store_transportation_name_shipway
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_shipway_linestring
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.name_shipway_store();

CREATE TRIGGER trigger_store_transportation_name_aerialway
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_aerialway_linestring
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.name_aerialway_store();

CREATE TRIGGER trigger_store_transportation_name_linestring
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_transportation_name_linestring
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.name_linestring_store();

CREATE TRIGGER trigger_flag_name
    AFTER INSERT
    ON transportation_name.name_changes
    FOR EACH STATEMENT
EXECUTE PROCEDURE transportation_name.flag_name();

CREATE TRIGGER trigger_flag_shipway
    AFTER INSERT
    ON transportation_name.shipway_changes
    FOR EACH STATEMENT
EXECUTE PROCEDURE transportation_name.flag_shipway();

CREATE TRIGGER trigger_flag_aerialway
    AFTER INSERT
    ON transportation_name.aerialway_changes
    FOR EACH STATEMENT
EXECUTE PROCEDURE transportation_name.flag_aerialway();

CREATE CONSTRAINT TRIGGER trigger_refresh_name
    AFTER INSERT
    ON transportation_name.updates_name
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.refresh_name();

CREATE CONSTRAINT TRIGGER trigger_refresh_shipway
    AFTER INSERT
    ON transportation_name.updates_shipway
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.refresh_shipway_linestring();

CREATE CONSTRAINT TRIGGER trigger_refresh_aerialway
    AFTER INSERT
    ON transportation_name.updates_aerialway
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE transportation_name.refresh_aerialway_linestring();
