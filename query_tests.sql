-- Enable timing (note some outputs here are redacted to remove timing information, to avoid cluttering the output)
postgres=# \timing on

-- Get ID of Interstellar movie, so we can get movies that are similar to it.
postgres=# SELECT id FROM movies_tmdb WHERE title = 'Interstellar';
   id   
--------
 157336
(1 row)

-- Get 5 movies with the lowest distance to Interstellar according to the overview embedding.
-- This was done by using Exact Nearest Neighbours Search, since we have no indexes created yet.
postgres=# SELECT                                 
    m.id,
    m.title,
    ((SELECT overview_embedding FROM movies_tmdb_embeddings WHERE id = 157336) <-> e.overview_embedding) as distance
FROM movies_tmdb m
JOIN movies_tmdb_embeddings e ON m.id = e.id
ORDER BY distance ASC 
LIMIT 5;
   id    |             title             |      distance      
---------+-------------------------------+--------------------
  157336 | Interstellar                  |                  0
  334847 | Aberrations                   | 0.6266655901339936
  838389 | Interstellar: Desgornias Cut  | 0.6367423866424898
   70981 | Prometheus                    |   0.79595452795547
 1338318 | Beachworld                    | 0.8277890225598951
(5 rows)

-- If you run the query again, you will see the same exact results are returned.

-- Increase the maintenance work mem so that index creation is faster
SET maintenance_work_mem = '3GB';

-- Create a new HNSW index on the overview_embedding column for the L2 distance.
postgres=# CREATE INDEX idx_overview_embedding_hnsw ON movies_tmdb_embeddings USING hnsw (overview_embedding vector_l2_ops);
CREATE INDEX
Time: 374447.374 ms (06:14.447)

-- Check progress on the index creation.
postgres=# SELECT phase, 
    round(100.0 * blocks_done / nullif(blocks_total, 0), 1) AS "% blocks", 
    round(100.0 * tuples_done / nullif(tuples_total, 0), 1) AS "% tuples" 
FROM pg_stat_progress_create_index;
             phase              | % blocks | % tuples 
--------------------------------+----------+----------
 building index: loading tuples |     43.4 |         
(1 row)

-- Verify the index was created
postgres=# \d+ movies_tmdb_embeddings;
                                          Table "public.movies_tmdb_embeddings"
       Column       |    Type     | Collation | Nullable | Default | Storage  | Compression | Stats target | Description 
--------------------+-------------+-----------+----------+---------+----------+-------------+--------------+-------------
 id                 | bigint      |           | not null |         | plain    |             |              | 
 overview_embedding | vector(384) |           |          |         | external |             |              | 
Indexes:
    "movies_tmdb_embeddings_pkey" PRIMARY KEY, btree (id)
    "idx_overview_embedding_hnsw" hnsw (overview_embedding vector_l2_ops)

-- Get all the indexes from tables that start with 'movie'
postgres=# SELECT                                           
    idx.indexrelid AS index_oid,
    i.relname AS index_name, 
    idx.indisvalid AS index_is_valid,
    t.oid AS table_oid,
    t.relname AS table_name,
    ns.nspname AS schema_name
FROM pg_index AS idx
JOIN pg_class AS i ON i.oid = idx.indexrelid
JOIN pg_class AS t ON t.oid = idx.indrelid
JOIN pg_namespace AS ns ON ns.oid = t.relnamespace
WHERE t.relname LIKE 'movie%'
ORDER BY ns.nspname, t.relname, i.relname;
 index_oid |             index_name              | index_is_valid | table_oid |       table_name       | schema_name 
-----------+-------------------------------------+----------------+-----------+------------------------+-------------
     16764 | movies_tmdb_pkey                    | t              |     16725 | movies_tmdb            | public
     16778 | idx_overview_embedding_hnsw         | t              |     16730 | movies_tmdb_embeddings | public
(2 rows)

-- Run EXPLAIN to see the query plan. It's using the HNSW index we created ("index scan on idx_overview_embedding_hnsw").
postgres=# EXPLAIN (analyze,verbose,buffers,costs) 
SELECT                                 
    m.id,
    m.title,
    ((SELECT overview_embedding FROM movies_tmdb_embeddings WHERE id = 157336) <-> e.overview_embedding) as distance
