# Upversion - Release nueva versión

Ejecuta el proceso completo de release de la gema llmemory.

## Parámetros

Si el usuario especifica algo después de `/upversion`, es el tipo de bump:
- **patch** (por defecto): 0.1.14 → 0.1.15
- **minor**: 0.1.14 → 0.2.0
- **major**: 0.1.14 → 1.0.0

Ejemplos: `/upversion`, `/upversion minor`, `/upversion major`

## Acción

Ejecutar en el directorio del proyecto:

```bash
bundle exec rake release:bump[bump_type]
```

Donde `bump_type` es patch, minor o major según lo indicado (por defecto: patch).

La tarea rake primero comprueba: rama actual es main, no hay cambios sin commit, y ejecuta los tests. Si todo pasa: incremento de versión, bundle install, CHANGELOG.txt, commit, push, tag y push del tag.
