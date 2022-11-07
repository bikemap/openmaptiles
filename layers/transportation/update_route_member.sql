DROP TRIGGER IF EXISTS trigger_store_transportation_route_member ON osm_route_member;
DROP TRIGGER IF EXISTS trigger_store_transportation_superroute_member ON osm_superroute_member;
DROP TRIGGER IF EXISTS trigger_store_transportation_highway_linestring ON osm_highway_linestring;

CREATE TABLE IF NOT EXISTS ne_10m_admin_0_bg_buffer AS
SELECT ST_Buffer(geometry, 10000)
FROM ne_10m_admin_0_countries
WHERE iso_a2 = 'GB';

CREATE OR REPLACE VIEW gbr_route_members_view AS
SELECT 0,
       osm_id,
       substring(ref FROM E'^[AM][0-9AM()]+'),
       CASE WHEN highway = 'motorway' THEN 'omt-gb-motorway' ELSE 'omt-gb-trunk' END
FROM osm_highway_linestring
WHERE length(ref) > 0
  AND ST_Intersects(geometry, (SELECT * FROM ne_10m_admin_0_bg_buffer))
  AND highway IN ('motorway', 'trunk')
;

CREATE INDEX IF NOT EXISTS osm_highway_linestring_highway_partial_idx
    ON osm_highway_linestring (highway)
    WHERE highway IN ('motorway', 'trunk');

-- Create GBR relations (so we can use it in the same way as other relations)
DELETE
FROM osm_route_member
WHERE network IN ('omt-gb-motorway', 'omt-gb-trunk');
-- etldoc:  osm_highway_linestring ->  osm_route_member
INSERT INTO osm_route_member (osm_id, member, ref, network)
SELECT *
FROM gbr_route_members_view;

CREATE OR REPLACE FUNCTION osm_route_member_network_type(network text) RETURNS route_network_type AS
$$
SELECT CASE
           WHEN network = 'US:I' THEN 'us-interstate'::route_network_type
           WHEN network = 'US:US' THEN 'us-highway'::route_network_type
           WHEN network LIKE 'US:__' THEN 'us-state'::route_network_type
           -- https://en.wikipedia.org/wiki/Trans-Canada_Highway
           WHEN network LIKE 'CA:transcanada%' THEN 'ca-transcanada'::route_network_type
           WHEN network = 'omt-gb-motorway' THEN 'gb-motorway'::route_network_type
           WHEN network = 'omt-gb-trunk' THEN 'gb-trunk'::route_network_type
           WHEN network IN ('icn', 'ncn', 'rcn', 'lcn') THEN network::route_network_type
           END;
$$ LANGUAGE sql IMMUTABLE
                PARALLEL SAFE;

-- etldoc:  osm_route_member ->  osm_route_member
-- see http://wiki.openstreetmap.org/wiki/Relation:route#Road_routes
UPDATE osm_route_member
SET network_type = osm_route_member_network_type(network)
WHERE network != ''
  AND network_type IS DISTINCT FROM osm_route_member_network_type(network)
;

