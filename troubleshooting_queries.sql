\set table_names '{movies_tmdb,movies_tmdb_embeddings}'
\set column_name 'overview_embedding'
\set table_name 'movies_tmdb_embeddings'

-- Get table definition
\d+ :table_name

-- Get sizes for a table, its indexes, and its toast
SELECT 
    c.relname AS table_name,
    pg_relation_size(c.oid) / current_setting('block_size')::int AS table_pages,
    pg_indexes_size(c.oid) / current_setting('block_size')::int AS index_pages,
    pg_relation_size(c.reltoastrelid) / current_setting('block_size')::int AS toast_pages,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
WHERE c.relname = ANY(:'table_names'::text[]);

-- Get storage type for columns (to see if it can be toasted)
SELECT 
    attrelid::regclass AS table_name,
    attname AS column_name,
    attstorage AS storage_type,
    CASE attstorage
        WHEN 'p' THEN 'PLAIN: No compression or TOAST storage is used. Data is stored inline in the main table.'
        WHEN 'm' THEN 'MAIN: Column is compressed if the row does not fit in the 8KB page. Attempts to store inline first.'
        WHEN 'e' THEN 'EXTERNAL: Column is moved to the TOAST table without compression when it does not fit inline.'
        WHEN 'x' THEN 'EXTENDED: Default for large data types like TEXT and BYTEA. Data is compressed and moved to TOAST if necessary.'
        ELSE 'Unknown: Unrecognized storage type.'
    END AS storage_description
FROM pg_attribute
WHERE attrelid::regclass::text = ANY(:'table_names'::text[])
AND attname = :'column_name';

-- Get min and max row sizes
SELECT 
    MIN(pg_column_size(t.*)) AS min_row_size,
    MAX(pg_column_size(t.*)) AS max_row_size
FROM :table_name AS t;

-- Get min and max row sizes for a specific column
SELECT 
    MIN(pg_column_size(t.:column_name)) AS min_row_size,
    MAX(pg_column_size(t.:column_name)) AS max_row_size
FROM :table_name AS t;

-- Get index creation progress
SELECT phase, 
       round(100.0 * blocks_done / nullif(blocks_total, 0), 1) AS "% blocks", 
       round(100.0 * tuples_done / nullif(tuples_total, 0), 1) AS "% tuples" 
FROM pg_stat_progress_create_index;