FROM movies_tmdb m
JOIN movies_tmdb_embeddings e ON m.id = e.id
ORDER BY distance ASC 
LIMIT 5;
                                                                        QUERY PLAN                         
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=834.93..848.46 rows=5 width=38) (actual time=1.810..1.850 rows=5 loops=1)
   Output: m.id, m.title, (((InitPlan 1).col1 <-> e.overview_embedding))
   Buffers: shared hit=1141
   InitPlan 1
     ->  Index Scan using movies_tmdb_embeddings_pkey on public.movies_tmdb_embeddings  (cost=0.43..8.45 rows=1 width=1544) (actual time=0.017..0.019 rows=1 loops=1)
           Output: movies_tmdb_embeddings.overview_embedding
           Index Cond: (movies_tmdb_embeddings.id = 157336)
           Buffers: shared hit=4
   ->  Nested Loop  (cost=826.48..3170090.72 rows=1171172 width=38) (actual time=1.809..1.847 rows=5 loops=1)
         Output: m.id, m.title, ((InitPlan 1).col1 <-> e.overview_embedding)
         Inner Unique: true
         Buffers: shared hit=1141
         ->  Index Scan using idx_overview_embedding_hnsw on public.movies_tmdb_embeddings e  (cost=826.06..2356623.51 rows=1171172 width=1552) (actual time=1.791..1.797 rows=5 loops=1)
               Output: e.id, e.overview_embedding
               Order By: (e.overview_embedding <-> (InitPlan 1).col1)
               Buffers: shared hit=1121
         ->  Index Scan using movies_tmdb_pkey on public.movies_tmdb m  (cost=0.43..0.69 rows=1 width=30) (actual time=0.007..0.007 rows=1 loops=5)
               Output: m.id, m.title, m.vote_average, m.vote_count, m.status, m.release_date, m.revenue, m.runtime, m.adult, m.backdrop_path, m.budget, m.homepage, m.imdb_id, m.original_language, m.original_title, m.overview, m.popularity, m.poster_path, m.tagline, m.genres, m.production_companies, m.production_countries, m.spoken_languages, m.keywords
               Index Cond: (m.id = e.id)
               Buffers: shared hit=20
 Planning:
   Buffers: shared hit=17
 Planning Time: 0.536 ms
 Execution Time: 1.896 ms
(24 rows)
Time: 3.073 ms


-- Disable the index
postgres=# UPDATE pg_index SET indisvalid = false WHERE indexrelid = 'idx_overview_embedding_hnsw'::regclass;
UPDATE 1

-- Check the index is disabled
postgres=# SELECT indisvalid FROM pg_index WHERE indexrelid = 'idx_overview_embedding_hnsw'::regclass;
 indisvalid 
------------
 f
(1 row)

-- Run the query again, and check the query plan and execution time.
-- It's using a full table scan ("parallel seq scan on movies_tmdb_embeddings") and it's much slower.
postgres=# EXPLAIN (analyze,verbose,buffers,costs) 
SELECT                                 
    m.id,
    m.title,
    ((SELECT overview_embedding FROM movies_tmdb_embeddings WHERE id = 157336) <-> e.overview_embedding) as distance
