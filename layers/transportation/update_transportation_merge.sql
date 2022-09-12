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


-- Improve performance of the sql in transportation/update_transportation_name.sql
CREATE INDEX IF NOT EXISTS osm_highway_linestring_transportation_name_partial_idx
    ON osm_highway_linestring (name, ref, highway)
    WHERE (osm_highway_linestring.name <> '' OR osm_highway_linestring.ref <> '') AND
          osm_highway_linestring.highway <> '';

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

CREATE INDEX IF NOT EXISTS osm_transportation_name_update_partial_idx
    ON osm_transportation_name_network (coalesce(tags->'name', ''), coalesce(ref, ''), network_type,
                                        nullif(network_name, ''))
    WHERE coalesce(tags->'name', '') <> '' OR
          coalesce(ref, '') <> '' OR (
              network_type = ANY('{icn,ncn,rcn,lcn}') AND
              nullif(network_name, '') IS NOT NULL
          );
CREATE INDEX IF NOT EXISTS osm_transportation_name_network_geometry_idx
    ON osm_transportation_name_network USING gist (geometry);


CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z11_update_partial_idx
ON osm_highway_linestring_gen_z11 (network, highway, construction)
WHERE network in ('icn', 'ncn', 'rcn', 'lcn') OR
    (
        highway IN (
            'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link', 'primary_link',
            'secondary_link', 'tertiary_link', 'busway'
        ) OR (
            highway = 'construction' AND
            construction IN (
                'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link', 'primary_link',
                'secondary_link', 'tertiary_link', 'busway'
            )
        )
    );

