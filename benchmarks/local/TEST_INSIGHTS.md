# TEST_INSIGHTS — Suite diagnóstica local (classic · zero_mem · hybrid)

Análisis de las dos pasadas de `suite-diag` con LM Studio y `qwen3-4b-instruct-2507`
(Q4_K_M, ctx 8192 → ampliado a ~22k en la segunda pasada), timeout 900 s, lector LLM local.

- Pasada 1: `results/suite_diag_20260917T142649Z.json` (15 celdas).
- Pasada 2 (relleno de huecos): `results/suite_diag_20260918T103107Z.json` (6 celdas).
- Celdas sin resultado: **MemoryAgentBench ×3** (ver §5.5).

El objetivo no es la puntuación absoluta (un 4B local no es comparable a los papers) sino
**dónde falla llmemory por capa** — ingest/extract, retrieve/ranking, temporal, ensamblado de contexto —
y qué cambios de producto se justifican con evidencia.

---

## 1. Resumen ejecutivo

1. **Solo 3 benchmarks producen señal válida**: LoCoMo, LongMemEval y Mem2Act. MemSyco da señal
   cualitativa (sin puntuar). GroupMemBench, LoCoMo‑Plus y MemoryArena son **artefactos del harness**
   (memoria vacía o esquema de datos mal mapeado): sus ceros no dicen nada de llmemory (§6).
2. **Trade‑off cobertura vs precisión** muy claro en LoCoMo:
   - `classic` acierta el contexto en **2/20** preguntas pero tiene el mejor F1 (**0.070**): los hechos
     destilados son precisos pero cubren poco.
   - `zero_mem` sube la cobertura a **7/20** con el peor F1 (**0.034**): la evidencia está, pero el turno
     bruto (con timestamp ISO) no se convierte en respuesta.
   - `hybrid` tiene la mejor cobertura (**9/20**) y F1 intermedio (**0.050**), y **pierde respuestas que
     classic sí daba** (q11 «Four years») → el reparto 50/50 del presupuesto de tokens recorta el bloque classic.
3. **La capa temporal es el fallo dominante** (LoCoMo cat. 2 F1 ≤ 0.055 en las tres variantes; LongMemEval
   temporal EM 0–0.1 con 9/10 hits): expresiones relativas sin resolver («Last year», «Last week», «This
   month», «yesterday» → fecha de sesión), timestamps ISO devueltos tal cual como respuesta, y evidencia
   sin fechas legibles para comparar/ordenar eventos.
4. **Localización Zero‑Mem**: el turno gold está en el contexto (35–45 % en LoCoMo, 90 % en LongMemEval)
   pero **nunca en el top‑5 en LoCoMo** (recall@5 = 0, recall@10 = 0.26, MRR 0.04–0.08). El ranking
   coloca el gold en posiciones 7–14; con presupuesto de 2000 tokens eso equivale a recortarlo.
5. **Robustez a entradas largas**: MemoryAgentBench rompe las tres variantes por diseño del producto,
   no del modelo: `consolidate!` intenta un único prompt de 211k tokens y `Trace.normalize_content!`
   lanza excepción con > 32k caracteres.
6. **Lo que funciona**: Mem2Act resuelve referencias implícitas desde memoria («that tech stock we always
   track» → `AAPL`) con **tool accuracy 1.0 en las tres variantes**; `retrieve` es 100 % libre de LLM
   (`invoke_calls_delta` = 0 en todas las filas); latencias de retrieve 1–140 ms.

---

## 2. Matriz de resultados

Métrica principal = capa retrieve (`hit` = texto gold o turno gold presente en el contexto; `R@5`/`MRR`
= localización del turno gold en el ranking Zero‑Mem). Secundaria = capa respuesta.

> **Nota**: `bench_scores.retrieval_hit.mean` sale siempre 1.0 en los JSON por un bug del agregador
> (`filter_map` descarta los `false`). Las tasas de esta tabla están recontadas fila a fila.

