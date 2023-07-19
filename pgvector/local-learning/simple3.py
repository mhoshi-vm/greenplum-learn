from sentence_transformers import SentenceTransformer
model = SentenceTransformer('all-MiniLM-L6-v2')

#Our sentences we like to encode
sentences = ['this is a dog']

#Sentences are encoded by calling model.encode()
embeddings=model.encode(sentences)

print(mbeddings[0])

for i, embedding in enumerate(embeddings[0]): 
  ",".join
  print(i) 
  print(embedding)

