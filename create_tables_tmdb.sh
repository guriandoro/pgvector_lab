#!/bin/bash
psql -c "DROP TABLE IF EXISTS movies_tmdb;"
psql -c "CREATE TABLE movies_tmdb (id BIGINT PRIMARY KEY, title TEXT, vote_average FLOAT, vote_count BIGINT, status TEXT, release_date TEXT, revenue BIGINT, runtime INT, adult BOOLEAN, backdrop_path TEXT, budget BIGINT, homepage TEXT, imdb_id TEXT, original_language TEXT, original_title TEXT, overview TEXT, popularity FLOAT, poster_path TEXT, tagline TEXT, genres TEXT, production_companies TEXT, production_countries TEXT, spoken_languages TEXT, keywords TEXT)"
psql -c "DROP TABLE IF EXISTS movies_tmdb_embeddings;"
psql -c "CREATE TABLE movies_tmdb_embeddings (id BIGINT PRIMARY KEY, overview_embedding vector(384))"