| Bench (n) | Variante | hit | R@5 | R@10 | MRR | Métrica respuesta | «I don't know» | lat. retrieve |
|---|---|---|---|---|---|---|---|---|
| LoCoMo (20, conv‑26, 19 sesiones) | classic | 2/20 | n/a | n/a | n/a | F1 **0.070** (c1 .106 · c2 .055 · c3 0) | 11/20 | 19 ms |
| | zero_mem | 7/20 | 0.00 | 0.26 | 0.083 | F1 0.034 (c1 .054 · c2 .025 · c3 0) | 10/20 | 58 ms |
| | hybrid | **9/20** | 0.00 | 0.26 | 0.040 | F1 0.050 (c1 .084 · c2 .033 · c3 0) | 5/20 | 70 ms |
| LongMemEval temporal (10) | classic | 2/10 | n/a | n/a | n/a | EM 0.0 | 10/10 | 82 ms |
| | zero_mem | **9/10** | 0.40 | **0.85** | 0.375 | EM 0.0 (1 correcta no reconocida por substring) | 6/10 | 64 ms |
| | hybrid | **9/10** | **0.45** | 0.45 | 0.340 | EM **0.1** | 8/10 | 137 ms |
| Mem2Act (20) | classic | n/a | n/a | n/a | n/a | tool 1.0 · param‑F1 **0.817** | 0 | 28 ms |
| | zero_mem | n/a | n/a | n/a | n/a | tool 1.0 · param‑F1 0.790 | 0 | 1 ms |
| | hybrid | n/a | n/a | n/a | n/a | tool 1.0 · param‑F1 0.765 | 0 | 26 ms |
| MemSyco pers. (20) | classic / zero_mem / hybrid | — | — | — | — | judge **sin puntuar** (gold no mapeado) | 1/20 c/u | 128 / 14 / 138 ms |
| GroupMemBench (10) | ×3 | 0 | 0 | 0 | 0 | EM 0 — **memoria vacía (bug adapter)** | 10/10 (zm 9/10) | — |
| LoCoMo‑Plus (20) | ×3 | 0 | (zm 1.0 artificial) | | | judge sin puntuar — **0 turnos ingeridos (bug adapter)** | 20/20 | — |
| MemoryArena (5) | ×3 | 0 | 0 | 0 | 0 | substring_em sobre gold JSON — **métrica no aplicable** | — | 400 ms |
| MemoryAgentBench (20) | ×3 | — | — | — | — | **fallo**: 211k tokens en un consolidate / trace > 32k chars | — | — |

Coste de pared (pasada 2, 4B local): LoCoMo classic ≈ 10 min (19 consolidaciones por sesión), hybrid ≈ 13 min,
LongMemEval classic/hybrid ≈ 7 min cada uno, MemSyco zero_mem ≈ 1 min, hybrid ≈ 5 min.

---

## 3. LoCoMo — análisis pregunta a pregunta (conv‑26)

Categorías LoCoMo: 1 = single‑hop, 2 = temporal, 3 = open‑domain/adversarial.

| q | cat | gold | classic | zero_mem | hybrid | Diagnóstico |
|---|---|---|---|---|---|---|
| q1 | 2 | 7 May 2023 | IDK | IDK | «2023‑05‑08» | Hybrid devuelve la **fecha de sesión**; el turno dice «yesterday». Relativo sin resolver. |
| q2 | 2 | 2022 | «Last year.» | IDK | «2023» | Classic almacenó el hecho **sin anclar** al año de la sesión; hybrid copia el año de sesión. |
| q3 | 3 | Psychology, counseling | IDK | Mental health and counseling | ídem | zero_mem/hybrid recuperan; classic no. |
| q4 | 1 | Adoption agencies | **hit** → .44 | IDK | **hit** → IDK | Hybrid tiene la evidencia y **no la convierte**: ruido/orden del contexto fusionado. |
| q5 | 1 | Transgender woman | .40 | .02 (verboso) | .40 | Evidencia bruta → respuesta larga y difusa. |
| q6 | 2 | Sunday before 25 May | «Last Saturday, May 25» .55 | «Last Saturday, 2023‑05‑25» .36 | **«2023‑05‑25T11:14:00Z»** .18 | El timestamp ISO del trace **se filtra como respuesta**. |
| q7 | 2 | June 2023 | IDK | IDK | IDK | Ninguna variante recupera el plan futuro. |
| q8 | 1 | Single | **hit** → IDK | IDK | **hit** → «single parent» .22 | Classic tiene el texto y abstiene. |
| q9 | 2 | week before 9 June | «June 9th» .13 | IDK | «Three years ago.» | Fecha de sesión (classic) / relativo mal resuelto (hybrid). |
| q10 | 2 | week before 9 June | IDK | **hit** → «June 9th, 2023» .44 | **hit** → «Last week.» .25 | Hybrid deja el relativo tal cual. |
| q11 | 2 | 4 years | **«Four years.» .50** | IDK | **IDK** | **Regresión hybrid**: el hecho classic cabía en 2000 tokens pero no en 1000. |
| q12 | 1 | Sweden | IDK | **hit** → «her home country» | **hit** → ídem | El turno gold no nombra el país; hace falta **agregar hechos de varias sesiones**. |
| q13 | 2 | 10 years ago | IDK | IDK | IDK | Requiere aritmética (edad + «18th birthday»). |
| q14 | 1 | counseling / mental health trans | .27 | .32 | .30 | OK en las tres. |
| q15 | 3 | Likely no | IDK | IDK | IDK | Contrafactual; límite del lector. |
| q16 | 1 | pottery, camping, painting, swimming | IDK | «pottery» .14 | «pottery, violin, painting» .19 | **Respuesta multivalor parcial**: solo se recupera un hecho. |
| q17 | 2 | 2 July 2023 | IDK | «2023‑07‑03» .14 | «July 3, 2023» .67 | Off‑by‑one: fecha de sesión vs «yesterday». |
| q18 | 2 | July 2023 | IDK | **hit** → «This month.» | **hit** → «This month.» | Relativo sin resolver con la evidencia delante. |
| q19 | 1 | beach, mountains, forest | «beach» .17 | IDK | «beach» .22 | Multivalor parcial. |
| q20 | 1 | dinosaurs, nature | «museums… dinosaur exhibit… pottery» 0 | «clay…» 0 | «pottery workshops…» 0 | Recupera el evento, no el atributo; verbosidad penaliza. |

