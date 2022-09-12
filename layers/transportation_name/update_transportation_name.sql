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
DROP TRIGGER IF EXISTS trigger_store_transportation_name_network ON transportation_name.updates_shipway;
DROP TRIGGER IF EXISTS trigger_refresh_aerialway ON transportation_name.updates_aerialway;

-- Instead of using relations to find out the road names we
-- stitch together the touching ways with the same name
-- to allow for nice label rendering
-- Because this works well for roads that do not have relations as well

-- etldoc: osm_transportation_name_network ->  osm_transportation_name_linestring
-- etldoc: osm_shipway_linestring ->  osm_transportation_name_linestring
-- etldoc: osm_aerialway_linestring ->  osm_transportation_name_linestring

CREATE INDEX IF NOT EXISTS osm_shipway_linestring_update_partial_idx
    ON osm_shipway_linestring (name) WHERE name <> '';
CREATE INDEX IF NOT EXISTS osm_aerialway_linestring_update_partial_idx
    ON osm_aerialway_linestring (name) WHERE name <> '';

CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring(
    id SERIAL,
    source integer,
    geometry geometry('LineString'),
    parent_osm_ids bigint[],
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

TRUNCATE osm_transportation_name_linestring;

INSERT INTO osm_transportation_name_linestring(source, geometry, parent_osm_ids, tags, ref, highway, subclass, brunnel,
                                               sac_scale, "level", layer, indoor, network, network_name, route_1,
                                               route_2, route_3, route_4, route_5, route_6,z_order, route_rank)
SELECT source,
       geometry,
       parent_osm_ids,
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
         SELECT (ST_Dump(ST_LineMerge(ST_Collect(geometry)))).geom AS geometry,
                array_agg(osm_id) AS parent_osm_ids,
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
                    ST_ClusterDBSCAN(geometry, 0, 1) OVER (
                        PARTITION BY tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor,
                                     network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6
                    ) AS cluster,
                    rank() OVER (
                        ORDER BY tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor, network_type,
                                 network_name, route_1, route_2, route_3, route_4, route_5, route_6
                    ) as cluster_id
             FROM osm_transportation_name_network
             WHERE coalesce(tags->'name', '') <> '' OR
                   coalesce(ref, '') <> '' OR (
                     network_type = ANY('{icn,ncn,rcn,lcn}') AND nullif(network_name, '') IS NOT NULL
             )
         ) q
         GROUP BY cluster_id, cluster, tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor,
                  network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6
         UNION ALL

         SELECT (ST_Dump(ST_LineMerge(ST_Collect(geometry)))).geom AS geometry,
                array_agg(osm_id) AS parent_osm_ids,
                1 AS source,
                transportation_name_tags(NULL::geometry, tags, name, name_en, name_de) AS tags,
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
                    ST_ClusterDBSCAN(geometry, 0, 1) OVER (
                        PARTITION BY transportation_name_tags(
                            NULL::geometry, tags, name, name_en, name_de
                        ), shipway, layer
                    ) AS cluster,
                    rank() OVER (
                        ORDER BY transportation_name_tags(
                            NULL::geometry, tags, name, name_en, name_de
                        ), shipway, layer
                    ) as cluster_id
             FROM osm_shipway_linestring
             WHERE name <> ''
         ) q
         GROUP BY cluster_id, cluster, transportation_name_tags(
             NULL::geometry, tags, name, name_en, name_de
         ), shipway, layer
         UNION ALL

         SELECT (ST_Dump(ST_LineMerge(ST_Collect(geometry)))).geom AS geometry,
                array_agg(osm_id) AS parent_osm_ids,
                2 AS source,
                transportation_name_tags(NULL::geometry, tags, name, name_en, name_de) AS tags,
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
                    ST_ClusterDBSCAN(geometry, 0, 1) OVER (
                        PARTITION BY transportation_name_tags(
                            NULL::geometry, tags, name, name_en, name_de
                        ), aerialway, layer
                    ) AS cluster,
                    rank() OVER (
                        ORDER BY transportation_name_tags(
                            NULL::geometry, tags, name, name_en, name_de
                        ), aerialway, layer
                    ) as cluster_id
             FROM osm_aerialway_linestring
             WHERE name <> ''
         ) q
         GROUP BY cluster_id, cluster, transportation_name_tags(
             NULL::geometry, tags, name, name_en, name_de
         ), aerialway, layer
     ) AS highway_union
