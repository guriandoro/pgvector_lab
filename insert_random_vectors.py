#!/usr/bin/env python3

"""
Usage:
    Modify the code to set the desired table names, vector dimensions and number of tuples, and run the python script.
"""

# Import libraries
import psycopg2
import random

# Database connection parameters
db_config = {
    "host": "localhost",
    "database": "postgres",
    "user": "postgres",
    "password": "verysecretpassword1^"
}

# Table names and dimensions
TABLE_1 = "table_400"
DIMENSION_1 = 400
TABLE_2 = "table_500"
DIMENSION_2 = 500
# Number of rows to insert into each table
NUM_ROWS = 100000

# Function to generate a random vector of specified dimensions
def generate_random_vector(dim):
    return [random.uniform(-1, 1) for _ in range(dim)]

# Function to create tables
def create_tables(connection):
    try:
        with connection.cursor() as cursor:
            cursor.execute(f"""
                CREATE TABLE IF NOT EXISTS {TABLE_1} (
                    id SERIAL PRIMARY KEY,
                    embedding VECTOR({DIMENSION_1})
                );
            """)
            cursor.execute(f"""
                CREATE TABLE IF NOT EXISTS {TABLE_2} (
                    id SERIAL PRIMARY KEY,
                    embedding VECTOR({DIMENSION_2})
                );
            """)
        connection.commit()
        print("Tables created successfully.")
    except Exception as e:
        connection.rollback()
        print(f"Error creating tables: {e}")

# Function to insert random data into a table
def insert_random_data(table_name, dimension, num_rows, connection):
    try:
        with connection.cursor() as cursor:
            print(f"Inserting {num_rows} rows into {table_name}...")
            for _ in range(num_rows):
                vector = generate_random_vector(dimension)
                cursor.execute(
                    f"INSERT INTO {table_name} (embedding) VALUES (%s)",
                    (vector,)
                )
                if _ % 5000 == 0:
                    connection.commit()
                    print(f"Inserted {_} rows into {table_name}.")
        connection.commit()
        print(f"Inserted {num_rows} rows into {table_name}.")
    except Exception as e:
        connection.rollback()
        print(f"Error inserting data into {table_name}: {e}")

# Main script
if __name__ == "__main__":
    try:
        # Connect to the PostgreSQL database
        with psycopg2.connect(**db_config) as conn:
            # Create tables
            create_tables(conn)
            # Insert random data into the first table
            insert_random_data(TABLE_1, DIMENSION_1, NUM_ROWS, conn)
            # Insert random data into the second table
            insert_random_data(TABLE_2, DIMENSION_2, NUM_ROWS, conn)
    except psycopg2.Error as e:
        print(f"Database connection error: {e}")