**Patrones**

- **Temporal (cat. 2, 10 preguntas)**: 0 respuestas correctas en las tres variantes. Tres modos de fallo
  repetidos: (a) relativo sin resolver («Last year», «Last week», «This month», «Three years ago»); (b)
  fecha de sesión en lugar de fecha del evento (q1, q9, q17: «yesterday»/«last week» ignorados); (c)
  timestamp ISO devuelto como respuesta (q6 hybrid).
- **Cobertura ≠ conversión**: de los 9 hits de hybrid solo 3 acaban en F1 > 0.2 (q8, q10, q17); de los 7 de
  zero_mem, 2 (q6, q10).
- **Multivalor**: q16/q19/q20 (listas acumuladas a lo largo de sesiones) se responden con un único valor.
  La memoria no agrega hechos del mismo sujeto/predicado.
- **Localización**: zero_mem/hybrid MRR ≈ 0.07–0.14 en las filas con hit → el gold aparece en rango 7–14.

---

## 4. LongMemEval (temporal‑reasoning, 10 preguntas, 1 sesión gold ×2 por pregunta)

- **classic**: 2/10 hits, 10/10 «I don't know». Consolidación única (`consolidate_after_hydrate`) sobre
  ~40–50 sesiones con un extractor 4B: los hechos pierden fechas y especificidad.
- **zero_mem**: 9/10 hits, recall@10 0.85, MRR 0.375. Respuestas: 1 correcta («GPS system», puntuada 0 por
  `substring_em`), 2 **erróneas de orden** («The car.» vs bike; «marigolds» vs tomatoes), 1 explícita
  «the context does not provide specific dates», 6 IDK.
- **hybrid**: 9/10 hits, recall@5 0.45 (mejor), 1 correcta (Samsung Galaxy S22, EM 0.1), 1 «does not specify
  the exact dates», 8 IDK.

**Lectura**: la recuperación funciona (≥ 90 % de las preguntas tienen la evidencia), la **capa temporal no**.
El bloque `=== ZERO-MEM EVIDENCE ===` imprime `[trace_id] 2023-02-13T00:00:00Z session role: contenido`;
para «which first / how many days between» el lector necesita fechas legibles, ordenadas y, idealmente,
la diferencia precalculada. Las preguntas «how many days» son 5/10 y fallan las 5 en todas las variantes.

---

## 5. Resto de benchmarks

### 5.1 Mem2Act (válido) — resolución de referencias implícitas para tool‑calling

- **tool_accuracy 1.0** en las tres variantes: la memoria resuelve «that tech stock we always track» → `AAPL`,
  «the electric‑car company» → `TSLA`, «my sign» → `aquarius`, «that contact number» → `+14155552671`,
  «that mutual fund» → `VFIAX`, `shortcode` de Instagram, etc.
- **param‑F1**: classic 0.817 > zero_mem 0.790 > hybrid 0.765. Las pérdidas de zero_mem/hybrid son **ruido de
  evidencia bruta**:
  - `"apikey":"dev-key-12345"` aparece en `Stock Quote Price` (hybrid/zero_mem): un turno irrelevante se
    coló en el contexto.
  - `season: 2026` / `2023` en vez de `2024`; `campaignId: "EcoCharge-2026"`: el lector toma el
    **`occurred_at` de ingesta (2026)** como fecha del evento. Los traces sin fecha real muestran el
    momento de grabación como si fuera el del hecho.
  - Formato de slots (`USD EUR` / `USDEUR` vs `USD-EUR`; `golden_rush` vs `Golden_Rush`): el hecho destilado
    (classic) conserva mejor la forma literal que la reformulación desde turno bruto.
- Sobre‑especificación (`fresh:1`, `pageIndex`, `region`, `timestamp`) es del esquema/lector, no de memoria.

### 5.2 MemSyco `personalized_memory_use` (señal cualitativa)