;

CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_parent_osm_ids_idx
    ON osm_transportation_name_linestring USING GIN (parent_osm_ids);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_source_idx
    ON osm_transportation_name_linestring (source);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_geometry_idx
    ON osm_transportation_name_linestring USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_highway_partial_idx
    ON osm_transportation_name_linestring (highway, subclass, ST_Length(geometry))
    WHERE (highway IN ('motorway', 'trunk') OR highway = 'construction' AND subclass IN ('motorway', 'trunk'))
          AND ST_Length(geometry) > 8000;

CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring_gen1 (
    id integer,
    geometry geometry('LineString'),
    tags hstore,
    ref text,
    highway varchar,
    subclass text,
    brunnel text,
    network route_network_type,
    route_1 text,
    route_2 text,
    route_3 text,
    route_4 text,
    route_5 text,
    route_6 text,
    z_order integer
);

CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring_gen2
(LIKE osm_transportation_name_linestring_gen1);
CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring_gen3
(LIKE osm_transportation_name_linestring_gen2);
CREATE TABLE IF NOT EXISTS osm_transportation_name_linestring_gen4
(LIKE osm_transportation_name_linestring_gen3);

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

    DELETE FROM osm_transportation_name_linestring_gen1
    USING transportation_name.name_changes_gen
    WHERE full_update IS TRUE OR (
        transportation_name.name_changes_gen.is_old IS TRUE AND
        transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen1.id
    );

    INSERT INTO osm_transportation_name_linestring_gen1 (id, geometry, tags, ref, highway, subclass, brunnel, network,
                                                         route_1, route_2, route_3, route_4, route_5, route_6, z_order)
    SELECT id, ST_Simplify(geometry, 50) AS geometry, tags, ref, highway, subclass, brunnel, network, route_1, route_2,
           route_3, route_4, route_5, route_6, z_order
    FROM osm_transportation_name_linestring
    WHERE (
        full_update IS TRUE OR EXISTS (
            SELECT NULL
            FROM transportation_name.name_changes_gen
            WHERE transportation_name.name_changes_gen.is_old IS FALSE AND
                  transportation_name.name_changes_gen.id = osm_transportation_name_linestring.id
        )
    ) AND (
        (highway IN ('motorway', 'trunk') OR highway = 'construction' AND subclass IN ('motorway', 'trunk')) AND
        ST_Length(geometry) > 8000
    ) ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, tags = excluded.tags, ref = excluded.ref,
                                     highway = excluded.highway, subclass = excluded.subclass,
                                     brunnel = excluded.brunnel, network = excluded.network, route_1 = excluded.route_1,
                                     route_2 = excluded.route_2, route_3 = excluded.route_3, route_4 = excluded.route_4,
                                     route_5 = excluded.route_5, route_6 = excluded.route_6, z_order = excluded.z_order;

    ANALYZE VERBOSE osm_transportation_name_linestring_gen1;

    DELETE FROM osm_transportation_name_linestring_gen2
    USING transportation_name.name_changes_gen
    WHERE full_update IS TRUE OR (
        transportation_name.name_changes_gen.is_old IS TRUE AND
        transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen2.id
    );

    INSERT INTO osm_transportation_name_linestring_gen2 (id, geometry, tags, ref, highway, subclass, brunnel, network,
                                                         route_1, route_2, route_3, route_4, route_5, route_6, z_order)
    SELECT id, ST_Simplify(geometry, 120) AS geometry, tags, ref, highway, subclass, brunnel, network, route_1, route_2,
           route_3, route_4, route_5, route_6, z_order
    FROM osm_transportation_name_linestring_gen1
    WHERE (
        full_update IS TRUE OR EXISTS (
            SELECT NULL
            FROM transportation_name.name_changes_gen
            WHERE transportation_name.name_changes_gen.is_old IS FALSE AND
                  transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen1.id
        )
    ) AND (
        (highway IN ('motorway', 'trunk') OR highway = 'construction' AND subclass IN ('motorway', 'trunk')) AND
        ST_Length(geometry) > 14000
    ) ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, tags = excluded.tags, ref = excluded.ref,
                                     highway = excluded.highway, subclass = excluded.subclass,
                                     brunnel = excluded.brunnel, network = excluded.network, route_1 = excluded.route_1,
                                     route_2 = excluded.route_2, route_3 = excluded.route_3, route_4 = excluded.route_4,
                                     route_5 = excluded.route_5, route_6 = excluded.route_6, z_order = excluded.z_order;

    ANALYZE VERBOSE osm_transportation_name_linestring_gen2;

    DELETE FROM osm_transportation_name_linestring_gen3
    USING transportation_name.name_changes_gen
    WHERE full_update IS TRUE OR (
        transportation_name.name_changes_gen.is_old IS TRUE AND
        transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen3.id
    );

    INSERT INTO osm_transportation_name_linestring_gen3 (id, geometry, tags, ref, highway, subclass, brunnel, network,
                                                         route_1, route_2, route_3, route_4, route_5, route_6, z_order)
    SELECT id, ST_Simplify(geometry, 200) AS geometry, tags, ref, highway, subclass, brunnel, network, route_1, route_2,
           route_3, route_4, route_5, route_6, z_order
    FROM osm_transportation_name_linestring_gen2
    WHERE (
        full_update IS TRUE OR EXISTS (
            SELECT NULL
            FROM transportation_name.name_changes_gen
            WHERE transportation_name.name_changes_gen.is_old IS FALSE AND
                  transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen2.id
        )
    ) AND (
        (highway = 'motorway' OR highway = 'construction' AND subclass = 'motorway') AND
        ST_Length(geometry) > 20000
    ) ON CONFLICT (id) DO UPDATE SET geometry = excluded.geometry, tags = excluded.tags, ref = excluded.ref,
                                     highway = excluded.highway, subclass = excluded.subclass,
                                     brunnel = excluded.brunnel, network = excluded.network, route_1 = excluded.route_1,
                                     route_2 = excluded.route_2, route_3 = excluded.route_3, route_4 = excluded.route_4,
                                     route_5 = excluded.route_5, route_6 = excluded.route_6, z_order = excluded.z_order;

    ANALYZE VERBOSE osm_transportation_name_linestring_gen3;

    DELETE FROM osm_transportation_name_linestring_gen4
    USING transportation_name.name_changes_gen
    WHERE full_update IS TRUE OR (
        transportation_name.name_changes_gen.is_old IS TRUE AND
        transportation_name.name_changes_gen.id = osm_transportation_name_linestring_gen4.id
    );

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

    ANALYZE VERBOSE osm_transportation_name_linestring_gen4;

    DELETE FROM transportation_name.name_changes_gen;

    RAISE LOG 'Refresh transportation_name merged done in %', age(clock_timestamp(), t);
