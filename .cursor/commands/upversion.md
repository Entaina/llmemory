# Upversion - Release nueva versión

Ejecuta el proceso completo de release de la gema llmemory.

## Parámetros

Si el usuario especifica algo después de `/upversion`, es el tipo de bump:
- **patch** (por defecto): 0.2.6 → 0.2.7
- **minor**: 0.2.6 → 0.3.0
- **major**: 0.2.6 → 1.0.0

Ejemplos: `/upversion`, `/upversion minor`, `/upversion major`

## Acción (obligatoria en dos pasos)

**No ejecutes `release:bump` sin redactar antes las notas de release.** El changelog debe describir cambios relevantes para el usuario (Added / Changed / Fixed / Removed / Notes), **no** una lista de commits.

### 1. Analizar cambios desde el último tag

```bash
bundle exec rake release:since_tag
git log $(git describe --tags --abbrev=0)..HEAD --oneline
git diff $(git describe --tags --abbrev=0)..HEAD --stat
```

Revisa el diff y los commits para entender el impacto funcional. Ignora ruido interno (refactors sin efecto visible, typos en specs, etc.).

### 2. Redactar `tmp/release_notes.txt`

Crea `tmp/release_notes.txt` siguiendo el estilo de entradas recientes en `CHANGELOG.txt` (véase v0.2.7 como referencia):

```markdown
### Added
- **Feature X.** Descripción orientada al usuario...

### Changed
- ...

### Fixed
- ...

### Removed
- ...

### Notes
- ...
```

Reglas:
- Bullets con el **qué** y el **por qué** visibles para quien actualiza la gema.
- Nombres de APIs, flags de config y comportamientos breaking en **bold** cuando importen.
- **No** pegues `git log --oneline` ni hashes de commit en el cuerpo principal.
- Opcional al final: una línea `Commits: abc1234, def5678` solo como referencia interna.

### 3. Ejecutar el bump

```bash
bundle exec rake release:bump[patch]
# o
bundle exec rake release:bump[minor,tmp/release_notes.txt]
```

La tarea rake comprueba: rama `main`, working tree limpio (excepto archivos de release), tests en verde. Luego: incremento de versión, `bundle install`, inserta el contenido de `tmp/release_notes.txt` en `CHANGELOG.txt`, commit `Release vX.Y.Z`, push, tag y push del tag. Borra `tmp/release_notes.txt` al terminar si era la ruta por defecto.

## Si falla por falta de notas

Si `tmp/release_notes.txt` no existe, la tarea aborta con instrucciones. Vuelve al paso 2.