Sin puntuar porque el adapter busca `reference`/`answer` y el dataset guarda
`evaluation.reference_answer`, y los ítems de memoria están en `memory.items` (no se ingieren; solo el
`dialogue`). Aun así, las predicciones son **coherentes con la rúbrica** en la mayoría de casos (p. ej.
«User dislikes cooking for a date» → «A casual dining option» / gold «Order takeout…»; «smaller, structured
jam session»; «retro movie marathon»). Las tres variantes dan respuestas casi idénticas en la gran mayoría
de filas → la personalización básica sale del diálogo, no de los ítems. Los subtests `memory_evidence_conflict`,
`contextual_scope_control` y `valid_memory_selection` son los relevantes para llmemory (sicofancia de
memoria: cuándo **no** aplicar un recuerdo) y aún no se han ejecutado.

### 5.3 GroupMemBench — resultado inválido

El JSON de canal (`synthetic_domain_channels_rolevariants_Finance.json`) está indexado por proyecto
(`"Regulatory Compliance Program": [{msg_node, content, …}]`, 5292 mensajes), no por `messages`. El adapter
ingiere **0 turnos** → memoria vacía → 10/10 IDK. Nada que concluir sobre multi‑hop en canales grupales.

### 5.4 LoCoMo‑Plus — resultado inválido

El adapter globbea `**/*.json` y toma `locomo10.json` (LoCoMo original) con un esquema que no reconoce
(`conversation.session_N`) → **0 turnos**. El fichero real `locomo_plus.json` tiene otro esquema
(`cue_dialogue` / `trigger_query` / `relation_type` / `time_gap`) y no está adaptado. El recall@5 = 1.0 de
zero_mem es artificial (§6.2).

### 5.5 MemoryAgentBench — fallo en las tres variantes (insight de producto)

- classic: `consolidate_after_hydrate` construye **un** prompt de 211 787 tokens → overflow con cualquier ctx.
- zero_mem/hybrid: `Llmemory::ZeroMem::Trace.normalize_content!` lanza `ValidationError` con > 32 000 chars.
Ambos son límites de llmemory, no del modelo: consolidación no troceada y `record_trace` que rechaza en vez
de partir.

### 5.6 MemoryArena — métrica no aplicable

Tareas agénticas multi‑paso de webshop con gold `{target_asin, attributes}` evaluadas con `substring_em`
sobre texto libre. zero_mem incluso emite `Search[...]` siguiendo el formato del prompt. Necesita un
scorer por ASIN/atributos y un bucle de acción; fuera del alcance de esta suite.

---

## 6. Deuda del harness (corregir antes de la siguiente ronda)

1. **`Report.retrieval_hit_aggregate`**: `rows.filter_map { |r| r[:retrieval_hit] }` descarta `false` →
   `mean` siempre 1.0 y `count` = nº de aciertos. Usar `rows.map { … }.compact` y contar `true`.
2. **`Harness#rank_fixture_turn_ids`** añade los `gold_trace_ids` al final del ranking → si la evidencia
   tiene < 5 ítems (o está vacía) recall@5 = 1.0 y MRR = 1.0 (LoCoMo‑Plus zero_mem). No rellenar con gold.
3. **Localización en classic** siempre 0.0 porque `rank_trace_ids_in_context` exige el texto literal del
   turno y classic devuelve hechos. Debe ser `nil`/no aplicable, no 0, para no arrastrar medias.
4. **Adapter GroupMemBench**: mapear la estructura por proyecto (`msg_node`, `content`, autor) y los
   `evidence_turn_ids`.
5. **Adapter LoCoMo‑Plus**: leer `locomo_plus.json` (cue → trigger con `time_gap`) y excluir `locomo10.json`.
6. **Adapter MemSyco**: gold en `evaluation.reference_answer`, rúbrica en `evaluation.rubric`, ingerir
   `memory.items` como hechos (o como traces), pasar `memory.policy` al judge.
7. **LongMemEval**: `substring_em` penaliza respuestas correctas parafraseadas («GPS system…»); ejecutar
   con `--use-judge` o normalizar.
8. **MemoryAgentBench**: trocear el documento en sesiones/turnos ≤ `max_message_chars` en el adapter
   (además del fix de producto de §7.6) para poder medir.
9. **MemoryArena**: scorer por `target_asin`/atributos o excluir de `suite-diag`.

---

## 7. Insights de producto priorizados

Ordenados por impacto observado × amplitud (afecta a varias variantes/benches). Cada uno indica capa,
evidencia, propuesta y cómo se mediría.

### 7.1 Anclaje temporal en consolidación (extract) — **P0**

- **Evidencia**: LoCoMo cat. 2 F1 ≤ 0.055 en las tres variantes; classic almacena «Last year» (q2) y
  responde «June 9th» para «la semana anterior al 9 de junio» (q9). `FileBased::Memory#memorize` antepone
  `# Conversation anchor time` al texto, pero `FactExtractor#extract_items` **no pide** resolver expresiones
  relativas ni emitir fecha de evento.
