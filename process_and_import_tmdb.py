#!/usr/bin/python3 -u
from sentence_transformers import SentenceTransformer
import psycopg2
import csv
from psycopg2 import sql
from datetime import datetime

# Database connection parameters
db_config = {
    "host": "localhost",
    "database": "postgres",
    "user": "postgres",
    "password": "verysecretpassword1^"
}

# Load model
model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')

# Connect to PostgreSQL
connection = psycopg2.connect(**db_config)
connection.set_client_encoding("utf-8")
cursor = connection.cursor()

# Insert query for movies
insert_query_movies = sql.SQL("""
    INSERT INTO movies_tmdb (
        id, title, vote_average, vote_count, status, release_date, revenue, runtime, adult, backdrop_path, budget, 
        homepage, imdb_id, original_language, original_title, overview, popularity, poster_path, tagline, genres, 
        production_companies, production_countries, spoken_languages, keywords
    ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (id) DO NOTHING
""")

# Insert query for movies embeddings
insert_query_movies_embeddings = sql.SQL("""
    INSERT INTO movies_tmdb_embeddings (
        id, overview_embedding
    ) VALUES (%s, %s)
    ON CONFLICT (id) DO NOTHING
""")

# TMDB CSV file
tmdb_csv_file = '/var/lib/pgsql/src/TMDB_movie_dataset_v11.csv'

# Count rows
count_rows = 0
total_rows = sum(1 for line in open(tmdb_csv_file, 'r')) - 1  # Subtract 1 for header

# Open CSV file
with open(tmdb_csv_file, 'r') as file:
    print(f"Opened file: {tmdb_csv_file}")
    csv_reader = csv.reader(file)
    # Skip first line (header)
    next(csv_reader)
    # Process other lines
    for row in csv_reader:
      id, title, vote_average, vote_count, status, release_date, revenue, runtime, adult, backdrop_path, budget, homepage, imdb_id, original_language, original_title, overview, popularity, poster_path, tagline, genres, production_companies, production_countries, spoken_languages, keywords = row

      # Encode overview
      overview_embedding = model.encode(overview)
      overview_embedding_vector = "["+','.join(map(str, overview_embedding))+"]"

      # Insert movie
      cursor.execute(insert_query_movies, (
          id, title, vote_average, vote_count, status, release_date, revenue, runtime, adult, backdrop_path, budget, 
          homepage, imdb_id, original_language, original_title, overview, popularity, poster_path, tagline, genres, 
          production_companies, production_countries, spoken_languages, keywords
      ))

      # Insert movie embeddings
      cursor.execute(insert_query_movies_embeddings, (
          id, overview_embedding_vector
      ))

      # Commit every 2000 rows
      count_rows += 1
      if count_rows % 2000 == 0:
        connection.commit()
        current_time = datetime.now().strftime("%H:%M:%S %Z")
        percentage = (count_rows / total_rows) * 100
        print(f"Committing after 2000 rows. Current row number: {count_rows}/{total_rows} ({percentage:.1f}%) at {current_time}")

# Final commit for any remaining rows
connection.commit()
# Close connection
cursor.close()
connection.close()
