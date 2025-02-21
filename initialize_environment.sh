anydbver -n pgvector deploy ppg:17

anydbver -n pgvector exec 

yum install -q -y percona-pgvector_17 \
  && echo "PERCONA PGVECTOR Installation: OK" || echo "PERCONA PGVECTOR Installation: Not OK"
yum install -q -y python3.12 python3.12-pip python3.12-devel python3.12-psycopg2 python3.12-libs \
  && echo "PYTHON 3.12 Installation: OK" || echo "PYTHON 3.12 Installation: Not OK"
yum install -q -y unzip \
  && echo "UNZIP Installation: OK" || echo "UNZIP Installation: Not OK"
#yum remove -q -y python3-pip
rm -f /etc/alternatives/python3
ln -s /usr/bin/python3.12 /etc/alternatives/python3
rm -f /etc/alternatives/pip3
ln -s /usr/bin/pip3.12 /etc/alternatives/pip3

pip3 -q install sentence-transformers prettytable \
  && echo "PIP SENTENCE TRANSFORMERS Installation: OK" || echo "PIP SENTENCE TRANSFORMERS Installation: Not OK"

echo "alias ll='ls -l --color=auto'" >> ~/.bashrc
source ~/.bashrc

# Tune postgres
{
echo "alter system set checkpoint_timeout = 1800;"
echo "alter system set max_wal_size = '20GB';"
echo "alter system set min_wal_size = '10GB';"
echo "alter system set shared_buffers = '5GB';"
} | psql

systemctl restart postgresql-17

{
echo "CREATE EXTENSION IF NOT EXISTS vector;"
echo "\dx;"
echo "DROP TABLE IF EXISTS test_embeddings;"
echo "CREATE TABLE test_embeddings (id BIGSERIAL PRIMARY KEY, sentence text, embedding vector(384));"
} | psql

mkdir -p ~/src
cd ~/src

curl -L -o `pwd`/tmdb-movies-dataset-2023-930k-movies.zip https://www.kaggle.com/api/v1/datasets/download/asaniczka/tmdb-movies-dataset-2023-930k-movies
unzip tmdb-movies-dataset-2023-930k-movies.zip
ls -lh TMDB_movie_dataset_v11.csv

chmod +x create_tables_tmdb.sh
./create_tables_tmdb.sh

chmod +x process_and_import_tmdb.py
nohup ./process_and_import_tmdb.py > process_and_import_tmdb.py.nohup.out 2>&1 &

chmod +x query_tmdb.py
PGV_PSQL_EXPLAIN=0 PGV_PSQL_VERT=1 PGV_PSQL_DEBUG=0 ./query_tmdb.py "astronauts in space"

psql -c "CREATE INDEX ON movies_tmdb_embeddings USING ivfflat (overview_embedding vector_l2_ops) WITH (lists = 100);"

PGV_PSQL_EXPLAIN=0 PGV_PSQL_VERT=1 PGV_PSQL_DEBUG=0 ./query_tmdb.py "astronauts in space" 10

psql -c "CREATE INDEX ON movies_tmdb_embeddings USING hnsw (overview_embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);"

PGV_PSQL_EXPLAIN=0 PGV_PSQL_VERT=1 PGV_PSQL_DEBUG=0 ./query_tmdb.py "astronauts in space" 10 cosine