CREATE OR REPLACE FUNCTION update_osm_route_member() RETURNS void AS
$$
BEGIN

    ANALYZE transportation_name.superroute_changes;

    ALTER TABLE transportation_name.network_changes DISABLE TRIGGER trigger_flag_transportation_name;
    INSERT INTO transportation_name.network_changes(osm_id)
    WITH RECURSIVE recursive_superroute_children AS (
        SELECT osm_superroute_member.osm_id, osm_superroute_member.member
        FROM osm_superroute_member
        JOIN transportation_name.superroute_changes ON
            osm_superroute_member.osm_id = transportation_name.superroute_changes.osm_id
        UNION
        SELECT child.osm_id, child.member
        FROM osm_superroute_member child
        JOIN recursive_superroute_children ON child.osm_id = recursive_superroute_children.member
    )
    SELECT osm_route_member.member
    FROM osm_route_member, recursive_superroute_children
    WHERE osm_route_member.osm_id = recursive_superroute_children.member
    ON CONFLICT(osm_id) DO NOTHING;
    ALTER TABLE transportation_name.network_changes ENABLE TRIGGER trigger_flag_transportation_name;

    ANALYZE transportation_name.network_changes;

    DELETE
    FROM osm_route_member AS r
        USING
            transportation_name.network_changes AS c
    WHERE network IN ('omt-gb-motorway', 'omt-gb-trunk')
      AND r.osm_id = c.osm_id;

    INSERT INTO osm_route_member (osm_id, member, ref, network)
    SELECT r.*
    FROM gbr_route_members_view AS r
             JOIN transportation_name.network_changes AS c ON
        r.osm_id = c.osm_id;

    INSERT INTO osm_route_member (id, osm_id, network, network_type, concurrency_index, rank, name)
    SELECT
      rm.id,
      rm.osm_id,
      COALESCE(NULLIF(srm.network, ''), rm.network) AS network,
      osm_route_member_network_type(COALESCE(NULLIF(srm.network, ''), rm.network)) AS network_type,
      DENSE_RANK() OVER (
          PARTITION BY rm.member
          ORDER BY osm_route_member_network_type(COALESCE(NULLIF(srm.network, ''), rm.network)),
                   COALESCE(NULLIF(srm.network, ''), rm.network),
                   LENGTH(COALESCE(NULLIF(srm.ref, ''), rm.ref)),
                   COALESCE(NULLIF(srm.ref, ''), rm.ref)
          ) AS concurrency_index,
      CASE
           WHEN COALESCE(NULLIF(srm.network, ''), rm.network) IN ('iwn', 'nwn', 'rwn') THEN 1
           WHEN COALESCE(NULLIF(srm.network, ''), rm.network) = 'lwn' THEN 2
           WHEN rm.osmc_symbol || rm.colour <> '' THEN 2
      END AS rank,
      COALESCE(NULLIF(srm.name, ''), rm.name) AS name
    FROM osm_route_member rm
    LEFT OUTER JOIN (
        SELECT DISTINCT ON (ordered_superroute_members.member) NULL, ordered_superroute_members.* FROM (
            WITH RECURSIVE recursive_superroute_member AS (
                SELECT osm_id AS parent_osm_id, osm_id, 0 AS hierachy_index, member, role, network, ref, name
                FROM osm_superroute_member
                UNION
                SELECT parent.osm_id AS parent_osm_id, recursive_superroute_member.osm_id,
                       recursive_superroute_member.hierachy_index + 1 AS hierarchy_index,
                       recursive_superroute_member.member, parent.role, parent.network, parent.ref, parent.name
                FROM osm_superroute_member parent
                JOIN recursive_superroute_member ON parent.member = recursive_superroute_member.parent_osm_id
            )
            SELECT *, DENSE_RANK() OVER (
                PARTITION BY recursive_superroute_member.member
                ORDER BY osm_route_member_network_type(recursive_superroute_member.network),
                         recursive_superroute_member.hierachy_index DESC,
                         recursive_superroute_member.role = 'alternative',
                         recursive_superroute_member.network,
                         LENGTH(recursive_superroute_member.ref),
                         recursive_superroute_member.ref,
                         LENGTH(recursive_superroute_member.name),
                         NULLIF(recursive_superroute_member.name, '')
                ) AS dense_rank
            FROM recursive_superroute_member
        ) AS ordered_superroute_members
        WHERE ordered_superroute_members.dense_rank = 1
    ) AS srm ON srm.member = rm.osm_id
    WHERE rm.member IN
      (SELECT DISTINCT osm_id FROM transportation_name.network_changes)
    ON CONFLICT (id, osm_id) DO UPDATE SET concurrency_index = EXCLUDED.concurrency_index,
                                           rank = EXCLUDED.rank,
                                           network = EXCLUDED.network,
                                           network_type = EXCLUDED.network_type,
                                           name = EXCLUDED.name;

END;
$$ LANGUAGE plpgsql;

CREATE INDEX IF NOT EXISTS osm_route_member_network_idx ON osm_route_member ("network");
CREATE INDEX IF NOT EXISTS osm_route_member_member_idx ON osm_route_member ("member");
CREATE INDEX IF NOT EXISTS osm_route_member_name_idx ON osm_route_member ("name");
CREATE INDEX IF NOT EXISTS osm_route_member_ref_idx ON osm_route_member ("ref");

CREATE INDEX IF NOT EXISTS osm_route_member_network_type_idx ON osm_route_member ("network_type");

CREATE INDEX IF NOT EXISTS osm_highway_linestring_osm_id_idx ON osm_highway_linestring ("osm_id");
CREATE UNIQUE INDEX IF NOT EXISTS osm_highway_linestring_gen_z11_osm_id_idx ON osm_highway_linestring_gen_z11 ("osm_id");

ALTER TABLE osm_route_member ADD COLUMN IF NOT EXISTS concurrency_index int,
                             ADD COLUMN IF NOT EXISTS rank int;