FROM movies_tmdb m
JOIN movies_tmdb_embeddings e ON m.id = e.id
ORDER BY distance ASC 
LIMIT 5;
                                                                                     QUERY PLAN                                                                                      
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=525308.33..525308.91 rows=5 width=38) (actual time=6303.111..6583.445 rows=5 loops=1)
   Output: m.id, m.title, (((InitPlan 1).col1 <-> e.overview_embedding))
   Buffers: shared hit=72293 read=231195, temp read=241218 written=244020
   InitPlan 1
     ->  Index Scan using movies_tmdb_embeddings_pkey on public.movies_tmdb_embeddings  (cost=0.43..8.45 rows=1 width=1544) (actual time=0.016..0.019 rows=1 loops=1)
           Output: movies_tmdb_embeddings.overview_embedding
           Index Cond: (movies_tmdb_embeddings.id = 157336)
           Buffers: shared hit=4
   ->  Gather Merge  (cost=525299.88..639171.70 rows=975976 width=38) (actual time=6303.109..6583.440 rows=5 loops=1)
         Output: m.id, m.title, (((InitPlan 1).col1 <-> e.overview_embedding))
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=72293 read=231195, temp read=241218 written=244020
         ->  Sort  (cost=524299.86..525519.83 rows=487988 width=38) (actual time=6297.728..6297.739 rows=4 loops=3)
               Output: m.id, m.title, (((InitPlan 1).col1 <-> e.overview_embedding))
               Sort Key: (((InitPlan 1).col1 <-> e.overview_embedding))
               Sort Method: top-N heapsort  Memory: 25kB
               Buffers: shared hit=72289 read=231195, temp read=241218 written=244020
               Worker 0:  actual time=6295.504..6295.513 rows=5 loops=1
                 Sort Method: top-N heapsort  Memory: 25kB
                 Buffers: shared hit=24054 read=76608, temp read=81483 written=80804
               Worker 1:  actual time=6295.493..6295.505 rows=5 loops=1
                 Sort Method: top-N heapsort  Memory: 25kB
                 Buffers: shared hit=23976 read=76847, temp read=80533 written=81084
               ->  Parallel Hash Join  (cost=339132.73..516194.56 rows=487988 width=38) (actual time=5644.639..6239.657 rows=390391 loops=3)
                     Output: m.id, m.title, ((InitPlan 1).col1 <-> e.overview_embedding)
                     Inner Unique: true
                     Hash Cond: (m.id = e.id)
                     Buffers: shared hit=72273 read=231195, temp read=241218 written=244020
                     Worker 0:  actual time=5636.351..6237.047 rows=400594 loops=1
                       Buffers: shared hit=24046 read=76608, temp read=81483 written=80804
                     Worker 1:  actual time=5645.391..6237.955 rows=388704 loops=1
                       Buffers: shared hit=23968 read=76847, temp read=80533 written=81084
                     ->  Parallel Seq Scan on public.movies_tmdb m  (cost=0.00..74007.88 rows=487988 width=30) (actual time=0.075..244.018 rows=390391 loops=3)
                           Output: m.id, m.title
                           Buffers: shared hit=69128
                           Worker 0:  actual time=0.022..246.299 rows=390302 loops=1
                             Buffers: shared hit=23061
                           Worker 1:  actual time=0.098..244.369 rows=388134 loops=1
                             Buffers: shared hit=22949
                     ->  Parallel Hash  (cost=239151.88..239151.88 rows=487988 width=1552) (actual time=5293.446..5293.446 rows=390391 loops=3)
                           Output: e.overview_embedding, e.id
                           Buckets: 8192  Batches: 256  Memory Usage: 7712kB
                           Buffers: shared hit=3077 read=231195, temp written=234804
                           Worker 0:  actual time=5291.234..5291.234 rows=387607 loops=1
                             Buffers: shared hit=951 read=76608, temp written=77732
                           Worker 1:  actual time=5291.291..5291.292 rows=389160 loops=1
                             Buffers: shared hit=985 read=76847, temp written=78012
                           ->  Parallel Seq Scan on public.movies_tmdb_embeddings e  (cost=0.00..239151.88 rows=487988 width=1552) (actual time=0.079..3901.550 rows=390391 loops=3)
                                 Output: e.overview_embedding, e.id
                                 Buffers: shared hit=3077 read=231195
                                 Worker 0:  actual time=0.091..3911.247 rows=387607 loops=1
                                   Buffers: shared hit=951 read=76608
                                 Worker 1:  actual time=0.098..3901.493 rows=389160 loops=1
                                   Buffers: shared hit=985 read=76847
 Planning:
   Buffers: shared hit=24
 Planning Time: 0.587 ms
 Execution Time: 6583.529 ms
(59 rows)
Time: 6584.721 ms (00:06.585)

