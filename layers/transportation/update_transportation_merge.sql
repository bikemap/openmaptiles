DROP TRIGGER IF EXISTS trigger_flag_transportation ON osm_highway_linestring;
DROP TRIGGER IF EXISTS trigger_refresh ON transportation.updates;

-- Instead of using relations to find out the road names we
-- stitch together the touching ways with the same name
-- to allow for nice label rendering
-- Because this works well for roads that do not have relations as well


CREATE INDEX IF NOT EXISTS osm_route_member_network_partial_idx
  ON osm_route_member(network)
  WHERE network IN ('icn', 'ncn', 'rcn', 'lcn');

DROP MATERIALIZED VIEW IF EXISTS osm_highway_linestring_view CASCADE;
CREATE MATERIALIZED VIEW osm_highway_linestring_view AS (
    SELECT hl.*, rm.network AS cycle_network
    FROM osm_highway_linestring hl
    LEFT JOIN osm_route_member rm ON (
        rm.member = hl.osm_id AND
        rm.network IN ('icn', 'ncn', 'rcn', 'lcn')
    )
);

CREATE INDEX IF NOT EXISTS osm_highway_linestring_view_geometry_idx
  ON osm_highway_linestring_view USING gist(geometry);
CREATE INDEX IF NOT EXISTS osm_highway_linestring_view_highway_partial_idx
  ON osm_highway_linestring_view(highway, construction);
CREATE INDEX IF NOT EXISTS osm_highway_linestring_view_network_partial_idx
  ON osm_highway_linestring_view(cycle_network)
  WHERE cycle_network IN ('icn', 'ncn', 'rcn', 'lcn');

DROP MATERIALIZED VIEW IF EXISTS osm_highway_linestring_gen_z11_view CASCADE;
CREATE MATERIALIZED VIEW osm_highway_linestring_gen_z11_view AS (
    SELECT hl.*, rm.network AS cycle_network
    FROM osm_highway_linestring_gen_z11 hl
    LEFT JOIN osm_route_member rm ON (
        rm.member = hl.osm_id AND
        rm.network IN ('icn', 'ncn', 'rcn', 'lcn')
    )
    WHERE (
        rm.network IS NOT NULL OR
        highway IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link') OR
        highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link')
    ) AND NOT is_area
);

CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z11_view_geometry_idx
  ON osm_highway_linestring_gen_z11_view USING gist(geometry);
CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z11_view_highway_partial_idx
  ON osm_highway_linestring_gen_z11_view(highway, construction)
  WHERE highway IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link') OR
        highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link');
CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z11_view_network_partial_idx
  ON osm_highway_linestring_gen_z11_view(cycle_network)
  WHERE cycle_network IN ('icn', 'ncn', 'rcn', 'lcn');

DROP MATERIALIZED VIEW IF EXISTS osm_highway_linestring_gen_z10_view CASCADE;
CREATE MATERIALIZED VIEW osm_highway_linestring_gen_z10_view AS (
    SELECT hl.*, rm.network AS cycle_network
    FROM osm_highway_linestring_gen_z10 hl
    LEFT JOIN osm_route_member rm ON (
        rm.member = hl.osm_id AND
        rm.network IN ('icn', 'ncn', 'rcn')
    )
    WHERE (
        rm.network IS NOT NULL OR
        highway IN ('motorway', 'trunk', 'primary', 'secondary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link') OR
        highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary', 'secondary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link')
    ) AND NOT is_area
);

CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z10_view_geometry_idx
  ON osm_highway_linestring_gen_z10_view USING gist(geometry);
CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z10_view_highway_partial_idx
  ON osm_highway_linestring_gen_z10_view(highway, construction, network)
  WHERE highway IN ('motorway', 'trunk', 'primary', 'secondary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link') OR
        highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary', 'secondary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link');
CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z10_view_network_partial_idx
  ON osm_highway_linestring_gen_z10_view(cycle_network)
  WHERE cycle_network IN ('icn', 'ncn', 'rcn');

DROP MATERIALIZED VIEW IF EXISTS osm_highway_linestring_gen_z9_view CASCADE;
CREATE MATERIALIZED VIEW osm_highway_linestring_gen_z9_view AS (
    SELECT hl.*, rm.network AS cycle_network
    FROM osm_highway_linestring_gen_z9 hl
    LEFT JOIN osm_route_member rm ON (
        rm.member = hl.osm_id AND
        rm.network IN ('icn', 'ncn', 'rcn')
    )
    WHERE (
        rm.network IS NOT NULL OR
        highway IN ('motorway', 'trunk', 'primary', 'secondary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link') OR
        highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary', 'secondary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link')
    ) AND NOT is_area
);

CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z9_view_geometry_idx
  ON osm_highway_linestring_gen_z9_view USING gist(geometry);
CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z9_view_highway_partial_idx
  ON osm_highway_linestring_gen_z9_view(highway, construction, network)
  WHERE highway IN ('motorway', 'trunk', 'primary', 'secondary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link') OR
        highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary', 'secondary', 'motorway_link', 'trunk_link', 'primary_link', 'secondary_link');
CREATE INDEX IF NOT EXISTS osm_highway_linestring_gen_z9_view_network_partial_idx
  ON osm_highway_linestring_gen_z9_view(cycle_network)
  WHERE cycle_network IN ('icn', 'ncn', 'rcn');


-- Improve performance of the sql in transportation_name/network_type.sql
CREATE INDEX IF NOT EXISTS osm_highway_linestring_highway_partial_idx
    ON osm_highway_linestring (highway)
    WHERE highway IN ('motorway', 'trunk', 'primary', 'construction');

-- etldoc: osm_highway_linestring ->  osm_transportation_merge_linestring
DROP MATERIALIZED VIEW IF EXISTS osm_transportation_merge_linestring CASCADE;
CREATE MATERIALIZED VIEW osm_transportation_merge_linestring AS
(
SELECT (ST_Dump(geometry)).geom AS geometry,
       NULL::bigint AS osm_id,
       highway,
       construction,
       is_bridge,
       is_tunnel,
       is_ford,
       z_order,
       cycle_network
FROM (
         SELECT ST_LineMerge(ST_Collect(geometry)) AS geometry,
                highway,
                construction,
                is_bridge,
                is_tunnel,
                is_ford,
                min(z_order) AS z_order,
                cycle_network
         FROM osm_highway_linestring_view
         WHERE (
             cycle_network IS NOT NULL OR
             highway IN ('motorway', 'trunk', 'primary') OR
             highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary')
           )
           AND ST_IsValid(geometry)
         GROUP BY highway, construction, is_bridge, is_tunnel, is_ford, cycle_network
     ) AS highway_union
    ) /* DELAY_MATERIALIZED_VIEW_CREATION */;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_geometry_idx
    ON osm_transportation_merge_linestring USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_highway_partial_idx
    ON osm_transportation_merge_linestring (highway, construction)
    WHERE highway IN ('motorway', 'trunk', 'primary', 'construction');
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_network_partial_idx
  ON osm_transportation_merge_linestring(cycle_network)
  WHERE cycle_network IN ('icn', 'ncn', 'rcn');

-- etldoc: osm_transportation_merge_linestring -> osm_transportation_merge_linestring_gen_z8
DROP MATERIALIZED VIEW IF EXISTS osm_transportation_merge_linestring_gen_z8 CASCADE;
CREATE MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z8 AS
(
SELECT ST_Simplify(geometry, ZRes(10)) AS geometry,
       osm_id,
       highway,
       construction,
       is_bridge,
       is_tunnel,
       is_ford,
       z_order,
       cycle_network
FROM osm_transportation_merge_linestring
WHERE cycle_network IN ('icn', 'ncn', 'rcn') OR highway IN ('motorway', 'trunk', 'primary')
   OR highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary')
    ) /* DELAY_MATERIALIZED_VIEW_CREATION */;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_geometry_idx
    ON osm_transportation_merge_linestring_gen_z8 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_highway_partial_idx
    ON osm_transportation_merge_linestring_gen_z8 (highway, construction)
    WHERE highway IN ('motorway', 'trunk', 'primary', 'construction');
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z8_network_partial_idx
  ON osm_transportation_merge_linestring_gen_z8(cycle_network)
  WHERE cycle_network IN ('icn', 'ncn', 'rcn');

-- etldoc: osm_transportation_merge_linestring_gen_z8 -> osm_transportation_merge_linestring_gen_z7
DROP MATERIALIZED VIEW IF EXISTS osm_transportation_merge_linestring_gen_z7 CASCADE;
CREATE MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z7 AS
(
SELECT ST_Simplify(geometry, ZRes(9)) AS geometry,
       osm_id,
       highway,
       construction,
       is_bridge,
       is_tunnel,
       is_ford,
       z_order,
       cycle_network
FROM osm_transportation_merge_linestring_gen_z8
WHERE (cycle_network IN ('icn', 'ncn') OR highway IN ('motorway', 'trunk', 'primary') OR
       highway = 'construction' AND construction IN ('motorway', 'trunk', 'primary'))
  AND ST_Length(geometry) > 50
    ) /* DELAY_MATERIALIZED_VIEW_CREATION */;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z7_geometry_idx
    ON osm_transportation_merge_linestring_gen_z7 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z7_highway_partial_idx
    ON osm_transportation_merge_linestring_gen_z7 (highway, construction)
    WHERE highway IN ('motorway', 'trunk', 'primary', 'construction');
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z7_network_partial_idx
  ON osm_transportation_merge_linestring_gen_z7(cycle_network)
  WHERE cycle_network IN ('icn', 'ncn');

