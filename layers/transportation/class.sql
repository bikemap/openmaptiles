CREATE OR REPLACE FUNCTION brunnel(is_bridge bool, is_tunnel bool, is_ford bool) RETURNS text AS
$$
SELECT CASE
           WHEN is_bridge THEN 'bridge'
           WHEN is_tunnel THEN 'tunnel'
           WHEN is_ford THEN 'ford'
           END;
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

-- The classes for highways are derived from the classes used in ClearTables
-- https://github.com/ClearTables/ClearTables/blob/master/transportation.lua
CREATE OR REPLACE FUNCTION highway_class(highway text, public_transport text, construction text) RETURNS text AS
$$
SELECT CASE
           %%FIELD_MAPPING: class %%
           END;
$$ LANGUAGE SQL IMMUTABLE
                PARALLEL SAFE;

-- The classes for railways are derived from the classes used in ClearTables
-- https://github.com/ClearTables/ClearTables/blob/master/transportation.lua
CREATE OR REPLACE FUNCTION railway_class(railway text) RETURNS text AS
$$
SELECT CASE
           WHEN railway IN ('rail', 'narrow_gauge', 'preserved', 'funicular') THEN 'rail'
           WHEN railway IN ('subway', 'light_rail', 'monorail', 'tram') THEN 'transit'
           END;
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

-- Limit service to only the most important values to ensure
-- we always know the values of service
CREATE OR REPLACE FUNCTION service_value(service text) RETURNS text AS
$$
SELECT CASE
           WHEN service IN ('spur', 'yard', 'siding', 'crossover', 'driveway', 'alley', 'parking_aisle') THEN service
           END;
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

-- Limit surface to only the most important values to ensure
-- we always know the values of surface
CREATE OR REPLACE FUNCTION surface_value(surface text) RETURNS text AS
$$
SELECT CASE
           WHEN surface IN ('paved', 'asphalt', 'cobblestone', 'concrete', 'concrete:lanes', 'concrete:plates', 'metal',
                            'paving_stones', 'sett', 'unhewn_cobblestone', 'wood') THEN 'paved'
           WHEN surface IN ('unpaved', 'compacted', 'dirt', 'earth', 'fine_gravel', 'grass', 'grass_paver', 'gravel',
                            'gravel_turf', 'ground', 'ice', 'mud', 'pebblestone', 'salt', 'sand', 'snow', 'woodchips')
               THEN 'unpaved'
           END;
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

CREATE OR REPLACE FUNCTION oneway_bicycle_value(oneway_bicycle TEXT) RETURNS boolean AS $$
    SELECT CASE
        WHEN NULLIF(oneway_bicycle, '') IS NULL THEN NULL
        WHEN oneway_bicycle in ('true', 'yes', '1') THEN TRUE
        ELSE FALSE
    END
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;


CREATE OR REPLACE FUNCTION cycleway_value(cycleway TEXT, cycleway_both TEXT, cycleway_left TEXT, cycleway_right TEXT, cyclestreet TEXT) RETURNS text AS $$
    SELECT CASE
        WHEN NULLIF(cycleway, '') IS NOT NULL THEN cycleway
        WHEN NULLIF(cycleway, '') IS NULL AND NULLIF(cycleway_both, '') IS NOT NULL THEN cycleway_both
        WHEN NULLIF(cycleway, '') IS NULL AND NULLIF(cycleway_both, '') IS NULL AND
             NULLIF(cycleway_left, '') IS NOT NULL THEN cycleway_left
        WHEN NULLIF(cycleway, '') IS NULL AND NULLIF(cycleway_both, '') IS NULL AND
             NULLIF(cycleway_left, '') IS NULL AND NULLIF(cycleway_right, '') IS NOT NULL THEN cycleway_right
        WHEN NULLIF(cycleway, '') IS NULL AND NULLIF(cycleway_both, '') IS NULL AND
             NULLIF(cycleway_left, '') IS NULL AND NULLIF(cycleway_right, '') IS NULL AND
             NULLIF(cyclestreet, '') IS NOT NULL THEN cyclestreet
        ELSE ''
    END;
$$
LANGUAGE SQL
IMMUTABLE STRICT PARALLEL SAFE;

-- Determine which transportation features are shown at zoom 12
CREATE OR REPLACE FUNCTION transportation_filter_z12(highway text, construction text) RETURNS boolean AS
$$
SELECT CASE
           WHEN highway IN ('unclassified', 'residential', 'cycleway') THEN TRUE
           WHEN highway_class(highway, '', construction) IN
               (
                'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'raceway',
                'motorway_construction', 'trunk_construction', 'primary_construction',
                'secondary_construction', 'tertiary_construction', 'raceway_construction',
                'busway', 'bus_guideway', 'cycleway'
               ) THEN TRUE --includes ramps
           ELSE FALSE
       END
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;

-- Determine which transportation features are shown at zoom 13
-- Assumes that piers have already been excluded
CREATE OR REPLACE FUNCTION transportation_filter_z13(highway text,
                                                     public_transport text,
                                                     construction text,
                                                     service text) RETURNS boolean AS
$$
SELECT CASE
           WHEN transportation_filter_z12(highway, construction) THEN TRUE
           WHEN highway = 'service' OR construction = 'service' THEN service NOT IN ('driveway', 'parking_aisle')
           WHEN highway_class(highway, public_transport, construction) IN ('minor', 'minor_construction') THEN TRUE
           ELSE FALSE
       END
$$ LANGUAGE SQL IMMUTABLE
                STRICT
                PARALLEL SAFE;