END;
$$ LANGUAGE plpgsql;

TRUNCATE osm_transportation_name_linestring_gen1;
TRUNCATE osm_transportation_name_linestring_gen2;
TRUNCATE osm_transportation_name_linestring_gen3;
TRUNCATE osm_transportation_name_linestring_gen4;

SELECT update_transportation_name_linestring_gen(TRUE);

-- etldoc: osm_transportation_name_linestring -> osm_transportation_name_linestring_gen1
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen1_geometry_idx ON osm_transportation_name_linestring_gen1 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen1_update_partial_idx
    ON osm_transportation_name_linestring_gen1 (highway, subclass, ST_Length(geometry))
    WHERE (highway IN ('motorway', 'trunk') OR highway = 'construction' AND subclass IN ('motorway', 'trunk'))
          AND ST_Length(geometry) > 14000;

CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen2_geometry_idx ON osm_transportation_name_linestring_gen2 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen2_update_partial_idx
    ON osm_transportation_name_linestring_gen2 (highway, subclass, ST_Length(geometry))
    WHERE (highway = 'motorway' OR highway = 'construction' AND subclass = 'motorway')
          AND ST_Length(geometry) > 20000;

CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen3_geometry_idx ON osm_transportation_name_linestring_gen3 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen3_update_partial_idx
    ON osm_transportation_name_linestring_gen3 (highway, subclass, ST_Length(geometry))
    WHERE (highway = 'motorway' OR highway = 'construction' AND subclass = 'motorway')
          AND ST_Length(geometry) > 20000;