-- Change hnsw.ef_search to 1 and see what happens.
-- Even if we used LIMIT 5 as before, we have only one row returned, because the dynamic list used is of size 1.
postgres=# SET hnsw.ef_search = 1;
SET 

-- Run the query again, and see the results.
postgres=# SELECT                                 
    m.id,                              
    m.title,
    ((SELECT overview_embedding FROM movies_tmdb_embeddings WHERE id = 157336) <-> e.overview_embedding) as distance
FROM movies_tmdb m                                                                                                  
JOIN movies_tmdb_embeddings e ON m.id = e.id
ORDER BY distance ASC 
LIMIT 5;
   id   |    title     | distance 
--------+--------------+----------
 157336 | Interstellar |        0
(1 row)
Time: 1.501 ms

-- Check the number of rows in the movies_tmdb_embeddings table, to choose the optimal number of lists for the IVFFlat index.
-- Default is 100 lists
postgres=# SELECT COUNT(*) AS total_count, COUNT(*)/1000 AS if_less_than_1M, SQRT(COUNT(*)) AS if_more_than_1M FROM movies_tmdb_embeddings;
 total_count | if_less_than_1m |  if_more_than_1m   
-------------+-----------------+--------------------
     1171172 |            1171 | 1082.2070042279342
(1 row)

-- Create a new IVFFlat index on the overview_embedding column for the cosine distance
postgres=# CREATE INDEX idx_overview_embedding_ivfflat ON movies_tmdb_embeddings USING ivfflat (overview_embedding vector_cosine_ops);
CREATE INDEX
Time: 35151.246 ms (00:35.151)

-- Run query (note we are now using the <=> operator for the cosine distance).
-- It's using the IVFFlat index ("index scan on idx_overview_embedding_ivfflat").
postgres=# EXPLAIN (analyze,verbose,buffers,costs) 
SELECT                                 
    m.id,
    m.title,
    ((SELECT overview_embedding FROM movies_tmdb_embeddings WHERE id = 157336) <=> e.overview_embedding) as distance
FROM movies_tmdb m
JOIN movies_tmdb_embeddings e ON m.id = e.id
ORDER BY distance ASC 
LIMIT 5;
                                                                                  QUERY PLAN
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=5954.19..5964.43 rows=5 width=38) (actual time=6.727..6.766 rows=5 loops=1)
   Output: m.id, m.title, (((InitPlan 1).col1 <=> e.overview_embedding))
   Buffers: shared hit=1501
   InitPlan 1
     ->  Index Scan using movies_tmdb_embeddings_pkey on public.movies_tmdb_embeddings  (cost=0.43..8.45 rows=1 width=1544) (actual time=0.015..0.017 rows=1 loops=1)
           Output: movies_tmdb_embeddings.overview_embedding
           Index Cond: (movies_tmdb_embeddings.id = 157336)
           Buffers: shared hit=4
   ->  Nested Loop  (cost=5945.74..2405802.22 rows=1171172 width=38) (actual time=6.725..6.761 rows=5 loops=1)
         Output: m.id, m.title, ((InitPlan 1).col1 <=> e.overview_embedding)
         Inner Unique: true
         Buffers: shared hit=1501
         ->  Index Scan using idx_overview_embedding_ivfflat on public.movies_tmdb_embeddings e  (cost=5945.31..1592335.01 rows=1171172 width=1552) (actual time=6.698..6.704 rows=5 loops=1)
               Output: e.id, e.overview_embedding
               Order By: (e.overview_embedding <=> (InitPlan 1).col1)
               Buffers: shared hit=1481
         ->  Index Scan using movies_tmdb_pkey on public.movies_tmdb m  (cost=0.43..0.69 rows=1 width=30) (actual time=0.008..0.008 rows=1 loops=5)
               Output: m.id, m.title, m.vote_average, m.vote_count, m.status, m.release_date, m.revenue, m.runtime, m.adult, m.backdrop_path, m.budget, m.homepage, m.imdb_id, m.original_language, m.original_title, m.overview, m.popularity, m.poster_path, m.tagline, m.genres, m.production_companies, m.production_countries, m.spoken_languages, m.keywords
               Index Cond: (m.id = e.id)
               Buffers: shared hit=20
 Planning:
   Buffers: shared hit=39 dirtied=1
 Planning Time: 0.700 ms
 Execution Time: 6.840 ms
