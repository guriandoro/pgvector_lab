#!/usr/bin/python3

# Import libraries
from sentence_transformers import SentenceTransformer, SimilarityFunction

# Load model
model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')

# Encode words
embedding_king = model.encode("king")
embedding_man = model.encode("man")
embedding_woman = model.encode("woman")
embedding_queen = model.encode("queen")

# Print results for COSINE similarity (default)
print("\nCOSINE similarity (default):")
print("King - Man + Woman = Queen")
print(model.similarity(embedding_king-embedding_man+embedding_woman, embedding_queen))
print("Queen + Man - Woman = King")
print(model.similarity(embedding_queen+embedding_man-embedding_woman, embedding_king))
print("King - Man + Man = King")
print(model.similarity(embedding_king-embedding_man+embedding_man, embedding_king))

# Switch to EUCLIDEAN similarity
model.similarity_fn_name = SimilarityFunction.EUCLIDEAN

# Print results for EUCLIDEAN similarity 
print("\nEUCLIDEAN similarity:")
print("King - Man + Woman = Queen")
print(model.similarity(embedding_king-embedding_man+embedding_woman, embedding_queen))
print("Queen + Man - Woman = King")
print(model.similarity(embedding_queen+embedding_man-embedding_woman, embedding_king))
print("King - Man + Man = King")
print(model.similarity(embedding_king-embedding_man+embedding_man, embedding_king))