CREATE INDEX IF NOT EXISTS osm_transportation_name_linestring_gen4_geometry_idx ON osm_transportation_name_linestring_gen4 USING gist (geometry);

-- Handle updates

-- Trigger to update "osm_transportation_name_network" from "osm_route_member" and "osm_highway_linestring"

CREATE TABLE IF NOT EXISTS transportation_name.network_changes
(
    osm_id bigint,
    PRIMARY KEY (osm_id)
);

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
    osm_id bigint,
    PRIMARY KEY (osm_id)
);


CREATE OR REPLACE FUNCTION transportation_name.superroute_member_store() RETURNS trigger AS
$$
BEGIN

    INSERT INTO transportation_name.superroute_changes(osm_id) VALUES (
        (CASE WHEN tg_op IN ('DELETE', 'UPDATE') THEN old.osm_id ELSE new.osm_id END)
    ) ON CONFLICT DO NOTHING;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

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
    PERFORM update_osm_route_member();

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
		LEFT OUTER JOIN osm_route_member rm1 ON rm1.member = hl.osm_id AND rm1.concurrency_index=1
		LEFT OUTER JOIN osm_route_member rm2 ON rm2.member = hl.osm_id AND rm2.concurrency_index=2
		LEFT OUTER JOIN osm_route_member rm3 ON rm3.member = hl.osm_id AND rm3.concurrency_index=3
		LEFT OUTER JOIN osm_route_member rm4 ON rm4.member = hl.osm_id AND rm4.concurrency_index=4
		LEFT OUTER JOIN osm_route_member rm5 ON rm5.member = hl.osm_id AND rm5.concurrency_index=5
		LEFT OUTER JOIN osm_route_member rm6 ON rm6.member = hl.osm_id AND rm6.concurrency_index=6
	WHERE EXISTS(
	        SELECT NULL FROM transportation_name.network_changes AS c WHERE hl.osm_id = c.osm_id
	    ) AND (
	        (hl.name <> '' OR hl.ref <> '' OR rm1.ref <> '' OR rm1.network <> '') AND
	        hl.highway <> ''
        )
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

-- Trigger to update "osm_transportation_name_linestring" from "osm_transportation_name_network"

CREATE TABLE IF NOT EXISTS transportation_name.name_changes
(
    is_old boolean,
    osm_id bigint,
    PRIMARY KEY (osm_id, is_old)
);

CREATE INDEX IF NOT EXISTS transportation_name_name_changes_is_old_idx ON transportation_name.name_changes (is_old);

CREATE TABLE IF NOT EXISTS transportation_name.shipway_changes
(
    is_old boolean,
    osm_id bigint,
    PRIMARY KEY (osm_id, is_old)
);

CREATE INDEX IF NOT EXISTS transportation_name_shipway_changes_is_old_idx
    ON transportation_name.shipway_changes (is_old);

CREATE TABLE IF NOT EXISTS transportation_name.aerialway_changes
(
    is_old boolean,
    osm_id bigint,
    PRIMARY KEY (osm_id, is_old)
);

