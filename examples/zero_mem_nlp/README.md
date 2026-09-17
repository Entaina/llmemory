# Zero-Mem NLP sidecar (reference)

Optional spaCy + BGE-M3 sidecar for local NER/embeddings. **Not** part of the `llmemory` gem and not required in CI.

Endpoints (batch JSON):

- `GET /health` → `{ "name", "version", "dimensions" }`
- `POST /ner` → `{ "text" }` → `{ "entities": [...] }`
- `POST /embed` → `{ "texts": [...] }` → `{ "vectors": [...] }`

Configure llmemory with `zero_mem_entity_extractor: :http` and `zero_mem_ner_http_url`.

Do not interpolate user input into shell commands when running this service.