-- etldoc: osm_highway_linestring_gen_z11 ->  osm_transportation_merge_linestring_gen_z11
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z11(
    geometry geometry('LineString'),
    id SERIAL,
    osm_id bigint,
    parent_osm_ids bigint[],
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

CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z10
    (LIKE osm_transportation_merge_linestring_gen_z11);
ALTER TABLE osm_transportation_merge_linestring_gen_z10 DROP COLUMN IF EXISTS parent_osm_ids;

CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z9
    (LIKE osm_transportation_merge_linestring_gen_z10);

TRUNCATE osm_transportation_merge_linestring_gen_z11;

INSERT INTO osm_transportation_merge_linestring_gen_z11(geometry, parent_osm_ids, highway, network, construction,
                                                        is_bridge, is_tunnel, is_ford, expressway, z_order, bicycle,
                                                        foot, horse, mtb_scale, sac_scale, access, toll, layer,
                                                        cycleway, cycleway_both, cycleway_left, cycleway_right,
                                                        cycleway_street)
SELECT (ST_Dump(ST_LineMerge(ST_Collect(geometry)))).geom AS geometry,
       array_agg(osm_id) as parent_osm_ids,
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
FROM   (
    SELECT *,
        ST_ClusterDBSCAN(geometry, 0, 1) OVER (
        PARTITION BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle, foot, horse,
            mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left, cycleway_right,
            cycleway_street
        ) AS cluster,
        rank() OVER (
         ORDER BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle, foot, horse,
             mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left, cycleway_right,
             cycleway_street
        ) as cluster_id
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
GROUP BY cluster_id, cluster, highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle, foot,
         horse, mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left, cycleway_right,
         cycleway_street;

CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z11_parent_osm_ids_idx
    ON osm_transportation_merge_linestring_gen_z11 USING GIN (parent_osm_ids);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z11_geometry_idx
    ON osm_transportation_merge_linestring_gen_z11 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z11_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z11 (network, highway, construction)
    WHERE network in ('icn', 'ncn', 'rcn') OR (
        highway NOT IN ('tertiary', 'tertiary_link', 'busway')
        AND construction NOT IN ('tertiary', 'tertiary_link', 'busway')
    );

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

    ANALYZE VERBOSE transportation.changes_z9_z10;

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

    ANALYZE VERBOSE osm_transportation_merge_linestring_gen_z10;

    DELETE FROM osm_transportation_merge_linestring_gen_z9
    USING transportation.changes_z9_z10
    WHERE full_update IS TRUE OR (
        transportation.changes_z9_z10.is_old IS TRUE AND
        transportation.changes_z9_z10.id = osm_transportation_merge_linestring_gen_z9.id
    );

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

    ANALYZE VERBOSE osm_transportation_merge_linestring_gen_z9;

    DELETE FROM transportation.changes_z9_z10;

    RAISE LOG 'Refresh transportation z9 10 done in %', age(clock_timestamp(), t);
END;
$$ LANGUAGE plpgsql;

TRUNCATE osm_transportation_merge_linestring_gen_z10;
TRUNCATE osm_transportation_merge_linestring_gen_z9;

SELECT insert_transportation_merge_linestring_gen_z10(TRUE);

CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z10_geometry_idx
    ON osm_transportation_merge_linestring_gen_z10 USING gist (geometry);

CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z9_geometry_idx
    ON osm_transportation_merge_linestring_gen_z9 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z9_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z9 (network, highway, construction, ST_IsValid(geometry), access)
    WHERE (
        network IN ('icn', 'ncn', 'rcn') OR
        highway IN ('motorway', 'trunk', 'primary') OR
        construction IN ('motorway', 'trunk', 'primary')
    ) AND ST_IsValid(geometry) AND access IS NULL;

-- etldoc: osm_transportation_merge_linestring_gen_z9 -> osm_transportation_merge_linestring_gen_z8
CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z8(
    geometry geometry('LineString'),
    id SERIAL,
    osm_id bigint,
    parent_ids int[],
    highway character varying,
    network character varying,
    construction character varying,
    is_bridge boolean,
    is_tunnel boolean,
    is_ford boolean,
    expressway boolean,
    z_order integer
);

CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z7
    (LIKE osm_transportation_merge_linestring_gen_z8);
ALTER TABLE osm_transportation_merge_linestring_gen_z7 DROP COLUMN IF EXISTS parent_ids;

CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z6
    (LIKE osm_transportation_merge_linestring_gen_z7);

CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z5
    (LIKE osm_transportation_merge_linestring_gen_z6);

CREATE TABLE IF NOT EXISTS osm_transportation_merge_linestring_gen_z4
    (LIKE osm_transportation_merge_linestring_gen_z5);

TRUNCATE osm_transportation_merge_linestring_gen_z8;

INSERT INTO osm_transportation_merge_linestring_gen_z8(geometry, parent_ids, highway, network, construction, is_bridge,
                                                       is_tunnel, is_ford, expressway, z_order)
SELECT (ST_Dump(ST_Simplify(ST_LineMerge(ST_Collect(geometry)), ZRes(10)))).geom AS geometry,
       array_agg(id) AS parent_ids,
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
        ST_ClusterDBSCAN(geometry, 0, 1) OVER (
            PARTITION BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
        ) AS cluster,
        rank() OVER (
            ORDER BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
        ) as cluster_id
    FROM osm_transportation_merge_linestring_gen_z9
    WHERE (
        network IN ('icn', 'ncn', 'rcn') OR
        highway IN ('motorway', 'trunk', 'primary') OR
        construction IN ('motorway', 'trunk', 'primary')
    ) AND ST_IsValid(geometry) AND access IS NULL
) q
GROUP BY cluster_id, cluster, highway, network, construction, is_bridge, is_tunnel, is_ford, expressway;

CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_ids_idx
    ON osm_transportation_merge_linestring_gen_z8 USING GIN (parent_ids);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_geometry_idx
    ON osm_transportation_merge_linestring_gen_z8 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z8 (network, ST_Length(geometry))
    WHERE (network IN ('icn', 'ncn') OR ST_Length(geometry) > 50);

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

    ANALYZE VERBOSE transportation.changes_z4_z5_z6_z7;

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

    ANALYZE VERBOSE osm_transportation_merge_linestring_gen_z7;

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

    ANALYZE VERBOSE osm_transportation_merge_linestring_gen_z6;

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

    ANALYZE VERBOSE osm_transportation_merge_linestring_gen_z5;

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

    ANALYZE VERBOSE osm_transportation_merge_linestring_gen_z4;

    DELETE FROM transportation.changes_z4_z5_z6_z7;

    RAISE LOG 'Refresh transportation z4 z5 z6 z7 done in %', age(clock_timestamp(), t);
END;
$$ LANGUAGE plpgsql;

TRUNCATE osm_transportation_merge_linestring_gen_z7;
TRUNCATE osm_transportation_merge_linestring_gen_z6;
TRUNCATE osm_transportation_merge_linestring_gen_z5;
TRUNCATE osm_transportation_merge_linestring_gen_z4;

SELECT insert_transportation_merge_linestring_gen_z7(TRUE);

CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z7_geometry_idx
    ON osm_transportation_merge_linestring_gen_z7 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z7_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z7 (highway, construction, ST_Length(geometry))
    WHERE (highway IN ('motorway', 'trunk') OR construction IN ('motorway', 'trunk')) AND
          ST_Length(geometry) > 100;

CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z6_geometry_idx
    ON osm_transportation_merge_linestring_gen_z6 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z6_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z6 (ST_Length(geometry))
    WHERE ST_Length(geometry) > 500;

CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z5_geometry_idx
    ON osm_transportation_merge_linestring_gen_z5 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z5_update_partial_idx
    ON osm_transportation_merge_linestring_gen_z5 (highway, construction, ST_Length(geometry))
    WHERE (highway = 'motorway' OR construction = 'motorway') AND
          ST_Length(geometry) > 1000;

CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z4_geometry_idx
    ON osm_transportation_merge_linestring_gen_z4 USING gist (geometry);


-- Handle updates on
-- osm_highway_linestring_gen_z11 -> osm_transportation_merge_linestring_gen_z11

CREATE TABLE IF NOT EXISTS transportation.changes_z11
(
    is_old boolean NULL,
    osm_id bigint,
    PRIMARY KEY (osm_id, is_old)
);

CREATE INDEX IF NOT EXISTS transportation_transportation_changes_z11_is_old_idx ON transportation.changes_z11(is_old);

CREATE OR REPLACE FUNCTION transportation.store_z11() RETURNS trigger AS
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

-- Handle updates on
-- osm_transportation_merge_linestring_gen_z11 -> osm_transportation_merge_linestring_gen_z10
-- osm_transportation_merge_linestring_gen_z11 -> osm_transportation_merge_linestring_gen_z9
CREATE OR REPLACE FUNCTION transportation.store_z10() RETURNS trigger AS
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

    ANALYZE VERBOSE transportation.changes_z11;
    ANALYZE VERBOSE osm_highway_linestring_gen_z11;

    CREATE TEMPORARY TABLE old_changes AS
    SELECT m.id, m.parent_osm_ids
    FROM osm_transportation_merge_linestring_gen_z11 m
    WHERE EXISTS(
        SELECT NULL
        FROM transportation.changes_z11 c
        WHERE c.is_old IS TRUE AND m.parent_osm_ids && ARRAY[c.osm_id]::bigint[]
    );

    CREATE INDEX ON old_changes (id);
    ANALYZE VERBOSE old_changes;

    CREATE TEMPORARY TABLE all_changes AS
    SELECT unnest(old_changes.parent_osm_ids) AS osm_id
    FROM old_changes
    UNION
    SELECT osm_id FROM transportation.changes_z11 WHERE is_old IS FALSE
    ORDER BY osm_id;

    CREATE INDEX ON all_changes (osm_id);
    ANALYZE VERBOSE all_changes;

    CREATE TEMPORARY TABLE updated_linestrings_gen_z11 AS
    WITH changed_linestrings AS (
        SELECT *
        FROM osm_highway_linestring_gen_z11
        WHERE EXISTS(SELECT NULL FROM all_changes WHERE all_changes.osm_id = osm_highway_linestring_gen_z11.osm_id) AND
              (
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
              )
    )
    SELECT q.*,
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (
               PARTITION BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle, foot,
               horse, mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left, cycleway_right,
               cycleway_street
           ) AS cluster,
           rank() OVER (
               ORDER BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle, foot, horse,
               mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left, cycleway_right,
               cycleway_street
           ) as cluster_id
    FROM (
        SELECT osm_id, NULL::INTEGER AS id, geometry, highway, network, construction, is_bridge, is_tunnel, is_ford,
               expressway, bicycle, foot, horse, mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both,
               cycleway_left, cycleway_right, cycleway_street, z_order
        FROM changed_linestrings
        UNION ALL
        SELECT unnest(parent_osm_ids) AS osm_id, id, geometry, highway, network, construction, is_bridge, is_tunnel,
               is_ford, expressway, bicycle, foot, horse, mtb_scale, sac_scale, access, toll, layer, cycleway,
               cycleway_both, cycleway_left, cycleway_right, cycleway_street, z_order
        FROM osm_transportation_merge_linestring_gen_z11
        WHERE EXISTS(
            SELECT NULL FROM changed_linestrings
            WHERE ST_Intersects(
                changed_linestrings.geometry, osm_transportation_merge_linestring_gen_z11.geometry
            )
        )
    ) q;

    CREATE INDEX ON updated_linestrings_gen_z11 (id);
    CREATE INDEX ON updated_linestrings_gen_z11 (cluster_id, cluster);
    ANALYZE VERBOSE updated_linestrings_gen_z11;

    DELETE
    FROM osm_transportation_merge_linestring_gen_z11 m
    USING old_changes
    WHERE old_changes.id = m.id;

    DELETE
    FROM osm_transportation_merge_linestring_gen_z11 m
    USING updated_linestrings_gen_z11
    WHERE m.id = updated_linestrings_gen_z11.id;

    INSERT INTO osm_transportation_merge_linestring_gen_z11(geometry, parent_osm_ids, highway, network, construction,
                                                            is_bridge, is_tunnel, is_ford, expressway, z_order, bicycle,
                                                            foot, horse, mtb_scale, sac_scale, access, toll, layer,
                                                            cycleway, cycleway_both, cycleway_left, cycleway_right,
                                                            cycleway_street)
    SELECT (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
        array_agg(osm_id) AS parent_osm_ids,
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
    FROM updated_linestrings_gen_z11
    GROUP BY cluster_id, cluster, highway, network, construction, is_bridge, is_tunnel, is_ford, expressway, bicycle,
             foot, horse, mtb_scale, sac_scale, access, toll, layer, cycleway, cycleway_both, cycleway_left,
             cycleway_right, cycleway_street;

    DROP TABLE old_changes;
    DROP TABLE all_changes;
    DROP TABLE updated_linestrings_gen_z11;

    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.changes_z11;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.updates_z11;

    ANALYZE VERBOSE osm_transportation_merge_linestring_gen_z11;

    RAISE LOG 'Refresh transportation z11 done in %', age(clock_timestamp(), t);

    PERFORM insert_transportation_merge_linestring_gen_z10(FALSE);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trigger_store_transportation_highway_linestring_gen_z11
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_highway_linestring_gen_z11
    FOR EACH ROW
EXECUTE PROCEDURE transportation.store_z11();

CREATE TRIGGER trigger_store_osm_transportation_merge_linestring_gen_z11
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_transportation_merge_linestring_gen_z11
    FOR EACH ROW
EXECUTE PROCEDURE transportation.store_z10();

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

CREATE TABLE IF NOT EXISTS transportation.changes_z9
(
    is_old boolean,
    id bigint,
    PRIMARY KEY (id, is_old)
);

CREATE INDEX IF NOT EXISTS transportation_transportation_changes_z9_is_old_idx ON transportation.changes_z9(is_old);

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

-- Handle updates on
-- osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z7
-- osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z6
-- osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z5
-- osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z4

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

    ANALYZE VERBOSE transportation.changes_z9;

    CREATE TEMPORARY TABLE old_changes AS
    SELECT m.id, m.parent_ids
    FROM osm_transportation_merge_linestring_gen_z8 m
    WHERE EXISTS(
        SELECT NULL
        FROM transportation.changes_z9 c
        WHERE c.is_old IS TRUE AND m.parent_ids && ARRAY[c.id]::int[]
    );

    CREATE INDEX ON old_changes (id);
    ANALYZE VERBOSE old_changes;

    CREATE TEMPORARY TABLE all_changes AS
    SELECT unnest(old_changes.parent_ids) AS id
    FROM old_changes
    UNION
    SELECT id
    FROM transportation.changes_z9
    WHERE transportation.changes_z9.is_old IS FALSE
    ORDER BY id;

    CREATE INDEX ON all_changes (id);
    ANALYZE VERBOSE all_changes;

    CREATE TEMPORARY TABLE updated_linestrings_gen_z8 AS
    WITH changed_linestrings AS (
        SELECT *
        FROM osm_transportation_merge_linestring_gen_z9
        WHERE EXISTS(
            SELECT NULL
            FROM all_changes
            WHERE all_changes.id = osm_transportation_merge_linestring_gen_z9.id
        ) AND (
            (
                network IN ('icn', 'ncn', 'rcn') OR
                highway IN ('motorway', 'trunk', 'primary') OR
                construction IN ('motorway', 'trunk', 'primary')
            ) AND
            ST_IsValid(geometry) AND
            access IS NULL
        )
    )
    SELECT q.*,
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (
               PARTITION BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
           ) AS cluster,
           rank() OVER (
               ORDER BY highway, network, construction, is_bridge, is_tunnel, is_ford, expressway
           ) as cluster_id
    FROM (
        SELECT FALSE AS intersected, id, geometry, highway, network, construction, is_bridge, is_tunnel, is_ford,
               expressway, z_order
        FROM changed_linestrings
        UNION ALL
        SELECT TRUE AS intersected, id, geometry, highway, network, construction, is_bridge, is_tunnel, is_ford,
               expressway, z_order
        FROM osm_transportation_merge_linestring_gen_z8
        WHERE EXISTS(
            SELECT NULL FROM changed_linestrings
            WHERE ST_Intersects(
                changed_linestrings.geometry, osm_transportation_merge_linestring_gen_z8.geometry
            )
        )
    ) q;

    CREATE INDEX ON updated_linestrings_gen_z8 (intersected, id);
    CREATE INDEX ON updated_linestrings_gen_z8 (cluster_id, cluster);
    ANALYZE VERBOSE updated_linestrings_gen_z8;

    DELETE
    FROM osm_transportation_merge_linestring_gen_z8 m
    USING old_changes
    WHERE old_changes.id = m.id;

    DELETE
    FROM osm_transportation_merge_linestring_gen_z8 m
    USING updated_linestrings_gen_z8
    WHERE updated_linestrings_gen_z8.intersected IS TRUE AND m.id = updated_linestrings_gen_z8.id;

    INSERT INTO osm_transportation_merge_linestring_gen_z8(geometry, parent_ids, highway, network, construction,
                                                           is_bridge, is_tunnel, is_ford, expressway, z_order)
    SELECT (ST_Dump(ST_Simplify(ST_LineMerge(ST_Union(geometry)), ZRes(10)))).geom AS geometry,
        array_agg(id) as parent_ids,
        highway,
        network,
        construction,
        is_bridge,
        is_tunnel,
        is_ford,
        expressway,
        min(z_order) as z_order
    FROM updated_linestrings_gen_z8
    GROUP BY cluster_id, cluster, highway, network, construction, is_bridge, is_tunnel, is_ford, expressway;

    DROP TABLE old_changes;
    DROP TABLE all_changes;
    DROP TABLE updated_linestrings_gen_z8;

    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.changes_z9;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.updates_z9;

    ANALYZE VERBOSE osm_transportation_merge_linestring_gen_z8;

    RAISE LOG 'Refresh transportation z8 done in %', age(clock_timestamp(), t);

    PERFORM insert_transportation_merge_linestring_gen_z7(FALSE);

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

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
