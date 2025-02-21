#!/usr/bin/python3 -u

"""
Usage:
    python3 query_tmdb.py "movie description" [limit] [distance_metric]

Arguments:
    movie description  - Text description to search for similar movies (required)
    limit             - Number of results to return (optional, default: 5)
    distance_metric   - Either 'euclidean' or 'cosine' (optional, default: euclidean)

Environment Variables:
    PGV_PSQL_EXPLAIN - Set to 1 to output EXPLAIN analysis to file
    PGV_PSQL_VERT    - Set to 1 for vertical output format
    PGV_PSQL_DEBUG   - Set to 1 for debug output

Example:
    python3 query_tmdb.py "A sci-fi movie about space travel" 10 cosine

"""

# Import libraries
from sentence_transformers import SentenceTransformer
import psycopg2
from psycopg2 import sql
import sys
import os
from prettytable import PrettyTable
from datetime import datetime

# PGV_PSQL_EXPLAIN -> Get EXPLAIN outputs written to file
psql_explain = int(os.getenv('PGV_PSQL_EXPLAIN', '0'))
# PGV_PSQL_VERT -> Get vertical outputs
psql_vert = int(os.getenv('PGV_PSQL_VERT', '0'))
# PGV_PSQL_DEBUG -> Get debug outputs
psql_debug = int(os.getenv('PGV_PSQL_DEBUG', '0'))

# Database connection parameters
db_config = {
    "host": "localhost",
    "database": "postgres", 
    "user": "postgres",
    "password": "verysecretpassword1^"
}

# Execute query and print results
def execute_and_print(cursor = None, query = ""):
    cursor.execute(query)
    # Fetch and print the results
    rows = cursor.fetchall()
    columns = [desc[0] for desc in cursor.description]
    table = PrettyTable()
    table.field_names = columns
    if psql_vert:
      for i, row in enumerate(rows, start=1):
        print(f"--- Record {i} ---")
        for col, value in zip(columns, row):
            print(f"{col}: {value}")
        print()
    else:
      for row in rows:
          table.add_row(row)
      print(table)
    return None

# Execute query EXPLAIN and print results to file
def execute_and_print_explain(cursor = None, query = ""):
    cursor.execute(query)
    # Fetch results and write to file
    rows = cursor.fetchall()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"explain_output_{timestamp}.out"
    print(f"\n## Query EXPLAIN sent to {filename}")
    with open(filename, 'w') as f:
        f.write(f"Query: {query}\n")
        for row in rows:
            f.write(f"{row}\n")
    return None

# Main script
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    # Get input from first argument
    input = sys.argv[1]
    if psql_debug == 1:
        print(f"Input: {input}")

    # Get limit from second argument, default to 5 if not provided
    limit = 5
    if len(sys.argv) > 2:
        try:
            limit = int(sys.argv[2])
            if psql_debug == 1:
                print(f"Limit: {limit}")
        except ValueError:
            print("Warning: Invalid limit provided, using default of 5")

    # Get distance metric from third argument, default to euclidean if not provided
    distance_metric = 'euclidean'
    if len(sys.argv) > 3:
        metric = sys.argv[3].lower()
        if metric in ['euclidean', 'cosine']:
            distance_metric = metric
        else:
            print("Warning: Invalid distance metric provided, using default of 'euclidean'")
    if psql_debug == 1:
        print(f"Distance metric: {distance_metric}")

    # Load model
    model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')

    # Encode input
    embedding = model.encode(input)
    embedding_vector = "["+','.join(map(str, embedding))+"]"

    # Set distance operator based on metric
    distance_operator = '<->' if distance_metric == 'euclidean' else '<=>'

    try:
        # Connect to PostgreSQL
        connection = psycopg2.connect(**db_config)
        connection.set_client_encoding("utf-8")
        cursor = connection.cursor()

        # Query
        query = f"""
            SELECT 
                m.id,
                m.title,
                m.vote_average,
                m.release_date,
                m.runtime,
                m.overview,
                CASE WHEN m.imdb_id IS NULL OR m.imdb_id = '' THEN 'N/A' ELSE 'https://www.imdb.com/title/' || m.imdb_id END AS imdb_url,
                (\'{embedding_vector}\' {distance_operator} e.overview_embedding) as distance
            FROM movies_tmdb m
            JOIN movies_tmdb_embeddings e ON m.id = e.id
            ORDER BY distance ASC 
            LIMIT {limit};"""
        execute_and_print(cursor, query)

        # Explain query
        if psql_explain == 1:
            query_explain = "EXPLAIN (ANALYZE, VERBOSE, BUFFERS, COSTS) "+query
            execute_and_print_explain(cursor, query_explain)

        # Close connection
        cursor.close()
        connection.close()

    except psycopg2.Error as e:
        print(f"Database connection error: {e}")
        sys.exit(1)