-- etldoc: osm_transportation_merge_linestring_gen_z7 -> osm_transportation_merge_linestring_gen_z6
DROP MATERIALIZED VIEW IF EXISTS osm_transportation_merge_linestring_gen_z6 CASCADE;
CREATE MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z6 AS
(
SELECT ST_Simplify(geometry, ZRes(8)) AS geometry,
       osm_id,
       highway,
       construction,
       is_bridge,
       is_tunnel,
       is_ford,
       z_order
FROM osm_transportation_merge_linestring_gen_z7
WHERE (highway IN ('motorway', 'trunk') OR highway = 'construction' AND construction IN ('motorway', 'trunk'))
  AND ST_Length(geometry) > 100
    ) /* DELAY_MATERIALIZED_VIEW_CREATION */;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z6_geometry_idx
    ON osm_transportation_merge_linestring_gen_z6 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z6_highway_partial_idx
    ON osm_transportation_merge_linestring_gen_z6 (highway, construction)
    WHERE highway IN ('motorway', 'trunk', 'construction');

-- etldoc: osm_transportation_merge_linestring_gen_z6 -> osm_transportation_merge_linestring_gen_z5
DROP MATERIALIZED VIEW IF EXISTS osm_transportation_merge_linestring_gen_z5 CASCADE;
CREATE MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z5 AS
(
SELECT ST_Simplify(geometry, ZRes(7)) AS geometry,
       osm_id,
       highway,
       construction,
       is_bridge,
       is_tunnel,
       is_ford,
       z_order
FROM osm_transportation_merge_linestring_gen_z6
WHERE (highway IN ('motorway', 'trunk') OR highway = 'construction' AND construction IN ('motorway', 'trunk'))
  AND ST_Length(geometry) > 500
    ) /* DELAY_MATERIALIZED_VIEW_CREATION */;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z5_geometry_idx
    ON osm_transportation_merge_linestring_gen_z5 USING gist (geometry);
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z5_highway_partial_idx
    ON osm_transportation_merge_linestring_gen_z5 (highway, construction)
    WHERE highway IN ('motorway', 'trunk', 'construction');

-- etldoc: osm_transportation_merge_linestring_gen_z5 -> osm_transportation_merge_linestring_gen_z4
DROP MATERIALIZED VIEW IF EXISTS osm_transportation_merge_linestring_gen_z4 CASCADE;
CREATE MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z4 AS
(
SELECT ST_Simplify(geometry, ZRes(6)) AS geometry,
       osm_id,
       highway,
       construction,
       is_bridge,
       is_tunnel,
       is_ford,
       z_order
FROM osm_transportation_merge_linestring_gen_z5
WHERE (highway = 'motorway' OR highway = 'construction' AND construction = 'motorway')
  AND ST_Length(geometry) > 1000
    ) /* DELAY_MATERIALIZED_VIEW_CREATION */;
CREATE INDEX IF NOT EXISTS osm_transportation_merge_linestring_gen_z4_geometry_idx
    ON osm_transportation_merge_linestring_gen_z4 USING gist (geometry);


-- Handle updates

CREATE SCHEMA IF NOT EXISTS transportation;

CREATE TABLE IF NOT EXISTS transportation.updates
(
    id serial PRIMARY KEY,
    t text,
    UNIQUE (t)
);
CREATE OR REPLACE FUNCTION transportation.flag() RETURNS trigger AS
$$
BEGIN
    INSERT INTO transportation.updates(t) VALUES ('y') ON CONFLICT(t) DO NOTHING;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION transportation.refresh() RETURNS trigger AS
$$
DECLARE
    t TIMESTAMP WITH TIME ZONE := clock_timestamp();
BEGIN
    RAISE LOG 'Refresh transportation';
    REFRESH MATERIALIZED VIEW osm_highway_linestring_view;
    REFRESH MATERIALIZED VIEW osm_highway_linestring_gen_z11_view;
    REFRESH MATERIALIZED VIEW osm_highway_linestring_gen_z10_view;
    REFRESH MATERIALIZED VIEW osm_highway_linestring_gen_z9_view;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z8;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z7;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z6;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z5;
    REFRESH MATERIALIZED VIEW osm_transportation_merge_linestring_gen_z4;
    -- noinspection SqlWithoutWhere
    DELETE FROM transportation.updates;

    RAISE LOG 'Refresh transportation done in %', age(clock_timestamp(), t);
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_flag_transportation
    AFTER INSERT OR UPDATE OR DELETE
    ON osm_highway_linestring
    FOR EACH STATEMENT
EXECUTE PROCEDURE transportation.flag();

CREATE CONSTRAINT TRIGGER trigger_refresh
    AFTER INSERT
    ON transportation.updates
    INITIALLY DEFERRED
    FOR EACH ROW
EXECUTE PROCEDURE transportation.refresh();