- **Propuesta**: el extractor recibe `reference_time` explícito y devuelve por ítem `event_date`
  (absoluta, `nil` si no aplica) y `content` con el relativo ya resuelto («went to LGBTQ support group on
  2023‑05‑07»). Guardar `event_date` en el ítem (hoy solo hay `occurred_at` = hora de sesión) y exponerlo en
  `ContextAssembler`. `TemporalRanker` debe usar `event_date` cuando exista.
- **Métrica**: LoCoMo cat. 2 F1 classic/hybrid; preguntas q1, q2, q9, q10, q17, q18 pasan de relativo a fecha.

### 7.2 Evidencia Zero‑Mem legible y ordenada para consultas temporales (retrieve/context) — **P0**

- **Evidencia**: q6 hybrid responde literalmente `2023‑05‑25T11:14:00Z`; LongMemEval zero_mem/hybrid con
  9/10 hits producen 0–1 aciertos y el lector dice «context does not provide specific dates»; 2 errores de
  orden («The car.», «marigolds»).
- **Propuesta** (`EvidenceSet#to_context`): fecha legible (`Mon 8 May 2023`) además/en lugar del ISO; para
  intención temporal (detectable por léxico: when/first/before/how many days…) ordenar cronológicamente y
  añadir un bloque «Timeline» con `fecha — resumen de turno` de los traces recuperados. Distinguir
  `occurred_at` real de `recorded_at`: si el trace no traía fecha de evento, **no** mostrar la hora de ingesta
  como si lo fuera (Mem2Act `season: 2026`, `EcoCharge-2026`).
- **Métrica**: LongMemEval temporal EM/judge; LoCoMo cat. 2 en zero_mem/hybrid; desaparición de ISO en
  predicciones.

### 7.3 Ranking/localización Zero‑Mem en diálogos largos (retrieve) — **P1**

- **Evidencia**: LoCoMo zero_mem/hybrid recall@5 = 0.0, recall@10 = 0.26, MRR 0.04–0.08 con 35–45 % de
  hits → el gold entra en el contexto pero en posiciones 7–14. LongMemEval MRR 0.375, recall@5 0.40.
- **Propuesta**: en `EvidenceCalibrator`/fusión, (a) boost por coincidencia de entidades/sujeto de la
  pregunta con el hablante del turno, (b) penalizar turnos genéricos (saludos, reacciones) vía IDF de la
  consulta, (c) para preguntas temporales priorizar turnos con marcadores de tiempo. Revisar
  `fusion_weights` por defecto con `diag_locomo.rb` como test de regresión (gold `D1:3` en top‑5).
- **Métrica**: recall@5 y MRR en LoCoMo/LongMemEval zero_mem; `retrieval_hit` estable o mejor.

### 7.4 Presupuesto y fusión en hybrid (context) — **Hecho (fused, 2026-09-21)**

- **Implementado**: `Retrieval::HybridFusion` + `Memory#retrieve_fused` — un solo ranking RRF (hechos +
  traces), priors por `workload_class`, corroboración vía provenance `{type: trace}`, dedupe de traces
  redundantes cuando un hecho corroborado cubre el slot (salvo consultas temporales), exclusión de
  `kind: :resource` si hay trace store, contexto único `=== MEMORY ===`. `hybrid_classic_token_ratio` =
  techo de tokens para hechos/resúmenes dentro del presupuesto total. Localización en bench vía
  `HybridResult#ranked_trace_ids`.
- **Métrica pendiente**: hybrid F1 ≥ classic y hits/recall@5 ≥ zero_mem en LoCoMo; Mem2Act param‑F1 hybrid ≥
  classic (re-ejecutar suite).

### 7.5 Agregación de hechos multivalor por sujeto/predicado (extract/retrieve) — **P1**

- **Evidencia**: q16 (4 actividades → 1), q19 (3 lugares → 1), q20 (gustos → evento), q12 («home country»
  sin país: el dato está en otra sesión). LongMemEval classic 2/10 hits tras una consolidación única.
- **Propuesta**: en file_based, al recuperar, agrupar ítems por sujeto+predicado normalizados y renderizar
  como lista («Melanie — activities: pottery, camping, painting, swimming») en vez de N hechos sueltos que
  compiten por el top‑k; en graph_based ya existe la estructura, exponer «todos los objetos de un predicado
  no exclusivo» en `ContextAssembler`. Consolidación en **lotes por sesión/turnos** también para
  `consolidate_after_hydrate` (hoy un único prompt).
- **Métrica**: LoCoMo cat. 1 F1; LongMemEval classic hits.

### 7.6 Robustez a entradas largas (ingest) — **P1**

- **Evidencia**: MemoryAgentBench falla en las tres variantes (211k tokens en un `consolidate!`; trace de
  > 32k chars rechazado).
