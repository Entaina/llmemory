# Smart Commit - Commits agrupados por funcionalidad

Crea commits separados por funcionalidad, con mensajes explicativos para cada grupo.

## Proceso

1. **Analizar cambios**: Ejecuta `git status` y `git diff` para ver todos los archivos modificados, añadidos o eliminados.

2. **Agrupar por funcionalidad**: Agrupa los archivos según su propósito o componente:
   - Por ruta (ej: `lib/llmemory/short_term/`, `spec/retrieval/`)
   - Por feature (ej: MCP, long-term memory, extractors)
   - Por tipo (ej: tests, implementación, configuración)
   - Archivos relacionados que forman una unidad lógica van juntos

3. **Crear commits separados**: Para cada grupo:
   - Haz `git add` solo de los archivos de ese grupo
   - Escribe un mensaje de commit claro que explique qué funcionalidad o cambio representa
   - Ejecuta `git commit -m "mensaje"`
   - El mensaje debe ser descriptivo: qué hace el cambio, no solo "fix" o "update"

4. **Orden sugerido**: Primero dependencias/config, luego implementación, luego tests. O por feature completa (impl + specs juntos).

## Ejemplo de mensajes

- "Add NoiseFilter to filter low-value content before memorizing"
- "MCP: add MemoryTimelineContext tool for context around timestamp"
- "Short-term: MessageSanitizer removes orphaned tool_result messages"
- "Fix TemporalRanker exponential decay for evergreen candidates"

## Reglas

- No hagas commit de archivos que no tengan cambios relevantes
- Si el usuario indica algo después de `/git:commit`, úsalo como contexto (ej: `/git:commit solo los tests`)
- Usa mensajes en presente o imperativo: "Add X", "Fix Y", "Refactor Z"