(24 rows)
Time: 8.287 ms

-- Change ivfflat.probes to 1000 and see what happens.
-- It reverts to using a full table scan because the number of probes is too high (more than the default of 100)
postgres=# SET ivfflat.probes = 1000;
SET

postgres=# SELECT
    m.id,
    m.title,
    ((SELECT overview_embedding FROM movies_tmdb_embeddings WHERE id = 157336) <=> e.overview_embedding) as distance
FROM movies_tmdb m
JOIN movies_tmdb_embeddings e ON m.id = e.id
ORDER BY distance ASC 
LIMIT 5;
   id    |             title             |      distance       
---------+-------------------------------+---------------------
  157336 | Interstellar                  |                   0
  334847 | Aberrations                   |  0.1963548899783052
  838389 | Interstellar: Desgornias Cut  | 0.20272039199355452
   70981 | Prometheus                    | 0.31677184304855266
 1338318 | Beachworld                    | 0.34261733376538495
(5 rows)
Time: 7917.807 ms (00:07.918)

-- Run the query again, and check the query plan.
-- It's using a full table scan ("parallel seq scan on movies_tmdb_embeddings").
postgres=# EXPLAIN (analyze,verbose,buffers,costs) SELECT                                 
    m.id,
    m.title,
    ((SELECT overview_embedding FROM movies_tmdb_embeddings WHERE id = 157336) <=> e.overview_embedding) as distance
FROM movies_tmdb m
JOIN movies_tmdb_embeddings e ON m.id = e.id
ORDER BY distance ASC 
LIMIT 5;
-- OUTPUT TRIMMED --
-- ...
                           ->  Parallel Seq Scan on public.movies_tmdb_embeddings e  (cost=0.00..239151.88 rows=487988 width=1552) (actual time=0.086..304.781 rows=390391 loops=3)
                                 Output: e.overview_embedding, e.id
                                 Buffers: shared hit=13530 read=220742
                                 Worker 0:  actual time=0.098..309.637 rows=393362 loops=1
                                   Buffers: shared hit=4439 read=74271
                                 Worker 1:  actual time=0.095..306.470 rows=383640 loops=1
                                   Buffers: shared hit=4403 read=72325
 Planning:
   Buffers: shared hit=17
 Planning Time: 0.536 ms
 Execution Time: 2295.696 ms
(59 rows)

-- Create a new IVFFlat index with 1082 lists (the square root of the number of rows in the movies_tmdb_embeddings table)
postgres=# CREATE INDEX idx_overview_embedding_ivfflat_1082 ON movies_tmdb_embeddings USING ivfflat (overview_embedding vector_cosine_ops) WITH (lists = 1082);
CREATE INDEX
Time: 109343.134 ms (01:49.343)

-- Set the number of probes back to 1 (its default) and run query
postgres=# SET ivfflat.probes = 1;
SET

-- Run query
-- This is the first example we see of differences in results. As we discussed, the local minimum for the neighbourhood search
-- is not the global minimum, and we get a different result set. Since we increased the amount of lists created, the amount of
-- vectors in each is lower, and we would need to increase the probes to search in more of them
postgres=# SELECT                                 
    m.id,
    m.title,
    ((SELECT overview_embedding FROM movies_tmdb_embeddings WHERE id = 157336) <=> e.overview_embedding) as distance
FROM movies_tmdb m
JOIN movies_tmdb_embeddings e ON m.id = e.id
ORDER BY distance ASC 
LIMIT 5;
   id    |            title             |      distance       
---------+------------------------------+---------------------
  157336 | Interstellar                 |                   0
   70981 | Prometheus                   | 0.31677184304855266
  726394 | Banff Mountain Film Festival |  0.4086388240622062
  611409 | True North                   | 0.41242484487368547
 1005292 | Det Snöar om Börken          | 0.42771536955672596
(5 rows)

Time: 2.644 ms
