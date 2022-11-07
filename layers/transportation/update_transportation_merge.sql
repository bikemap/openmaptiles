DROP TRIGGER IF EXISTS trigger_store_osm_transportation_merge_linestring_gen_z8 ON osm_transportation_merge_linestring_gen_z8;
DROP TRIGGER IF EXISTS trigger_store_transportation_highway_linestring_gen_z9 ON osm_transportation_merge_linestring_gen_z9;
DROP TRIGGER IF EXISTS trigger_flag_transportation_z9 ON osm_transportation_merge_linestring_gen_z9;
DROP TRIGGER IF EXISTS trigger_refresh_z8 ON transportation.updates_z9;
DROP TRIGGER IF EXISTS trigger_store_transportation_highway_linestring_gen_z11 ON osm_highway_linestring_gen_z11;
DROP TRIGGER IF EXISTS trigger_store_osm_transportation_merge_linestring_gen_z11 ON osm_transportation_merge_linestring_gen_z11;
DROP TRIGGER IF EXISTS trigger_flag_transportation_z11 ON osm_highway_linestring_gen_z11;
DROP TRIGGER IF EXISTS trigger_refresh_z11 ON transportation.updates_z11;
DROP TRIGGER IF EXISTS trigger_store_transportation_name_network ON osm_transportation_name_network;

-- Instead of using relations to find out the road names we
-- stitch together the touching ways with the same name
-- to allow for nice label rendering
-- Because this works well for roads that do not have relations as well

-- etldoc: osm_highway_linestring ->  osm_transportation_name_network
-- etldoc: osm_route_member ->  osm_transportation_name_network
CREATE TABLE IF NOT EXISTS osm_transportation_name_network AS
SELECT
    geometry,
    osm_id,
    tags || get_basic_names(tags, geometry) AS tags,
    ref,
    highway,
    subclass,
    brunnel,
    "level",
    sac_scale,
    layer,
    indoor,
    network_type,
    network_name,
    route_1, route_2, route_3, route_4, route_5, route_6,
    z_order,
    route_rank
FROM (
    SELECT DISTINCT ON (hl.osm_id)
        hl.geometry,
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
            LEFT OUTER JOIN osm_route_member rm1 ON rm1.member = hl.osm_id AND rm1.concurrency_index=1
            LEFT OUTER JOIN osm_route_member rm2 ON rm2.member = hl.osm_id AND rm2.concurrency_index=2
            LEFT OUTER JOIN osm_route_member rm3 ON rm3.member = hl.osm_id AND rm3.concurrency_index=3
            LEFT OUTER JOIN osm_route_member rm4 ON rm4.member = hl.osm_id AND rm4.concurrency_index=4
            LEFT OUTER JOIN osm_route_member rm5 ON rm5.member = hl.osm_id AND rm5.concurrency_index=5
            LEFT OUTER JOIN osm_route_member rm6 ON rm6.member = hl.osm_id AND rm6.concurrency_index=6
    WHERE (hl.name <> '' OR hl.ref <> '' OR rm1.ref <> '' OR rm1.network <> '')
      AND hl.highway <> ''
) AS t;

-- Create Primary-Key for osm_transportation_name_network table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_name_network' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_name_network ADD PRIMARY KEY (osm_id);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Geometry Index
CREATE INDEX IF NOT EXISTS osm_transportation_name_network_geometry_idx
    ON osm_transportation_name_network USING gist (geometry);

-- etldoc: osm_highway_linestring_gen_z11 ->  osm_transportation_merge_linestring_gen_z11
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z11(
    geometry geometry('LineString'),
    id SERIAL,
    osm_id bigint,
    source_ids bigint[],
    highway character varying,
    network character varying,
    construction character varying,
    is_bridge boolean,
    is_tunnel boolean,
    is_ford boolean,
    expressway boolean,
    z_order integer,
    bicycle character varying,
    foot character varying,
    horse character varying,
    mtb_scale character varying,
    sac_scale character varying,
    access text,
    toll boolean,
    layer integer,
    cycleway text,
    cycleway_both text,
    cycleway_left text,
    cycleway_right text,
    cycleway_street text
);

-- Create osm_transportation_merge_linestring_gen_z10 as a copy of osm_transportation_merge_linestring_gen_z11 but
-- drop the "source_ids" column. This can be done because z10 and z9 tables are only simplified and not merged,
-- therefore relations to sources are direct via the id column.
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z10
    (LIKE osm_transportation_merge_linestring_gen_z11);
ALTER TABLE osm_transportation_merge_linestring_gen_z10 DROP COLUMN IF EXISTS source_ids;

-- Create osm_transportation_merge_linestring_gen_z9 as a copy of osm_transportation_merge_linestring_gen_z10
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z9
    (LIKE osm_transportation_merge_linestring_gen_z10);

-- Create OneToMany-Relation-Table storing relations of a Merged-LineString in table
-- osm_transportation_merge_linestring_gen_z11 to Source-LineStrings from table osm_highway_linestring_gen_z11
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z11_source_ids(
    id int,
    source_id bigint,
    PRIMARY KEY (id, source_id)
);

-- Create temporary Merged-LineString to Source-LineStrings-ID table to temporarily store relations before they have
-- been intersected
CREATE TEMPORARY TABLE initial_osm_transportation_merge_linestring_gen_z11_source_ids
(LIKE osm_transportation_merge_linestring_gen_z11_source_ids INCLUDING INDEXES);

-- Ensure tables are emtpy if they haven't been created
TRUNCATE osm_transportation_merge_linestring_gen_z11;
TRUNCATE osm_transportation_merge_linestring_gen_z11_source_ids;