- **Propuesta**: `consolidate!` trocea el checkpoint por presupuesto de tokens (configurable, por defecto
  ≤ 60 % del contexto del modelo) y consolida secuencialmente; `record_trace` parte contenidos largos en
  traces encadenados (`part_index`, misma `idempotency_key` base) en lugar de lanzar `ValidationError`.
- **Métrica**: MemoryAgentBench ejecuta hasta el final; nº de llamadas LLM por consolidación acotado.

### 7.7 Precisión de la evidencia para slot‑filling (retrieve) — **P2**

- **Evidencia**: Mem2Act param‑F1 classic 0.817 > zero_mem 0.790 > hybrid 0.765; `apikey` filtrado; casing
  y separadores alterados al reformular desde turno bruto.
- **Propuesta**: evidencia a nivel de frase (sentence‑level snippets) en vez de turno completo cuando la
  consulta pide un valor concreto; en hybrid preferir hechos destilados para entidades/slots.
- **Métrica**: Mem2Act param‑F1 zero_mem/hybrid ≥ classic.

### 7.8 Señales de confianza en el contexto (context) — **P2 / observación**

- **Evidencia**: muchos IDK con hit = true (classic q8; hybrid q4; LongMemEval hybrid 8/9 hits → IDK).
  Parte es el lector 4B con instrucción de abstenerse, pero el contexto no marca qué evidencia es relevante.
- **Propuesta**: `ContextAssembler`/`EvidenceSet#to_context` exponen `score`/`confidence` por ítem (ya
  existen en `Evidence`) y un encabezado «Most relevant: …». No es tuning del lector: es información que
  la memoria ya tiene y no muestra.

---

## 8. Siguiente ronda (orden sugerido)

1. Corregir §6.1–6.3 (agregador, ranking con gold, localización classic = n/a) → las métricas actuales
   quedan comparables.
2. Corregir adapters GroupMemBench, MemSyco (con `memory.items` + judge), LoCoMo‑Plus; re‑ejecutar
   `suite-diag` para tener línea base real de las 8 tablas.
3. Implementar 7.1 + 7.2 (temporal) y medir LoCoMo cat. 2 y LongMemEval temporal en las tres variantes.
4. Implementar 7.4 (hybrid adaptativo) y comprobar que hybrid ≥ classic en F1 sin perder cobertura.
5. 7.3 (ranking) con `diag_locomo.rb` como regresión; después 7.5, 7.6, 7.7.
6. Añadir MemSyco `memory_evidence_conflict` / `contextual_scope_control` a `suite-diag`: son los que miden
   si la memoria sabe **no** aplicarse (ConflictResolver, alcance), un diferenciador de producto.

Ficheros de referencia: `results/suite_diag_20260917T142649Z.json`, `results/suite_diag_20260918T103107Z.json`,
`results/<bench>__<variant>__<ts>.json` (filas por pregunta), logs `results/suite_diag_run.log`,
`results/suite_diag_rerun_20260918T103107Z.log`.

---

## 9. Implementación (plan TEST_INSIGHTS, 2026-09-21)

Cambios en producto y harness alineados con §6–§7 (ver `CHANGELOG.txt` [Unreleased]):

| Área | Estado | Verificación |
|------|--------|--------------|
| §6 métricas harness | Hecho | `spec/benchmarks/local/report_spec.rb`, `zm0_baseline_spec` |
| §6 adapters | Hecho | `spec/benchmarks/local/adapters_spec.rb` |
| 7.1 temporal extract | Hecho | `event_date` / `occurred_at`, migración AR template |
| 7.2 evidencia legible | Hecho | `spec/zero_mem/evidence_set_context_spec.rb` |
| 7.3 ranking | Hecho (v1) | boosts en `ZeroMem::Engine#boost_fusion_rows`, `diag_locomo_rank_spec` |
| 7.4 hybrid fused | Hecho | `spec/retrieval/hybrid_fusion_spec.rb`, `spec/zero_mem/hybrid_retrieve_spec.rb` |
| 7.5 multivalor | Hecho (agrupación retrieve) | file `grouped_item_candidates`, graph `format_as_context` |
| 7.6 troceado consolidate/trace | Hecho | `consolidation_chunk_tokens`, `long_trace_strategy` |
| 7.7–7.8 snippets + confianza | Hecho | `EvidenceSet#to_context`, `ContextAssembler` «Most relevant» |

**Pendiente de medición numérica:** nueva pasada `suite-diag` con LM Studio (ctx ≥ 22k) para comparar
antes/después en LoCoMo cat. 2, LongMemEval temporal y celdas MemoryAgentBench.

---

## 10. Correcciones post-benchmark (2026-09-21, pasada `084002Z`)

Tras analizar filas de LoCoMo/LongMemEval y `diag_locomo.rb`:

