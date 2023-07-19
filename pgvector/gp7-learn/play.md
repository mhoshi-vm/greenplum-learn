```
gpssh -f /home/gpadmin/hosts-all "python3.9 -m pip install -U --use-feature=2020-resolver sentence-transformers"
gpconfig -c plpython3.python_path -v "'/usr/local/greenplum-db-7.0.0-beta.4/ext/DataSciencePython3.9/lib/python3.9/site-packages'" --skipvalidation
gpstop -u
```

```
CREATE TABLE archive (
  id SERIAL,
  term text,
  title text,
  abstract text
) 
DISTRIBUTED BY (id);

COPY archive(term, title, abstract)
FROM '/home/gpadmin/arxiv_data_210930-054931.csv'
WITH CSV DELIMITER ',';

CREATE EXTENSION plpython3u;
SET plpython3.python_path='/home/gpadmin/.local/lib/python3.9/site-packages';

CREATE FUNCTION generate_embeddings (content text)
  RETURNS VECTOR
  LANGUAGE plpython3u
AS $$
  from sentence_transformers import SentenceTransformer
  model = SentenceTransformer('all-MiniLM-L6-v2')
  text = content  
  sentences = [ text ]
  
  #Sentences are encoded by calling model.encode()
  embeddings = model.encode(sentences)
  
  return embeddings[0].tolist()
$$;


CREATE TABLE document AS
SELECT id, term, title, abstract, generate_embeddings(abstract)
FROM archive;
```