WITH inserted_linestrings AS (
    -- Merge LineStrings from osm_highway_linestring_gen_z11 by grouping them and creating intersecting clusters of
    -- each group via ST_ClusterDBSCAN
    INSERT INTO osm_transportation_merge_linestring_gen_z11 (geometry, source_ids, highway, network, construction,
                                                             is_bridge, is_tunnel, is_ford, expressway, z_order,
                                                             bicycle, foot, horse, mtb_scale, sac_scale, access, toll,
                                                             layer, cycleway, cycleway_both, cycleway_left,
                                                             cycleway_right, cycleway_street)
    SELECT (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
           -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the geometries to
           -- merge. https://postgis.net/docs/ST_Union.html
           -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString if
           -- more than two LineStrings form an intersection or no intersection could be found.
           -- https://postgis.net/docs/ST_LineMerge.html
           -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
           -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
           array_agg(osm_id) as source_ids,
           highway,
           network,
           construction,
           is_bridge,
           is_tunnel,
           is_ford,
           expressway,
           min(z_order) as z_order,
           bicycle,
           foot,
           horse,
           mtb_scale,
           sac_scale,
           CASE
               WHEN access IN ('private', 'no') THEN 'no'
               ELSE NULL::text END AS access,
           toll,
           layer,
           cycleway,
           cycleway_both,
           cycleway_left,
           cycleway_right,
           cycleway_street
    FROM (
        SELECT *,
               -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points to 1
               -- https://postgis.net/docs/ST_ClusterDBSCAN.html
               ST_ClusterDBSCAN(geometry, 0, 1) OVER (
                   PARTITION BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle,
                                foot, horse, mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both,
                                cycleway_left, cycleway_right, cycleway_street
               ) AS cluster,
               -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition starting at 0.
               -- This leads to clusters having the same ID across multiple partitions therefore we generate a
               -- Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the partition columns.
               DENSE_RANK() OVER (
                   ORDER BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle,
                            foot, horse, mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both,
                            cycleway_left, cycleway_right, cycleway_street
               ) as cluster_group
        FROM osm_highway_linestring_gen_z11
        WHERE network in ('icn', 'ncn', 'rcn', 'lcn') OR
        (
            highway IN (
                'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link', 'primary_link',
                'secondary_link', 'tertiary_link', 'busway', 'bus_guideway'
            ) OR (
                highway = 'construction' AND
                construction IN (
                    'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link', 'primary_link',
                    'secondary_link', 'tertiary_link', 'busway', 'bus_guideway'
                )
            )
        )
    ) q
    GROUP BY cluster_group, cluster, highway, network, construction, is_bridge, is_tunnel, is_ford, expressway,
             bicycle, foot, horse, mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left,
             cycleway_right, cycleway_street
    RETURNING id, source_ids
)
-- Store OSM-IDs of Source-LineStrings
INSERT INTO initial_osm_transportation_merge_linestring_gen_z11_source_ids (id, source_id)
SELECT id, unnest(source_ids) AS source_id
FROM inserted_linestrings
ON CONFLICT (id, source_id) DO NOTHING;

-- Geometry Index
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z11_geometry_idx
    ON osm_transportation_merge_linestring_gen_z11 USING gist (geometry);

-- Create Primary-Keys for osm_transportation_merge_linestring_gen_z11/z10/z9 tables
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_merge_linestring_gen_z11' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_merge_linestring_gen_z11 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_merge_linestring_gen_z10' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_merge_linestring_gen_z10 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_merge_linestring_gen_z9' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_merge_linestring_gen_z9 ADD PRIMARY KEY (id);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create index on id columns and analyze the initial Merged-LineString to Source-LineStrings-ID Relations table to
-- speed up subsequent queries
CREATE INDEX ON initial_osm_transportation_merge_linestring_gen_z11_source_ids (id, source_id);
ANALYZE initial_osm_transportation_merge_linestring_gen_z11_source_ids;

-- Store OSM-IDs of Source-LineStrings by intersecting Merged-LineStrings with their sources. This required because
-- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString if
-- more than two LineStrings form an intersection or no intersection could be found.
-- Execute after indexes have been created on osm_transportation_merge_linestring_gen_z11 to improve performance
INSERT INTO osm_transportation_merge_linestring_gen_z11_source_ids (id, source_id)
SELECT m.id, source_id
FROM osm_transportation_merge_linestring_gen_z11 m, initial_osm_transportation_merge_linestring_gen_z11_source_ids s
WHERE (
    EXISTS(
        SELECT NULL
        FROM osm_highway_linestring_gen_z11
        WHERE m.id = s.id AND
              osm_highway_linestring_gen_z11.osm_id = s.source_id AND
              ST_Intersects(osm_highway_linestring_gen_z11.geometry, m.geometry)
    )
) ON CONFLICT (id, source_id) DO NOTHING;

-- Drop temporary tables early to save resources
DROP TABLE initial_osm_transportation_merge_linestring_gen_z11_source_ids;

-- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations table
-- Execute after indexes have been created on osm_transportation_merge_linestring_gen_z11 to improve performance
UPDATE osm_transportation_merge_linestring_gen_z11 SET source_ids = q.source_ids
FROM (
    SELECT id, array_agg(source_id) AS source_ids
    FROM osm_transportation_merge_linestring_gen_z11_source_ids
    GROUP BY id
) q
WHERE osm_transportation_merge_linestring_gen_z11.id = q.id;

CREATE SCHEMA IF NOT EXISTS transportation;

CREATE TABLE IF NOT EXISTS transportation.changes_z9_z10
(
    is_old boolean,
    id int,
    PRIMARY KEY (id, is_old)
);

CREATE OR REPLACE FUNCTION insert_transportation_merge_linestring_gen_z10(full_update bool) RETURNS void AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation z9 10';

    -- Analyze tracking and source tables before performing update
    ANALYZE transportation.changes_z9_z10;
    ANALYZE osm_transportation_merge_linestring_gen_z11;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_merge_linestring_gen_z10
    USING transportation.changes_z9_z10
    WHERE full_update IS TRUE OR (
        transportation.changes_z9_z10.is_old IS TRUE AND
        transportation.changes_z9_z10.id = osm_transportation_merge_linestring_gen_z10.id
    );

    -- etldoc: osm_transportation_merge_linestring_gen_z11 -> osm_transportation_merge_linestring_gen_z10
    INSERT INTO osm_transportation_merge_linestring_gen_z10
    SELECT ST_Simplify(geometry, ZRes(12)) AS geometry,
        id,
        osm_id,
        highway,
        network,
        construction,
        is_bridge,
        is_tunnel,
        is_ford,
        expressway,
        z_order,
        bicycle,
        foot,
        horse,
        mtb_scale,
        sac_scale,
        access,
        toll,
        layer,
        cycleway,
        cycleway_both,
        cycleway_left,
        cycleway_right,
        cycleway_street
    FROM osm_transportation_merge_linestring_gen_z11
    WHERE (full_update IS TRUE OR EXISTS(
            SELECT NULL FROM transportation.changes_z9_z10
            WHERE transportation.changes_z9_z10.is_old IS FALSE AND
                  transportation.changes_z9_z10.id = osm_transportation_merge_linestring_gen_z11.id
        ))
        AND (
            network in ('icn', 'ncn', 'rcn') OR (
                highway NOT IN ('tertiary', 'tertiary_link', 'busway', 'bus_guideway')
                AND construction NOT IN ('tertiary', 'tertiary_link', 'busway', 'bus_guideway')
            )
        )
    ON CONFLICT (id) DO UPDATE SET osm_id = excluded.osm_id, highway = excluded.highway, network = excluded.network,
                                   construction = excluded.construction, is_bridge = excluded.is_bridge,
                                   is_tunnel = excluded.is_tunnel, is_ford = excluded.is_ford,
                                   expressway = excluded.expressway, z_order = excluded.z_order,
                                   bicycle = excluded.bicycle, foot = excluded.foot, horse = excluded.horse,
                                   mtb_scale = excluded.mtb_scale, sac_scale = excluded.sac_scale,
                                   access = excluded.access, toll = excluded.toll, layer = excluded.layer,
                                   cycleway = excluded.cycleway, cycleway_both = excluded.cycleway_both,
                                   cycleway_left = excluded.cycleway_left, cycleway_right = excluded.cycleway_right,
                                   cycleway_street = excluded.cycleway_street;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_merge_linestring_gen_z9
    USING transportation.changes_z9_z10
    WHERE full_update IS TRUE OR (
        transportation.changes_z9_z10.is_old IS TRUE AND
        transportation.changes_z9_z10.id = osm_transportation_merge_linestring_gen_z9.id
    );

    -- Analyze source table
    ANALYZE osm_transportation_merge_linestring_gen_z10;

    -- etldoc: osm_transportation_merge_linestring_gen_z10 -> osm_transportation_merge_linestring_gen_z9
    INSERT INTO osm_transportation_merge_linestring_gen_z9
    SELECT ST_Simplify(geometry, ZRes(11)) AS geometry,
        id,
        osm_id,
        highway,
        network,
        construction,
        is_bridge,
        is_tunnel,
        is_ford,
        expressway,
        z_order,
        bicycle,
        foot,
        horse,
        mtb_scale,
        sac_scale,
        access,
        toll,
        layer,
        cycleway,
        cycleway_both,
        cycleway_left,
        cycleway_right,
        cycleway_street
    FROM osm_transportation_merge_linestring_gen_z10
    WHERE full_update IS TRUE OR EXISTS(
            SELECT NULL FROM transportation.changes_z9_z10
            WHERE transportation.changes_z9_z10.is_old IS FALSE AND
                  transportation.changes_z9_z10.id = osm_transportation_merge_linestring_gen_z10.id
            )
    ON CONFLICT (id) DO UPDATE SET osm_id = excluded.osm_id, highway = excluded.highway, network = excluded.network,
                                   construction = excluded.construction, is_bridge = excluded.is_bridge,
                                   is_tunnel = excluded.is_tunnel, is_ford = excluded.is_ford,
                                   expressway = excluded.expressway, z_order = excluded.z_order,
                                   bicycle = excluded.bicycle, foot = excluded.foot, horse = excluded.horse,
                                   mtb_scale = excluded.mtb_scale, sac_scale = excluded.sac_scale,
                                   access = excluded.access, toll = excluded.toll, layer = excluded.layer,
                                   cycleway = excluded.cycleway, cycleway_both = excluded.cycleway_both,
                                   cycleway_left = excluded.cycleway_left, cycleway_right = excluded.cycleway_right,
                                   cycleway_street = excluded.cycleway_street;

    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.changes_z9_z10;

    RAISE LOG 'Refresh transportation z9 10 done in %', age(clock_timestamp(), t);
END;
$$ LANGUAGE plpgsql;

-- Ensure tables are emtpy if they haven't been created
TRUNCATE osm_transportation_merge_linestring_gen_z10;
TRUNCATE osm_transportation_merge_linestring_gen_z9;

-- Indexes which can be utilized during full-update for queries originating from
-- insert_transportation_merge_linestring_gen_z10() function
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z11_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z11 (network, highway, construction)
    WHERE network in ('icn', 'ncn', 'rcn') OR (
        highway NOT IN ('tertiary', 'tertiary_link', 'busway')
        AND construction NOT IN ('tertiary', 'tertiary_link', 'busway')
    );


SELECT insert_transportation_merge_linestring_gen_z10(TRUE);

-- Geometry Indexes
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z10_geometry_idx
    ON osm_transportation_merge_linestring_gen_z10 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z9_geometry_idx
    ON osm_transportation_merge_linestring_gen_z9 USING gist (geometry);

-- etldoc: osm_transportation_merge_linestring_gen_z9 -> osm_transportation_merge_linestring_gen_z8
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z8(
    geometry geometry('LineString'),
    id SERIAL,
    osm_id bigint,
    source_ids int[],
    highway character varying,
    network character varying,
    construction character varying,
    is_bridge boolean,
    is_tunnel boolean,
    is_ford boolean,
    expressway boolean,
    z_order integer
);

-- Create osm_transportation_merge_linestring_gen_z7 as a copy of osm_transportation_merge_linestring_gen_z8 but
-- drop the "source_ids" column. This can be done because z7 to z5 tables are only simplified and not merged,
-- therefore relations to sources are direct via the id column.
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z7
    (LIKE osm_transportation_merge_linestring_gen_z8);
ALTER TABLE osm_transportation_merge_linestring_gen_z7 DROP COLUMN IF EXISTS source_ids;

-- Create osm_transportation_merge_linestring_gen_z6 as a copy of osm_transportation_merge_linestring_gen_z7
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z6
    (LIKE osm_transportation_merge_linestring_gen_z7);

-- Create osm_transportation_merge_linestring_gen_z5 as a copy of osm_transportation_merge_linestring_gen_z6
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z5
    (LIKE osm_transportation_merge_linestring_gen_z6);

-- Create osm_transportation_merge_linestring_gen_z4 as a copy of osm_transportation_merge_linestring_gen_z5
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z4
    (LIKE osm_transportation_merge_linestring_gen_z5);

-- Create OneToMany-Relation-Table storing relations of a Merged-LineString in table
-- osm_transportation_merge_linestring_gen_z8 to Source-LineStrings from table
-- osm_transportation_merge_linestring_gen_z9
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_source_ids(
    id int,
    source_id bigint,
    PRIMARY KEY (id, source_id)
);

-- Create temporary Merged-LineString to Source-LineStrings-ID table to temporarily store relations before they have
-- been intersected
CREATE TEMPORARY TABLE initial_osm_transportation_merge_linestring_gen_z8_source_ids
(LIKE osm_transportation_merge_linestring_gen_z8_source_ids INCLUDING INDEXES);

-- Ensure tables are emtpy if they haven't been created
TRUNCATE osm_transportation_merge_linestring_gen_z8;
TRUNCATE osm_transportation_merge_linestring_gen_z8_source_ids;

-- Indexes for filling and updating osm_transportation_merge_linestring_gen_z8 table
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z9_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z9 (network, highway, construction, ST_IsValid(geometry), access)
    WHERE (
        network IN ('icn', 'ncn', 'rcn') OR
        highway IN ('motorway', 'trunk', 'primary') OR
        construction IN ('motorway', 'trunk', 'primary')
    ) AND ST_IsValid(geometry) AND access IS NULL;

WITH inserted_linestrings AS (
    -- Merge LineStrings from osm_transportation_merge_linestring_gen_z9 by grouping them and creating intersecting
    -- clusters of each group via ST_ClusterDBSCAN
    INSERT INTO osm_transportation_merge_linestring_gen_z8(geometry, source_ids, highway, network, construction, is_bridge,
                                                           is_tunnel, is_ford, expressway, z_order)
    SELECT (ST_Dump(ST_Simplify(ST_LineMerge(ST_Union(geometry)), ZRes(10)))).geom AS geometry,
           -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the geometries to
           -- merge. https://postgis.net/docs/ST_Union.html
           -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString if
           -- more than two LineStrings form an intersection or no intersection could be found.
           -- https://postgis.net/docs/ST_LineMerge.html
           -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
           -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
           array_agg(id) AS source_ids,
           highway,
           network,
           construction,
           is_bridge,
           is_tunnel,
           is_ford,
           expressway,
           min(z_order) as z_order
    FROM (
        SELECT *,
               -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points to 1
               -- https://postgis.net/docs/ST_ClusterDBSCAN.html
               ST_ClusterDBSCAN(geometry, 0, 1) OVER (
                   PARTITION BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
               ) AS cluster,
               -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition starting at 0.
               -- This leads to clusters having the same ID across multiple partitions therefore we generate a
               -- Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the partition columns.
               DENSE_RANK() OVER (
                   ORDER BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
               ) as cluster_group
        FROM osm_transportation_merge_linestring_gen_z9
        WHERE (
            network IN ('icn', 'ncn', 'rcn') OR
            highway IN ('motorway', 'trunk', 'primary') OR
            construction IN ('motorway', 'trunk', 'primary')
        ) AND ST_IsValid(geometry) AND access IS NULL
    ) q
    GROUP BY cluster_group, cluster, highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
    RETURNING id, source_ids
)
INSERT INTO initial_osm_transportation_merge_linestring_gen_z8_source_ids (id, source_id)
SELECT id, unnest(source_ids) AS source_id
FROM inserted_linestrings
ON CONFLICT (id, source_id) DO NOTHING;

-- Geometry Index
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_geometry_idx
    ON osm_transportation_merge_linestring_gen_z8 USING gist (geometry);

-- Create Primary-Keys for osm_transportation_merge_linestring_gen_z8/z7/z6/z5/z4 tables
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_merge_linestring_gen_z8' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_merge_linestring_gen_z8 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_merge_linestring_gen_z7' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_merge_linestring_gen_z7 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_merge_linestring_gen_z6' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_merge_linestring_gen_z6 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_merge_linestring_gen_z5' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_merge_linestring_gen_z5 ADD PRIMARY KEY (id);
    END IF;

    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_transportation_merge_linestring_gen_z4' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE osm_transportation_merge_linestring_gen_z4 ADD PRIMARY KEY (id);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create index on id columns and analyze the initial Merged-LineString to Source-LineStrings-ID Relations table to
-- speed up subsequent queries
CREATE INDEX ON initial_osm_transportation_merge_linestring_gen_z8_source_ids (id, source_id);
ANALYZE initial_osm_transportation_merge_linestring_gen_z8_source_ids;

-- Store OSM-IDs of Source-LineStrings by intersecting Merged-LineStrings with their sources. This required because
-- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString if
-- more than two LineStrings form an intersection or no intersection could be found.
-- Execute after indexes have been created on osm_transportation_merge_linestring_gen_z11 to improve performance
INSERT INTO osm_transportation_merge_linestring_gen_z8_source_ids (id, source_id)
SELECT m.id, source_id
FROM osm_transportation_merge_linestring_gen_z8 m, initial_osm_transportation_merge_linestring_gen_z8_source_ids s
WHERE (
    EXISTS(
        SELECT NULL
        FROM osm_transportation_merge_linestring_gen_z9
        WHERE m.id = s.id AND
              osm_transportation_merge_linestring_gen_z9.id = s.source_id AND
              ST_Intersects(osm_transportation_merge_linestring_gen_z9.geometry, m.geometry)
    )
) ON CONFLICT (id, source_id) DO NOTHING;

-- Drop temporary tables early to save resources
DROP TABLE initial_osm_transportation_merge_linestring_gen_z8_source_ids;

-- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations Table
-- Execute after indexes have been created on osm_transportation_merge_linestring_gen_z11 to improve performance
UPDATE osm_transportation_merge_linestring_gen_z8 SET source_ids = q.source_ids
FROM (
    SELECT id, array_agg(source_id) AS source_ids
    FROM osm_transportation_merge_linestring_gen_z8_source_ids
    GROUP BY id
) q
WHERE osm_transportation_merge_linestring_gen_z8.id = q.id;

CREATE TABLE IF NOT EXISTS transportation.changes_z4_z5_z6_z7
(
    is_old boolean,
    id int,
    PRIMARY KEY (id, is_old)
);

CREATE OR REPLACE FUNCTION insert_transportation_merge_linestring_gen_z7(full_update boolean) RETURNS void AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation z4 z5 z6 z7';

    -- Analyze tracking and source tables before performing update
    ANALYZE transportation.changes_z4_z5_z6_z7;
    ANALYZE osm_transportation_merge_linestring_gen_z8;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_merge_linestring_gen_z7
    USING transportation.changes_z4_z5_z6_z7
    WHERE full_update IS TRUE OR (
        transportation.changes_z4_z5_z6_z7.is_old IS TRUE AND
        transportation.changes_z4_z5_z6_z7.id = osm_transportation_merge_linestring_gen_z7.id
    );

    -- etldoc: osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z7
    INSERT INTO osm_transportation_merge_linestring_gen_z7
    SELECT ST_Simplify(geometry, ZRes(9)) AS geometry,
        id,
        osm_id,
        highway,
        network,
        construction,
        is_bridge,
        is_tunnel,
        is_ford,
        expressway,
        z_order
    FROM osm_transportation_merge_linestring_gen_z8
        -- Current view: motorway/trunk/primary
    WHERE
        (full_update IS TRUE OR EXISTS(
            SELECT NULL FROM transportation.changes_z4_z5_z6_z7
            WHERE transportation.changes_z4_z5_z6_z7.is_old IS FALSE AND
                  transportation.changes_z4_z5_z6_z7.id = osm_transportation_merge_linestring_gen_z8.id
        )) AND
        (network IN ('icn', 'ncn') OR ST_Length(geometry) > 50)
    ON CONFLICT (id) DO UPDATE SET osm_id = excluded.osm_id, highway = excluded.highway, network = excluded.network,
                                   construction = excluded.construction, is_bridge = excluded.is_bridge,
                                   is_tunnel = excluded.is_tunnel, is_ford = excluded.is_ford,
                                   expressway = excluded.expressway, z_order = excluded.z_order;

    -- Analyze source table
    ANALYZE osm_transportation_merge_linestring_gen_z7;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_merge_linestring_gen_z6
    USING transportation.changes_z4_z5_z6_z7
    WHERE full_update IS TRUE OR (
        transportation.changes_z4_z5_z6_z7.is_old IS TRUE AND
        transportation.changes_z4_z5_z6_z7.id = osm_transportation_merge_linestring_gen_z6.id
    );

    -- etldoc: osm_transportation_merge_linestring_gen_z7 -> osm_transportation_merge_linestring_gen_z6
    INSERT INTO osm_transportation_merge_linestring_gen_z6
    SELECT ST_Simplify(geometry, ZRes(8)) AS geometry,
        id,
        osm_id,
        highway,
        network,
        construction,
        is_bridge,
        is_tunnel,
        is_ford,
        expressway,
        z_order
    FROM osm_transportation_merge_linestring_gen_z7
    WHERE
        (full_update IS TRUE OR EXISTS(
            SELECT NULL FROM transportation.changes_z4_z5_z6_z7
            WHERE transportation.changes_z4_z5_z6_z7.is_old IS FALSE AND
                  transportation.changes_z4_z5_z6_z7.id = osm_transportation_merge_linestring_gen_z7.id
        )) AND
        (highway IN ('motorway', 'trunk') OR construction IN ('motorway', 'trunk')) AND
        ST_Length(geometry) > 100
    ON CONFLICT (id) DO UPDATE SET osm_id = excluded.osm_id, highway = excluded.highway, network = excluded.network,
                                   construction = excluded.construction, is_bridge = excluded.is_bridge,
                                   is_tunnel = excluded.is_tunnel, is_ford = excluded.is_ford,
                                   expressway = excluded.expressway, z_order = excluded.z_order;

    -- Analyze source table
    ANALYZE osm_transportation_merge_linestring_gen_z6;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_merge_linestring_gen_z5
    USING transportation.changes_z4_z5_z6_z7
    WHERE full_update IS TRUE OR (
        transportation.changes_z4_z5_z6_z7.is_old IS TRUE AND
        transportation.changes_z4_z5_z6_z7.id = osm_transportation_merge_linestring_gen_z5.id
        );

    -- etldoc: osm_transportation_merge_linestring_gen_z6 -> osm_transportation_merge_linestring_gen_z5
    INSERT INTO osm_transportation_merge_linestring_gen_z5
    SELECT ST_Simplify(geometry, ZRes(7)) AS geometry,
        id,
        osm_id,
        highway,
        network,
        construction,
        is_bridge,
        is_tunnel,
        is_ford,
        expressway,
        z_order
    FROM osm_transportation_merge_linestring_gen_z6
    WHERE
        (full_update IS TRUE OR EXISTS(
            SELECT NULL FROM transportation.changes_z4_z5_z6_z7
            WHERE transportation.changes_z4_z5_z6_z7.is_old IS FALSE AND
                  transportation.changes_z4_z5_z6_z7.id = osm_transportation_merge_linestring_gen_z6.id
        )) AND
        -- Current view: motorway/trunk
        ST_Length(geometry) > 500
    ON CONFLICT (id) DO UPDATE SET osm_id = excluded.osm_id, highway = excluded.highway, network = excluded.network,
                                   construction = excluded.construction, is_bridge = excluded.is_bridge,
                                   is_tunnel = excluded.is_tunnel, is_ford = excluded.is_ford,
                                   expressway = excluded.expressway, z_order = excluded.z_order;

    -- Analyze source table
    ANALYZE osm_transportation_merge_linestring_gen_z5;

    -- Remove entries which have been deleted from source table
    DELETE FROM osm_transportation_merge_linestring_gen_z4
    USING transportation.changes_z4_z5_z6_z7
    WHERE full_update IS TRUE OR (
        transportation.changes_z4_z5_z6_z7.is_old IS TRUE AND
        transportation.changes_z4_z5_z6_z7.id = osm_transportation_merge_linestring_gen_z4.id
    );

    -- etldoc: osm_transportation_merge_linestring_gen_z5 -> osm_transportation_merge_linestring_gen_z4
    INSERT INTO osm_transportation_merge_linestring_gen_z4
    SELECT ST_Simplify(geometry, ZRes(6)) AS geometry,
        id,
        osm_id,
        highway,
        network,
        construction,
        is_bridge,
        is_tunnel,
        is_ford,
        expressway,
        z_order
    FROM osm_transportation_merge_linestring_gen_z5
    WHERE
        (full_update IS TRUE OR EXISTS(
            SELECT NULL FROM transportation.changes_z4_z5_z6_z7
            WHERE transportation.changes_z4_z5_z6_z7.is_old IS FALSE AND
                  transportation.changes_z4_z5_z6_z7.id = osm_transportation_merge_linestring_gen_z5.id
        )) AND
        (highway = 'motorway' OR construction = 'motorway') AND
        ST_Length(geometry) > 1000
    ON CONFLICT (id) DO UPDATE SET osm_id = excluded.osm_id, highway = excluded.highway, network = excluded.network,
                                   construction = excluded.construction, is_bridge = excluded.is_bridge,
                                   is_tunnel = excluded.is_tunnel, is_ford = excluded.is_ford,
                                   expressway = excluded.expressway, z_order = excluded.z_order;

    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.changes_z4_z5_z6_z7;

    RAISE LOG 'Refresh transportation z4 z5 z6 z7 done in %', age(clock_timestamp(), t);
END;
$$ LANGUAGE plpgsql;

-- Ensure tables are emtpy if they haven't been created
TRUNCATE osm_transportation_merge_linestring_gen_z7;
TRUNCATE osm_transportation_merge_linestring_gen_z6;
TRUNCATE osm_transportation_merge_linestring_gen_z5;
TRUNCATE osm_transportation_merge_linestring_gen_z4;

-- Indexes which can be utilized during full-update for queries originating from
-- insert_transportation_merge_linestring_gen_z7() function
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z8 (network, ST_Length(geometry))
    WHERE (network IN ('icn', 'ncn') OR ST_Length(geometry) > 50);

SELECT insert_transportation_merge_linestring_gen_z7(TRUE);

-- Indexes for queries originating from insert_transportation_merge_linestring_gen_z7() function
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z7_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z7 (highway, construction, ST_Length(geometry))
    WHERE (highway IN ('motorway', 'trunk') OR construction IN ('motorway', 'trunk')) AND
          ST_Length(geometry) > 100;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z6_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z6 (ST_Length(geometry))
    WHERE ST_Length(geometry) > 500;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z5_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z5 (highway, construction, ST_Length(geometry))
    WHERE (highway = 'motorway' OR construction = 'motorway') AND
          ST_Length(geometry) > 1000;

-- Geometry Indexes
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z7_geometry_idx
    ON osm_transportation_merge_linestring_gen_z7 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z6_geometry_idx
    ON osm_transportation_merge_linestring_gen_z6 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z5_geometry_idx
    ON osm_transportation_merge_linestring_gen_z5 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z4_geometry_idx
    ON osm_transportation_merge_linestring_gen_z4 USING gist (geometry);


-- Handle updates on
-- osm_highway_linestring_gen_z11 -> osm_transportation_merge_linestring_gen_z11
-- osm_transportation_merge_linestring_gen_z11 -> osm_transportation_merge_linestring_gen_z10
-- osm_transportation_merge_linestring_gen_z11 -> osm_transportation_merge_linestring_gen_z9
CREATE TABLE IF NOT EXISTS transportation.changes_z11
(
    is_old boolean NULL,
    osm_id bigint,
    PRIMARY KEY (osm_id, is_old)
);

-- Store IDs of changed elements from osm_highway_linestring_gen_z11 table.
CREATE OR REPLACE FUNCTION transportation.store_gen_z11() RETURNS trigger AS
$$
BEGIN
    IF (tg_op = 'INSERT' OR tg_op = 'UPDATE') THEN
        INSERT INTO transportation.changes_z11(is_old, osm_id)
        VALUES (FALSE, new.osm_id)
        ON CONFLICT (osm_id, is_old) DO NOTHING;
    END IF;
    IF (tg_op = 'DELETE' OR tg_op = 'UPDATE') THEN
        INSERT INTO transportation.changes_z11(is_old, osm_id)
        VALUES (TRUE, old.osm_id)
        ON CONFLICT (osm_id, is_old) DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Store IDs of changed elements from osm_highway_linestring_gen_z9 table.
CREATE OR REPLACE FUNCTION transportation.store_merge_z11() RETURNS trigger AS
$$
BEGIN
    IF (tg_op = 'INSERT' OR tg_op = 'UPDATE') THEN
        INSERT INTO transportation.changes_z9_z10(is_old, id)
        VALUES (FALSE, new.id)
        ON CONFLICT (id, is_old) DO NOTHING;
    END IF;
    IF tg_op = 'DELETE' THEN
        INSERT INTO transportation.changes_z9_z10(is_old, id)
        VALUES (TRUE, old.id)
        ON CONFLICT (id, is_old) DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS transportation.updates_z11
(
    id serial PRIMARY KEY,
    t text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION transportation.flag_z11() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation.updates_z11(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation.refresh_z11() RETURNS trigger AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation z11';

    -- Analyze tracking and source tables before performing update
    ANALYZE transportation.changes_z11;
    ANALYZE osm_highway_linestring_gen_z11;

    -- Fetch updated and deleted Merged-LineString from relation-table filtering for each Merged-LineString which
    -- contains an updated Source-LineString.
    -- Additionally attach a list of Source-LineString-IDs to each Merged-LineString in order to unnest them later.
    CREATE TEMPORARY TABLE affected_merged_linestrings AS
    SELECT m.id, array_agg(source_id) AS source_ids
    FROM osm_transportation_merge_linestring_gen_z11_source_ids m
    WHERE EXISTS(
        SELECT NULL
        FROM transportation.changes_z11 c
        WHERE c.is_old IS TRUE AND c.osm_id = m.source_id
    )
    GROUP BY id;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_merged_linestrings (id);
    ANALYZE VERBOSE affected_merged_linestrings;

    -- Delete all Merged-LineStrings which contained an updated or deleted Source-LineString
    DELETE
    FROM osm_transportation_merge_linestring_gen_z11 m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;
    DELETE
    FROM osm_transportation_merge_linestring_gen_z11_source_ids m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;

    -- Analyze the tables affected by the delete-query in order to speed up subsequent queries
    ANALYZE osm_transportation_merge_linestring_gen_z11;
    ANALYZE osm_transportation_merge_linestring_gen_z11_source_ids;

    -- Create a table containing the IDs of all Source-LineStrings affected by this update
    CREATE TEMPORARY TABLE affected_source_linestrings AS
    -- Get Source-LineString-IDs of deleted or updated elements
    SELECT unnest(affected_merged_linestrings.source_ids) AS osm_id
    FROM affected_merged_linestrings
    UNION
    -- Get Source-LineString-IDs of inserted or updated elements
    SELECT osm_id FROM transportation.changes_z11 WHERE is_old IS FALSE
    ORDER BY osm_id;

    -- Drop temporary tables early to save resources
    DROP TABLE affected_merged_linestrings;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_source_linestrings (osm_id);
    ANALYZE affected_source_linestrings;

    -- Create a table containing all LineStrings which should be merged
    CREATE TEMPORARY TABLE linestrings_to_merge AS
    -- Add all Source-LineStrings affected by this update
    SELECT osm_id, NULL::INTEGER AS id, geometry, highway, network, construction, is_bridge,
           is_tunnel, is_ford, expressway, bicycle, foot, horse, mtb_scale, sac_scale,
           CASE WHEN access IN ('private', 'no') THEN 'no' ELSE NULL::text END AS access, toll, layer, cycleway,
           cycleway_both, cycleway_left, cycleway_right, cycleway_street, z_order
    FROM osm_highway_linestring_gen_z11
    WHERE EXISTS(
        SELECT NULL
        FROM affected_source_linestrings
        WHERE affected_source_linestrings.osm_id = osm_highway_linestring_gen_z11.osm_id
    ) AND (
        network in ('icn', 'ncn', 'rcn', 'lcn') OR
        (
            highway IN (
                'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link',
                'primary_link', 'secondary_link', 'tertiary_link', 'busway', 'bus_guideway'
            ) OR (
                highway = 'construction' AND
                construction IN (
                    'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link',
                    'primary_link', 'secondary_link', 'tertiary_link', 'busway', 'bus_guideway'
                )
            )
        )
    );

    -- Drop temporary tables early to save resources
    DROP TABLE affected_source_linestrings;

    -- Create index on geometry column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge USING GIST (geometry);
    ANALYZE linestrings_to_merge;

    -- Add all Merged-LineStrings intersecting with Source-LineStrings affected by this update
    INSERT INTO linestrings_to_merge
    SELECT unnest(source_ids) AS osm_id, id,
           geometry, highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle, foot, horse,
           mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left, cycleway_right,
           cycleway_street, z_order
    FROM osm_transportation_merge_linestring_gen_z11
    WHERE EXISTS(
        SELECT NULL FROM linestrings_to_merge
        WHERE ST_Intersects(
            linestrings_to_merge.geometry, osm_transportation_merge_linestring_gen_z11.geometry
        )
    );

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge (id);
    ANALYZE linestrings_to_merge;

    -- Delete all Merged-LineStrings intersecting with Source-LineStrings affected by this update.
    -- We can use the linestrings_to_merge table since Source-LineStrings affected by this update and present in the
    -- table will have their ID-Column set to NULL by the previous query.
    DELETE
    FROM osm_transportation_merge_linestring_gen_z11 m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;
    DELETE
    FROM osm_transportation_merge_linestring_gen_z11_source_ids m
    USING linestrings_to_merge
    WHERE linestrings_to_merge.id = m.id;

    -- Create table containing all LineStrings to and create clusters of intersecting LineStrings partitioned by their
    -- groups
    CREATE TEMPORARY TABLE clustered_linestrings_to_merge AS
    SELECT *,
           -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points to 1
           -- https://postgis.net/docs/ST_ClusterDBSCAN.html
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (
               PARTITION BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle, foot,
               horse, mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left, cycleway_right,
               cycleway_street
           ) AS cluster,
           -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition starting at 0.
           -- This leads to clusters having the same ID across multiple partitions therefore we generate a
           -- Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the partition columns.
           DENSE_RANK() OVER (
               ORDER BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle, foot, horse,
               mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left, cycleway_right,
               cycleway_street
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
    (LIKE osm_transportation_merge_linestring_gen_z11_source_ids INCLUDING INDEXES);

    WITH inserted_linestrings AS (
        -- Merge LineStrings of each cluster and insert them
        INSERT INTO osm_transportation_merge_linestring_gen_z11(geometry, source_ids, highway, network, construction,
                                                                is_bridge, is_tunnel, is_ford, expressway, z_order,
                                                                bicycle, foot, horse, mtb_scale, sac_scale, access,
                                                                toll, layer, cycleway, cycleway_both, cycleway_left,
                                                                cycleway_right, cycleway_street)
        SELECT (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
               -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the geometries to
               -- merge. https://postgis.net/docs/ST_Union.html
               -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString if
               -- more than two LineStrings form an intersection or no intersection could be found.
               -- https://postgis.net/docs/ST_LineMerge.html
               -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
               -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
               array_agg(osm_id) AS source_ids,
               highway,
               network,
               construction,
               is_bridge,
               is_tunnel,
               is_ford,
               expressway,
               min(z_order) as z_order,
               bicycle,
               foot,
               horse,
               mtb_scale,
               sac_scale,
               access,
               toll,
               layer,
               cycleway,
               cycleway_both,
               cycleway_left,
               cycleway_right,
               cycleway_street
        FROM clustered_linestrings_to_merge
        GROUP BY cluster_group, cluster, highway, network, construction, is_bridge, is_tunnel, is_ford, expressway,
                 bicycle, foot, horse, mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both,
                 cycleway_left, cycleway_right, cycleway_street
        RETURNING id, source_ids
    )
    -- Store OSM-IDs of Source-LineStrings
    INSERT INTO inserted_relations (id, source_id)
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
        INSERT INTO osm_transportation_merge_linestring_gen_z11_source_ids (id, source_id)
        SELECT m.id, source_id
        FROM osm_transportation_merge_linestring_gen_z11 m, inserted_relations s
        WHERE (
            EXISTS(
                SELECT NULL
                FROM osm_highway_linestring_gen_z11
                WHERE m.id = s.id AND
                      osm_highway_linestring_gen_z11.osm_id = s.source_id AND
                      ST_Intersects(osm_highway_linestring_gen_z11.geometry, m.geometry)
            )
        ) ON CONFLICT (id, source_id) DO NOTHING
        RETURNING id, source_id
    )
    -- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations
    -- table
    UPDATE osm_transportation_merge_linestring_gen_z11 SET source_ids = q.source_ids
    FROM (
        SELECT id, array_agg(source_id) AS source_ids
        FROM intersected_relations
        GROUP BY id
    ) q
    WHERE osm_transportation_merge_linestring_gen_z11.id = q.id;

    -- Cleanup
    DROP TABLE inserted_relations;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.changes_z11;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.updates_z11;

    RAISE LOG 'Refresh transportation z11 done in %', age(clock_timestamp(), t);

    -- Update z10 and z9 tables
    PERFORM insert_transportation_merge_linestring_gen_z10(FALSE);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Indexes for queries originating from transportation.refresh_z11() function
CREATE INDEX IF NOT EXISTS transportation_transportation_changes_z11_is_old_idx ON transportation.changes_z11(is_old);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z11_source_ids_source
    ON osm_transportation_merge_linestring_gen_z11_source_ids (source_id);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z11_source_ids_id_idx
    ON osm_transportation_merge_linestring_gen_z11_source_ids (id);

CREATE TRIGGER trigger_store_transportation_highway_linestring_gen_z11
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_highway_linestring_gen_z11
    FOR EACH ROW
EXECUTE PROCEDURE transportation.store_gen_z11();

CREATE TRIGGER trigger_store_osm_transportation_merge_linestring_gen_z11
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_transportation_merge_linestring_gen_z11
    FOR EACH ROW
EXECUTE PROCEDURE transportation.store_merge_z11();

CREATE TRIGGER trigger_flag_transportation_z11
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_highway_linestring_gen_z11
    FOR EACH STATEMENT
EXECUTE PROCEDURE transportation.flag_z11();

CREATE CONSTRAINT TRIGGER trigger_refresh_z11
    AFTER INSERT
    ON transportation.updates_z11
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE transportation.refresh_z11();


-- Handle updates on
-- osm_transportation_merge_linestring_gen_z9 -> osm_transportation_merge_linestring_gen_z8
-- osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z7
-- osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z6
-- osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z5
-- osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z4

CREATE TABLE IF NOT EXISTS transportation.changes_z9
(
    is_old boolean,
    id bigint,
    PRIMARY KEY (id, is_old)
);

-- Store IDs of changed elements from osm_highway_linestring_gen_z9 table.
CREATE OR REPLACE FUNCTION transportation.store_z9() RETURNS trigger AS
$$
BEGIN
    IF (tg_op = 'INSERT' OR tg_op = 'UPDATE') THEN
        INSERT INTO transportation.changes_z9(is_old, id)
        VALUES (FALSE, new.id)
        ON CONFLICT (id, is_old) DO NOTHING;
    END IF;
    IF (tg_op = 'DELETE' OR tg_op = 'UPDATE') THEN
        INSERT INTO transportation.changes_z9(is_old, id)
        VALUES (TRUE, old.id)
        ON CONFLICT (id, is_old) DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Store IDs of changed elements from osm_highway_linestring_gen_z8 table.
CREATE OR REPLACE FUNCTION transportation.store_z8() RETURNS trigger AS
$$
BEGIN
    IF (tg_op = 'INSERT' OR tg_op = 'UPDATE') THEN
        INSERT INTO transportation.changes_z4_z5_z6_z7(is_old, id)
        VALUES (FALSE, new.id)
        ON CONFLICT (id, is_old) DO NOTHING;
    END IF;
    IF tg_op = 'DELETE' THEN
        INSERT INTO transportation.changes_z4_z5_z6_z7(is_old, id)
        VALUES (TRUE, old.id)
        ON CONFLICT (id, is_old) DO NOTHING;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS transportation.updates_z9
(
    id serial PRIMARY KEY,
    t text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION transportation.flag_z9() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation.updates_z9(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation.refresh_z8() RETURNS trigger AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation z8';

    -- Analyze tracking and source tables before performing update
    ANALYZE transportation.changes_z9;
    ANALYZE osm_transportation_merge_linestring_gen_z9;

    -- Fetch updated and deleted Merged-LineString from relation-table filtering for each Merged-LineString which
    -- contains an updated Source-LineString.
    -- Additionally attach a list of Source-LineString-IDs to each Merged-LineString in order to unnest them later.
    CREATE TEMPORARY TABLE affected_merged_linestrings AS
    SELECT m.id, array_agg(source_id) AS source_ids
    FROM osm_transportation_merge_linestring_gen_z8_source_ids m
    WHERE EXISTS(
        SELECT NULL
        FROM transportation.changes_z9 c
        WHERE c.is_old IS TRUE AND c.id = m.source_id
    )
    GROUP BY id;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_merged_linestrings (id);
    ANALYZE affected_merged_linestrings;

    -- Delete all Merged-LineStrings which contained an updated or deleted Source-LineString
    DELETE
    FROM osm_transportation_merge_linestring_gen_z8 m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;
    DELETE
    FROM osm_transportation_merge_linestring_gen_z8_source_ids m
    USING affected_merged_linestrings
    WHERE affected_merged_linestrings.id = m.id;

    -- Analyze the tables affected by the delete-query in order to speed up subsequent queries
    ANALYZE osm_transportation_merge_linestring_gen_z8;
    ANALYZE osm_transportation_merge_linestring_gen_z8_source_ids;

    -- Create a table containing the IDs of all Source-LineStrings affected by this update
    CREATE TEMPORARY TABLE affected_source_linestrings AS
    -- Get Source-LineString-IDs of deleted or updated elements
    SELECT unnest(affected_merged_linestrings.source_ids) AS id
    FROM affected_merged_linestrings
    UNION
    -- Get Source-LineString-IDs of inserted or updated elements
    SELECT id
    FROM transportation.changes_z9
    WHERE transportation.changes_z9.is_old IS FALSE
    ORDER BY id;

    -- Drop temporary tables early to save resources
    DROP TABLE affected_merged_linestrings;

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON affected_source_linestrings (id);
    ANALYZE affected_source_linestrings;

    -- Create a table containing all LineStrings which should be merged
    CREATE TEMPORARY TABLE linestrings_to_merge AS
    -- Add all Source-LineStrings affected by this update
    SELECT id AS source_id, NULL::int AS id, geometry, highway, network, construction, is_bridge,
           is_tunnel, is_ford, expressway, z_order
    FROM osm_transportation_merge_linestring_gen_z9
    WHERE EXISTS(
        SELECT NULL
        FROM affected_source_linestrings
        WHERE affected_source_linestrings.id = osm_transportation_merge_linestring_gen_z9.id
    ) AND (
        (
            network IN ('icn', 'ncn', 'rcn') OR
            highway IN ('motorway', 'trunk', 'primary') OR
            construction IN ('motorway', 'trunk', 'primary')
        ) AND
        ST_IsValid(geometry) AND
        access IS NULL
    );

    -- Drop temporary tables early to save resources
    DROP TABLE affected_source_linestrings;

    -- Create index on geometry column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge USING GIST (geometry);
    ANALYZE linestrings_to_merge;

    -- Add all Merged-LineStrings intersecting with Source-LineStrings affected by this update
    INSERT INTO linestrings_to_merge
    SELECT unnest(source_ids) AS source_id, id, geometry, highway, network, construction,
           is_bridge, is_tunnel, is_ford, expressway, z_order
    FROM osm_transportation_merge_linestring_gen_z8
    WHERE EXISTS(
        SELECT NULL FROM linestrings_to_merge
        WHERE ST_Intersects(
            linestrings_to_merge.geometry, osm_transportation_merge_linestring_gen_z8.geometry
        )
    );

    -- Create index on ID-Column and analyze the created table to speed up subsequent queries
    CREATE INDEX ON linestrings_to_merge (id);
    ANALYZE linestrings_to_merge;

    -- Delete all Merged-LineStrings intersecting with Source-LineStrings affected by this update.
    -- We can use the linestrings_to_merge table since Source-LineStrings affected by this update and present in the
    -- table will have their ID-Column set to NULL by the previous query.
    DELETE
    FROM osm_transportation_merge_linestring_gen_z8 m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;
    DELETE
    FROM osm_transportation_merge_linestring_gen_z8_source_ids m
    USING linestrings_to_merge
    WHERE m.id = linestrings_to_merge.id;

    -- Create table containing all LineStrings to and create clusters of intersecting LineStrings partitioned by their
    -- groups
    CREATE TEMPORARY TABLE clustered_linestrings_to_merge AS
    SELECT *,
           -- Get intersecting clusters by setting minimum distance to 0 and minimum intersecting points to 1
           -- https://postgis.net/docs/ST_ClusterDBSCAN.html
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (
               PARTITION BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
           ) AS cluster,
           -- ST_ClusterDBSCAN returns an increasing integer as the cluster-ids within each partition starting at 0.
           -- This leads to clusters having the same ID across multiple partitions therefore we generate a
           -- Cluster-Group-ID by utilizing the DENSE_RANK function sorted over the partition columns.
           DENSE_RANK() OVER (
               ORDER BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
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
    (LIKE osm_transportation_merge_linestring_gen_z8_source_ids INCLUDING INDEXES);

    WITH inserted_linestrings AS (
        -- Merge LineStrings of each cluster and insert them
        INSERT INTO osm_transportation_merge_linestring_gen_z8(geometry, source_ids, highway, network, construction,
                                                               is_bridge, is_tunnel, is_ford, expressway, z_order)
        SELECT (ST_Dump(ST_Simplify(ST_LineMerge(ST_Union(geometry)), ZRes(10)))).geom AS geometry,
               -- We use St_Union instead of St_Collect to ensure no overlapping points exist within the geometries to
               -- merge. https://postgis.net/docs/ST_Union.html
               -- ST_LineMerge only merges across singular intersections and groups its output into a MultiLineString if
               -- more than two LineStrings form an intersection or no intersection could be found.
               -- https://postgis.net/docs/ST_LineMerge.html
               -- In order to not end up with a mixture of LineStrings and MultiLineStrings we dump eventual
               -- MultiLineStrings via ST_Dump. https://postgis.net/docs/ST_Dump.html
            array_agg(source_id) as source_ids,
            highway,
            network,
            construction,
            is_bridge,
            is_tunnel,
            is_ford,
            expressway,
            min(z_order) as z_order
        FROM clustered_linestrings_to_merge
        GROUP BY cluster_group, cluster, highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
        RETURNING id, source_ids
    )
    -- Store OSM-IDs of Source-LineStrings
    INSERT INTO inserted_relations (id, source_id)
    SELECT id, unnest(source_ids)
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
        INSERT INTO osm_transportation_merge_linestring_gen_z8_source_ids (id, source_id)
        SELECT m.id, source_id
        FROM osm_transportation_merge_linestring_gen_z8 m, inserted_relations s
        WHERE (
            EXISTS(
                SELECT NULL
                FROM osm_transportation_merge_linestring_gen_z9
                WHERE m.id = s.id AND
                      osm_transportation_merge_linestring_gen_z9.id = s.source_id AND
                      ST_Intersects(osm_transportation_merge_linestring_gen_z9.geometry, m.geometry)
            )
        ) ON CONFLICT (id, source_id) DO NOTHING
        RETURNING id, source_id
    )
    -- Update Merged-LineStrings with Source-LineStrings-IDs from Merged-LineString to Source-LineStrings-ID Relations
    -- table
    UPDATE osm_transportation_merge_linestring_gen_z8 SET source_ids = q.source_ids
    FROM (
        SELECT id, array_agg(source_id) AS source_ids
        FROM intersected_relations
        GROUP BY id
    ) q
    WHERE osm_transportation_merge_linestring_gen_z8.id = q.id;

    -- Cleanup
    DROP TABLE inserted_relations;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.changes_z9;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.updates_z9;

    RAISE LOG 'Refresh transportation z8 done in %', age(clock_timestamp(), t);

    -- Update z7, z6, z5 and z4 tables
    PERFORM insert_transportation_merge_linestring_gen_z7(FALSE);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Indexes for queries originating from transportation.refresh_z11() function
CREATE INDEX IF NOT EXISTS transportation_transportation_changes_z9_is_old_idx ON transportation.changes_z9(is_old);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_source_ids_source_id
    ON osm_transportation_merge_linestring_gen_z8_source_ids (source_id);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_source_ids_id_idx
    ON osm_transportation_merge_linestring_gen_z8_source_ids (id);

CREATE TRIGGER trigger_store_transportation_highway_linestring_gen_z9
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_transportation_merge_linestring_gen_z9
    FOR EACH ROW
EXECUTE PROCEDURE transportation.store_z9();

CREATE TRIGGER trigger_store_osm_transportation_merge_linestring_gen_z8
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_transportation_merge_linestring_gen_z8
    FOR EACH ROW
EXECUTE PROCEDURE transportation.store_z8();

CREATE TRIGGER trigger_flag_transportation_z9
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_transportation_merge_linestring_gen_z9
    FOR EACH STATEMENT
EXECUTE PROCEDURE transportation.flag_z9();

CREATE CONSTRAINT TRIGGER trigger_refresh_z8
    AFTER INSERT
    ON transportation.updates_z9
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE transportation.refresh_z8();