| Fix | Efecto esperado |
|-----|-----------------|
| `freshness_requirement` solo en `:current_state`; calibrator ordena por score de fusión | Zero-Mem deja de priorizar turnos recientes en preguntas «when did…» |
| `TemporalRanker` sin decaimiento vs `Time.now` en consultas temporales; `now` = max del corpus | Classic deja de empujar sesión D18 en preguntas sobre mayo |
| Ancla temporal solo en prompt de extracción (no en `save_resource`) | Contexto sin cabecera `# Conversation anchor time` |
| `RelativeDateResolver` post-`FactExtractor` | Menos hechos «Last week» / «This month» sin fecha absoluta |
| BM25 + stopwords en `search_candidates` | Mejor hit en preguntas multi-token (actividades, etc.) |
| Vecinos de jerarquía como closure, no seeds | Menos relleno conversacional en top de evidencia |

**Probe rápido (`diag_locomo.rb`, stub reader):** hybrid pasa a incluir gold `D1:3` en top‑5 y el turno LGBTQ en contexto; zero_mem en diálogo completo sigue siendo difícil (recall@5 en suite aún 0 en zm puro).

---

## 11. Fusión hybrid (2026-09-21, post‑implementación)

- **Producto:** `memory_mode` por defecto `:hybrid`; `Memory#retrieve_fused` → `HybridFusion` (RRF hechos+traces, provenance trace, techo `hybrid_classic_token_ratio`, contexto `=== MEMORY ===`).
- **Bench:** hybrid usa `ranked_trace_ids` para recall@5/MRR (comparable a zero_mem).
- **Medición:** pasada LoCoMo `--limit 20` ×3 variantes en curso / resultados en
  `benchmarks/local/results/locomo__<variant>__*.json`. Comando:

  `./benchmarks/local/run_benchmarks.sh run locomo --limit 20 --variant classic|zero_mem_full|hybrid`

  Criterio de éxito (§7.4): hybrid F1 ≥ classic, hits/recall@5 ≥ zero_mem; Mem2Act param‑F1 hybrid ≥ classic.

---

## 13. Plan benchmarks 2026-09-23 (implementado)

### Harness / adapters

| Cambio | Estado |
|--------|--------|
| MemoryAgentBench: `questions[]` + `answers[][]` + `gold_answers` | Hecho |
| GroupMemBench: sesión por proyecto, turnos por keywords de la pregunta | Hecho |
| MemSyco: `MEMSYCO_TASK=all` en suite-diag / step | Hecho |
| MemoryArena: gold JSON → `ArenaMatch` | Hecho |
| `retrieval_hit` n/a (MemSyco); `evidence_in_range` n/a sin gold traces | Hecho |
| Comandos `baseline`, `baseline-control-7b` | Hecho |
| Métricas fila: `extraction_yield`; informe: `hits_converted` | Hecho |

### Producto (`lib/llmemory`)

| Cambio | Estado |
|--------|--------|
| FactExtractor: troceado, JSON truncado, reintento structured | Hecho |
| Ranking: penalizar saludos, boost metadata `project` | Hecho |
| Hybrid/Zero-Mem contexto: hechos primero, confianza normalizada, snippets | Hecho |

### Línea base y objetivos (4B, tras `./benchmarks/local/run_benchmarks.sh check`)

Ejecutar (LM Studio con `qwen3-4b-instruct-2507`):

```bash
./benchmarks/local/run_benchmarks.sh baseline
LLMEMORY_LLM_MODEL_CONTROL=qwen2.5-7b-instruct ./benchmarks/local/run_benchmarks.sh baseline-control-7b
SUITE_DIAG_VARIANTS=classic zero_mem_full hybrid ./benchmarks/local/run_benchmarks.sh suite-diag
```

Objetivos orientativos **hybrid @ 4B** (vs. step-cycle 22-09):

| Bench | Métrica | Baseline step (ref.) | Objetivo |
|-------|---------|----------------------|----------|
| LoCoMo | F1 cat. 2 | ~0.5 (n=2) | ≥0.12 en 24Q estratificadas; recall@5 ≥0.3 |
| LoCoMo | F1 global | 0.25 (n=4) | ≥1.5× baseline estratificado |
| LongMemEval | llm_judge | 0.33 (n=3) | ≥0.5 (15Q) |
| Mem2Act | param_f1 hybrid | 0.86 (n=5) | ≥ classic |
| MemoryAgentBench | substring_em | inválido (gold=`answer`) | EM >0 con adapter corregido |
| GroupMemBench | substring_em | 0 (canal equivocado) | EM >0 con multi-proyecto |
| MemSyco | memsyco_judge | 0.6 (n=5, 1 task) | ≥0.5 en 10Q × tasks `all` |

Clasificación de fallos: comparar `baseline-control-7b` con hybrid 4B; si el 7B convierte hits que el 4B no, capa **lector/modelo**, no memoria.