CREATE INDEX IF NOT EXISTS transportation_name_aerialway_changes_is_old_idx
    ON transportation_name.aerialway_changes (is_old);

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

    -- REFRESH osm_transportation_name_linestring

    ANALYZE VERBOSE transportation_name.name_changes;
    ANALYZE VERBOSE osm_transportation_name_network;

    CREATE TEMPORARY TABLE old_changes AS
    SELECT m.id, m.parent_osm_ids
    FROM osm_transportation_name_linestring m
    WHERE m.source = 0 AND EXISTS(
        SELECT NULL
        FROM transportation_name.name_changes c
        WHERE c.is_old IS TRUE AND m.parent_osm_ids && ARRAY[c.osm_id]::bigint[]
    );

    CREATE INDEX ON old_changes (id);
    ANALYZE VERBOSE old_changes;

    CREATE TEMPORARY TABLE all_changes AS
    SELECT unnest(old_changes.parent_osm_ids) AS osm_id
    FROM old_changes
    UNION
    SELECT osm_id FROM transportation_name.name_changes WHERE is_old IS FALSE
    ORDER BY osm_id;

    CREATE INDEX ON all_changes (osm_id);
    ANALYZE VERBOSE all_changes;

    CREATE TEMPORARY TABLE updated_transportation_name_linestrings AS
    WITH changed_linestrings AS (
        SELECT *
        FROM osm_transportation_name_network
        WHERE EXISTS(
            SELECT NULL
            FROM all_changes
            WHERE all_changes.osm_id = osm_transportation_name_network.osm_id
        ) AND (
            coalesce(tags->'name', '') <> '' OR
            coalesce(ref, '') <> '' OR (
                network_type = ANY('{icn,ncn,rcn,lcn}') AND NULLIF(network_name, '') IS NOT NULL
            )
        )
    )
    SELECT q.*,
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (
               PARTITION BY tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor,
                            network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6
           ) AS cluster,
           rank() OVER (
               ORDER BY tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor,
                        network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6
           ) as cluster_id
    FROM (
        SELECT osm_id, NULL::INTEGER AS id, geometry, tags, ref, highway, subclass, brunnel, sac_scale, level, layer,
               indoor, network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6,
               z_order, route_rank
        FROM changed_linestrings
        UNION ALL
        SELECT unnest(parent_osm_ids) AS osm_id, id, geometry, tags, ref, highway, subclass, brunnel, sac_scale, level, layer,
               indoor, network AS network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6,
               z_order, route_rank
        FROM osm_transportation_name_linestring
        WHERE EXISTS(
            SELECT NULL FROM changed_linestrings
            WHERE osm_transportation_name_linestring.source = 0 AND ST_Intersects(
                changed_linestrings.geometry, osm_transportation_name_linestring.geometry
            )
        )
    ) q;

    CREATE INDEX ON updated_transportation_name_linestrings (id);
    CREATE INDEX ON updated_transportation_name_linestrings (cluster_id, cluster);
    ANALYZE VERBOSE updated_transportation_name_linestrings;

    DELETE
    FROM osm_transportation_name_linestring m
    USING old_changes
    WHERE old_changes.id = m.id;

    DELETE
    FROM osm_transportation_name_linestring m
    USING updated_transportation_name_linestrings
    WHERE m.id = updated_transportation_name_linestrings.id;

    INSERT INTO osm_transportation_name_linestring(source, geometry, parent_osm_ids, tags, ref, highway, subclass, brunnel,
                                               sac_scale, "level", layer, indoor, network, network_name, route_1,
                                               route_2, route_3, route_4, route_5, route_6,z_order, route_rank)
    SELECT 0 AS source, (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
           array_agg(osm_id) AS parent_osm_ids, tags, ref, highway, subclass, brunnel, sac_scale, level, layer, indoor,
           network_type, network_name, route_1, route_2, route_3, route_4, route_5, route_6, min(z_order) AS z_order,
           min(route_rank) AS route_rank
    FROM updated_transportation_name_linestrings q
    GROUP BY cluster_id, cluster, tags, ref, highway, subclass, brunnel, level, layer, sac_scale, indoor, network_type,
             network_name, route_1, route_2, route_3, route_4, route_5, route_6;

    DROP TABLE all_changes;
    DROP TABLE old_changes;
    DROP TABLE updated_transportation_name_linestrings;

    DELETE FROM transportation_name.name_changes;
    DELETE FROM transportation_name.updates_name;

    ANALYZE VERBOSE osm_transportation_name_linestring;

    RAISE LOG 'Refresh transportation_name done in %', age(clock_timestamp(), t);

    PERFORM update_transportation_name_linestring_gen(FALSE);

    RETURN NULL;
END;
$BODY$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation_name.refresh_shipway_linestring() RETURNS trigger AS
$BODY$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation_name shiwpway';

    -- REFRESH osm_transportation_name_linestring

    ANALYZE VERBOSE transportation_name.name_changes;
    ANALYZE VERBOSE osm_shipway_linestring;

    CREATE TEMPORARY TABLE old_changes AS
    SELECT m.id, m.parent_osm_ids
    FROM osm_transportation_name_linestring m
    WHERE m.source = 1 AND EXISTS(
        SELECT NULL
        FROM transportation_name.shipway_changes c
        WHERE c.is_old IS TRUE AND m.parent_osm_ids && ARRAY[c.osm_id]::bigint[]
    );

    CREATE INDEX ON old_changes (id);
    ANALYZE VERBOSE old_changes;

    CREATE TEMPORARY TABLE all_changes AS
    SELECT unnest(old_changes.parent_osm_ids) AS osm_id
    FROM old_changes
    UNION
    SELECT osm_id FROM transportation_name.shipway_changes WHERE is_old IS FALSE
    ORDER BY osm_id;

    CREATE INDEX ON all_changes (osm_id);
    ANALYZE VERBOSE all_changes;

    CREATE TEMPORARY TABLE updated_shipway_linestrings AS
    WITH changed_linestrings AS (
        SELECT *
        FROM osm_shipway_linestring
        WHERE EXISTS(
            SELECT NULL
            FROM all_changes
            WHERE all_changes.osm_id = osm_shipway_linestring.osm_id
        ) AND (
            name <> ''
        )
    )
    SELECT q.*,
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (
               PARTITION BY tags, subclass, layer
           ) AS cluster,
               rank() OVER (
               ORDER BY tags, subclass, layer
           ) as cluster_id
    FROM (
        SELECT osm_id, NULL::INTEGER AS id, geometry,
               transportation_name_tags(
                   NULL::geometry, tags, name, name_en, name_de
               ) AS tags, shipway AS subclass, layer, z_order
        FROM changed_linestrings
        UNION ALL
        SELECT unnest(parent_osm_ids) AS osm_id, id, geometry, tags, subclass, layer, z_order
        FROM osm_transportation_name_linestring
        WHERE EXISTS(
            SELECT NULL FROM changed_linestrings
            WHERE osm_transportation_name_linestring.source = 1 AND ST_Intersects(
                changed_linestrings.geometry, osm_transportation_name_linestring.geometry
            )
        )
    ) q;

    CREATE INDEX ON updated_shipway_linestrings (id);
    CREATE INDEX ON updated_shipway_linestrings (cluster_id, cluster);
    ANALYZE VERBOSE updated_shipway_linestrings;

    DELETE
    FROM osm_transportation_name_linestring m
    USING old_changes
    WHERE old_changes.id = m.id;

    DELETE
    FROM osm_transportation_name_linestring m
    USING updated_shipway_linestrings
    WHERE m.id = updated_shipway_linestrings.id;

    INSERT INTO osm_transportation_name_linestring(source, geometry, parent_osm_ids, tags, highway, subclass, z_order)
    SELECT 1 AS source, (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
           array_agg(osm_id) AS parent_osm_ids, tags, 'shipway' AS highway, subclass, min(z_order) AS z_order
    FROM updated_shipway_linestrings q
    GROUP BY cluster_id, cluster, tags, subclass, layer;

    DROP TABLE all_changes;
    DROP TABLE old_changes;
    DROP TABLE updated_shipway_linestrings;

    DELETE FROM transportation_name.shipway_changes;
    DELETE FROM transportation_name.updates_shipway;

    ANALYZE VERBOSE osm_transportation_name_linestring;

    RAISE LOG 'Refresh transportation_name shipway done in %', age(clock_timestamp(), t);

    PERFORM update_transportation_name_linestring_gen(FALSE);

    RETURN NULL;
END;
$BODY$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation_name.refresh_aerialway_linestring() RETURNS trigger AS
$BODY$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation_name aerialway';

    -- REFRESH osm_transportation_name_linestring

    ANALYZE VERBOSE transportation_name.name_changes;
    ANALYZE VERBOSE osm_aerialway_linestring;

    CREATE TEMPORARY TABLE old_changes AS
    SELECT m.id, m.parent_osm_ids
    FROM osm_transportation_name_linestring m
    WHERE m.source = 2 AND EXISTS(
        SELECT NULL
        FROM transportation_name.aerialway_changes c
        WHERE c.is_old IS TRUE AND m.parent_osm_ids && ARRAY[c.osm_id]::bigint[]
    );

    CREATE INDEX ON old_changes (id);
    ANALYZE VERBOSE old_changes;

    CREATE TEMPORARY TABLE all_changes AS
    SELECT unnest(old_changes.parent_osm_ids) AS osm_id
    FROM old_changes
    UNION
    SELECT osm_id FROM transportation_name.aerialway_changes WHERE is_old IS FALSE
    ORDER BY osm_id;

    CREATE INDEX ON all_changes (osm_id);
    ANALYZE VERBOSE all_changes;

    CREATE TEMPORARY TABLE updated_aerialway_linestrings AS
    WITH changed_linestrings AS (
        SELECT *
        FROM osm_aerialway_linestring
        WHERE EXISTS(
            SELECT NULL
            FROM all_changes
            WHERE all_changes.osm_id = osm_aerialway_linestring.osm_id
        ) AND (
            name <> ''
        )
    )
    SELECT q.*,
           ST_ClusterDBSCAN(geometry, 0, 1) OVER (
               PARTITION BY tags, subclass, layer
           ) AS cluster,
               rank() OVER (
               ORDER BY tags, subclass, layer
           ) as cluster_id
    FROM (
        SELECT osm_id, NULL::INTEGER AS id, geometry,
               transportation_name_tags(
                   NULL::geometry, tags, name, name_en, name_de
               ) AS tags, aerialway AS subclass, layer, z_order
        FROM changed_linestrings
        UNION ALL
        SELECT unnest(parent_osm_ids) AS osm_id, id, geometry, tags, subclass, layer, z_order
        FROM osm_transportation_name_linestring
        WHERE EXISTS(
            SELECT NULL FROM changed_linestrings
            WHERE osm_transportation_name_linestring.source = 2 AND ST_Intersects(
                changed_linestrings.geometry, osm_transportation_name_linestring.geometry
            )
        )
    ) q;

    CREATE INDEX ON updated_aerialway_linestrings (id);
    CREATE INDEX ON updated_aerialway_linestrings (cluster_id, cluster);
    ANALYZE VERBOSE updated_aerialway_linestrings;

    DELETE
    FROM osm_transportation_name_linestring m
    USING old_changes
    WHERE old_changes.id = m.id;

    DELETE
    FROM osm_transportation_name_linestring m
    USING updated_aerialway_linestrings
    WHERE m.id = updated_aerialway_linestrings.id;

    INSERT INTO osm_transportation_name_linestring(source, geometry, parent_osm_ids, tags, highway, subclass, z_order)
    SELECT 2 AS source, (ST_Dump(ST_LineMerge(ST_Union(geometry)))).geom AS geometry,
           array_agg(osm_id) AS parent_osm_ids, tags, 'aerialway' AS highway, subclass, min(z_order) AS z_order
    FROM updated_aerialway_linestrings q
    GROUP BY cluster_id, cluster, tags, subclass, layer;

    DROP TABLE all_changes;
    DROP TABLE old_changes;
    DROP TABLE updated_aerialway_linestrings;

    DELETE FROM transportation_name.aerialway_changes;
    DELETE FROM transportation_name.updates_aerialway;

    ANALYZE VERBOSE osm_transportation_name_linestring;

    RAISE LOG 'Refresh transportation_name aerialway done in %', age(clock_timestamp(), t);

    PERFORM update_transportation_name_linestring_gen(FALSE);

    RETURN NULL;
END;
$BODY$ LANGUAGE plpgsql;

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

CREATE CONSTRAINT TRIGGER trigger_store_transportation_name_network
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

