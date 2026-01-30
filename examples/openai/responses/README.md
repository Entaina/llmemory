# Ejemplo: Chat con OpenAI Responses API

Este ejemplo muestra cómo integrar **llmemory** con la nueva **Responses API** de OpenAI (`/v1/responses`) para un chat que:

1. **Recibe el mensaje del usuario**
2. **Recupera contexto** de la memoria a largo plazo de llmemory
3. **Llama a OpenAI Responses API** con gestión de estado automática
4. **Guarda en memoria** tanto el mensaje del usuario como la respuesta del asistente

## Responses API vs Chat Completions API

La Responses API es la interfaz más reciente de OpenAI, diseñada para:

- **Gestión de estado automática**: OpenAI mantiene el historial de conversación usando `previous_response_id`
- **Interfaz simplificada**: `input` + `instructions` en lugar de un array de `messages`
- **Herramientas integradas**: acceso a web search, file search, code interpreter, etc.
- **Multi-turn sin enviar todo el historial**: cada llamada solo envía el nuevo mensaje

## Estructura

- **`chat.rb`**: define la clase `Examples::OpenAI::Responses::Chat` con el método `chat(user_message)` y un script ejecutable al final.

## Flujo del método `chat`

```
Usuario escribe mensaje
        │
        ▼
┌───────────────────┐
│ add_message       │  Se guarda el mensaje del usuario en memoria (short-term)
│ (role: :user)     │
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ memory.retrieve   │  Se obtiene contexto de hechos relevantes
│ (query, max_tokens)│  de la memoria a largo plazo de llmemory
└─────────┬─────────┘
          │
          ▼
┌───────────────────────────────┐
│ call_openai_responses         │  POST /v1/responses con:
│                               │  - input: mensaje del usuario
│                               │  - instructions: system prompt + contexto
│                               │  - previous_response_id: para continuidad
└─────────┬─────────────────────┘
          │
          ▼
┌───────────────────┐
│ add_message       │  Se guarda la respuesta del asistente en memoria
│ (role: :assistant)│
└─────────┬─────────┘
          │
          ▼
   Devuelve la respuesta al usuario
```

## Cómo ejecutarlo

Desde la raíz del repositorio de la gema:

```bash
export OPENAI_API_KEY=sk-...
bundle exec ruby examples/openai/responses/chat.rb
```

Se abre un bucle en consola: escribe mensajes y `salir` para terminar.

## Uso en tu propio código

```ruby
require "llmemory"
require_relative "examples/openai/responses/chat"

chat = Examples::OpenAI::Responses::Chat.new(
  user_id: "user_123",
  session_id: "session_456"
)

respuesta = chat.chat("¿Qué sabes de mis preferencias?")
puts respuesta

# La conversación continúa automáticamente gracias a previous_response_id
respuesta2 = chat.chat("Cuéntame más sobre eso")
puts respuesta2

# Reiniciar el estado de conversación de OpenAI (pero llmemory mantiene el historial)
chat.reset_conversation!

# Opcional: consolidar la conversación en memoria a largo plazo
chat.consolidate!
```

## Parámetros clave de la Responses API

| Parámetro | Descripción |
|-----------|-------------|
| `input` | El mensaje del usuario (string o array de items) |
| `instructions` | System prompt con instrucciones y contexto |
| `previous_response_id` | ID de la respuesta anterior para multi-turn |
| `store` | Si OpenAI debe almacenar la respuesta (true para usar previous_response_id) |
| `model` | El modelo a usar (ej: `gpt-4o-mini`, `gpt-4o`) |

## Dependencias

- **llmemory**: memoria unificada (short-term + long-term).
- **faraday**: ya es dependencia de llmemory; el ejemplo lo usa para llamar a la API de OpenAI.
- **OPENAI_API_KEY**: variable de entorno con tu API key de OpenAI.

## Diferencias con Chat Completions

| Aspecto | Chat Completions | Responses API |
|---------|------------------|---------------|
| Endpoint | `/v1/chat/completions` | `/v1/responses` |
| Historial | Enviar todos los `messages` cada vez | `previous_response_id` |
| System prompt | Mensaje con `role: "system"` | Campo `instructions` |
| Entrada usuario | Último mensaje en `messages` | Campo `input` |

Si prefieres la API clásica de Chat Completions, consulta el ejemplo en `examples/openai/completions/`.