**Nota harness (H1):** `locomo_20260921T143202Z.json` se etiquetó `variant: classic` pero corría con
`memory_mode` por defecto `:hybrid` (bug en `build_memory` sin `memory_mode: :classic`). Tratar esa fila
como **hybrid fusionado**, no como classic. Corregido en harness + aserción de modo por variante.

---

## 12. Línea base reproducible (harness fiable, 2026-09-21)

**Flujo recomendado: pasos pequeños (hybrid), no suite completa de golpe.**

```bash
./benchmarks/local/run_benchmarks.sh step-plan   # orden sugerido
./benchmarks/local/run_benchmarks.sh smoke
./benchmarks/local/run_benchmarks.sh step locomo # 1 conv × 4 Q estratificadas (~minutos, no horas)
# leer misses / bajo F1:
# bundle exec ruby benchmarks/local/scripts/summarize_run.rb benchmarks/local/results/locomo__hybrid__step_*.json
# bundle exec ruby benchmarks/local/scripts/explain_row.rb PATH q_id
# → corregir lib/ o harness → repetir step hasta estable → step longmemeval, mem2act, …

./benchmarks/local/run_benchmarks.sh step-cycle
# → smoke + steps 2–8 + benchmarks/local/results/step_cycle_summary_*.json
```

Filas incluyen `evidence_in_range` / `evidence_max_session` (LoCoMo step con `STEP_MAX_SESSIONS`); misses con evidencia fuera de rango se marcan en `summarize_run.rb`.
GroupMemBench step: `GROUPMEMBENCH_MAX_TURNS=120` (últimos turnos del canal) y timeout 2400s.

Variables útiles: `STEP_CONVERSATIONS=1` `STEP_PER_CONV=4` `STEP_LIMIT=3` `STEP_BENCH_TIMEOUT=900`.
**Por qué “consolidate” tarda horas:** no suele ser lógica Ruby — es **`POST /v1/chat/completions` sin respuesta** (LM Studio colgado, modelo no cargado, o petición anterior bloqueando). Con `LLMEMORY_LLM_TIMEOUT=900` y `LLMEMORY_LLM_HTTP_RETRIES=4` **una sola extracción puede esperar ~75 min** antes de fallar.

Verificación (obligatoria antes del bench):

```bash
./benchmarks/local/run_benchmarks.sh check   # ahora incluye ping chat "Reply OK"
```

Trazas: `results/step_trace_*.log` — si ves `extract invoke start` sin `invoke done`, el servidor LLM no contesta. Ajustes recomendados en `benchmarks.env`: `LLMEMORY_LLM_TIMEOUT=180`, `LLMEMORY_LLM_HTTP_RETRIES=1`, `LLMEMORY_LLM_MAX_OUTPUT_TOKENS=768`.

Probe una sesión: `bundle exec ruby benchmarks/local/scripts/probe_consolidate.rb /path/to/session.txt`

LoCoMo **step** usa por defecto `STEP_MAX_SESSIONS=4` (solo 4× `consolidate!`, no las 19 sesiones completas) y preguntas con evidencia en D1–D4; timeout step LoCoMo 1200s. Si aún expira, sube `STEP_BENCH_TIMEOUT` o baja `STEP_MAX_SESSIONS=2`.

Cuando todos los **step** pasen bien, escalar (p. ej. LoCoMo 3×8) o `SUITE_DIAG_VARIANTS=hybrid ./benchmarks/local/run_benchmarks.sh suite-diag`.

Suite completa (referencia):

```bash
export LLMEMORY_BENCH_CACHE=1
export LLMEMORY_LLM_TEMPERATURE=0
export LLMEMORY_BENCH_SEED=suite-diag
SUITE_DIAG_VARIANTS=hybrid ./benchmarks/local/run_benchmarks.sh suite-diag
```

- **LoCoMo:** `--stratify category --conversations 3 --per-conversation 8` (24 preguntas balanceadas).
- **LongMemEval:** `--stratify question_type --limit 10` con `--use-judge` por defecto (`SUITE_DIAG_JUDGE=1`).
- **Mem2Act / resto:** límites smoke + timeout `SUITE_DIAG_BENCH_TIMEOUT` (default 3600s).
- **Comparación:** `benchmarks/local/results/suite_diag_<timestamp>.json` (deltas hybrid−classic/zero_mem, F1 por categoría, hits convertidos, regresiones).
- **Depuración fila:** `bundle exec ruby benchmarks/local/scripts/explain_row.rb results/locomo__hybrid__*.json q12`.

Rerun manual LoCoMo ×3 variantes (misma semilla):

```bash
for v in classic zero_mem_full hybrid; do
  LLMEMORY_BENCH_OUT=benchmarks/local/results/locomo__${v}__baseline.json \
  LLMEMORY_BENCH_CACHE=1 \
  bundle exec ruby benchmarks/local/runners/run.rb --bench locomo --variant "$v" \
    --stratify category --conversations 3 --per-conversation 8 --seed baseline --reader llm
done
```