CREATE TABLE IF NOT EXISTS "public"."osm_superroute_member" (
    "osm_id" bigint,
    "member" bigint,
    "role" varchar,
    "type" smallint,
    "ref" varchar,
    "network" varchar,
    "name" varchar
);

-- Create Primary-Keys for osm_superroute_member
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT constraint_name
        FROM information_schema.table_constraints
        WHERE table_name = 'osm_superroute_member' AND constraint_type = 'PRIMARY KEY'
    ) THEN
        ALTER TABLE "public"."osm_superroute_member" ADD PRIMARY KEY (osm_id, member);
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Create indexes to speed up update queries on osm_superroute_member
CREATE INDEX IF NOT EXISTS "osm_superroute_member_osm_id" ON "public"."osm_superroute_member" (osm_id);
CREATE INDEX IF NOT EXISTS "osm_superroute_member_member_id" ON "public"."osm_superroute_member" (member);

ANALYZE "public"."osm_superroute_member";

-- One-time load of concurrency indexes; updates occur via trigger
INSERT INTO osm_route_member (id, osm_id, network, network_type, concurrency_index, rank, name)
  SELECT
  rm.id,
  rm.osm_id,
  COALESCE(NULLIF(srm.network, ''), rm.network) AS network,
  osm_route_member_network_type(COALESCE(NULLIF(srm.network, ''), rm.network)) AS network_type,
  DENSE_RANK() OVER (
      PARTITION BY rm.member
      ORDER BY osm_route_member_network_type(COALESCE(NULLIF(srm.network, ''), rm.network)),
               COALESCE(NULLIF(srm.network, ''), rm.network),
               LENGTH(COALESCE(NULLIF(srm.ref, ''), rm.ref)),
               COALESCE(NULLIF(srm.ref, ''), rm.ref)
      ) AS concurrency_index,
  CASE
       WHEN COALESCE(NULLIF(srm.network, ''), rm.network) IN ('iwn', 'nwn', 'rwn') THEN 1
       WHEN COALESCE(NULLIF(srm.network, ''), rm.network) = 'lwn' THEN 2
       WHEN rm.osmc_symbol || rm.colour <> '' THEN 2
  END AS rank,
  COALESCE(NULLIF(srm.name, ''), rm.name) AS name
  FROM osm_route_member rm
  LEFT OUTER JOIN (
        SELECT DISTINCT ON (ordered_superroute_members.member) NULL, ordered_superroute_members.* FROM (
            WITH RECURSIVE recursive_superroute_member AS (
                SELECT osm_id AS parent_osm_id, osm_id, 0 AS hierachy_index, member, role, network, ref, name
                FROM osm_superroute_member
                UNION
                SELECT parent.osm_id AS parent_osm_id, recursive_superroute_member.osm_id,
                       recursive_superroute_member.hierachy_index + 1 AS hierarchy_index,
                       recursive_superroute_member.member, parent.role, parent.network, parent.ref, parent.name
                FROM osm_superroute_member parent
                JOIN recursive_superroute_member ON parent.member = recursive_superroute_member.parent_osm_id
            )
            SELECT *, DENSE_RANK() OVER (
                PARTITION BY recursive_superroute_member.member
                ORDER BY osm_route_member_network_type(recursive_superroute_member.network),
                         recursive_superroute_member.hierachy_index DESC,
                         recursive_superroute_member.role = 'alternative',
                         recursive_superroute_member.network,
                         LENGTH(recursive_superroute_member.ref),
                         recursive_superroute_member.ref,
                         LENGTH(recursive_superroute_member.name),
                         NULLIF(recursive_superroute_member.name, '')
                ) AS dense_rank
            FROM recursive_superroute_member
        ) AS ordered_superroute_members
        WHERE ordered_superroute_members.dense_rank = 1
    ) AS srm ON srm.member = rm.osm_id
  ON CONFLICT (id, osm_id) DO UPDATE SET concurrency_index = EXCLUDED.concurrency_index, rank = EXCLUDED.rank,
                                         network = EXCLUDED.network, network_type = EXCLUDED.network_type,
                                         name = EXCLUDED.name;;

UPDATE osm_highway_linestring hl
  SET network = rm.network_type
  FROM osm_route_member rm
  WHERE hl.osm_id=rm.member AND rm.concurrency_index=1;

UPDATE osm_highway_linestring_gen_z11 hl
  SET network = rm.network_type
  FROM osm_route_member rm
  WHERE hl.osm_id=rm.member AND rm.concurrency_index=1;
