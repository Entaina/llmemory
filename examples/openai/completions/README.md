# Ejemplo: Chat con OpenAI Chat Completions API

Este ejemplo muestra cómo integrar **llmemory** con la API de Chat Completions de OpenAI (`/v1/chat/completions`) para un chat que:

1. **Recibe el mensaje del usuario**
2. **Recupera contexto** de la memoria (conversación reciente + hechos a largo plazo)
3. **Llama a OpenAI** con ese contexto en el sistema y el historial en `messages`
4. **Guarda en memoria** tanto el mensaje del usuario como la respuesta del asistente

## Estructura

- **`chat.rb`**: define la clase `Examples::OpenAI::Completions::Chat` con el método `chat(user_message)` y un script ejecutable al final.

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
│ memory.retrieve   │  Se obtiene contexto: conversación reciente + hechos
│ (query, max_tokens)│  relevantes de memoria a largo plazo
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ build_messages    │  Se construye el array de mensajes para OpenAI:
│                   │  - system: instrucciones + contexto de memoria
│                   │  - history: mensajes ya guardados (user/assistant)
│                   │  - el nuevo mensaje del usuario ya está en history
└─────────┬─────────┘
          │
          ▼
┌───────────────────┐
│ call_openai       │  POST /v1/chat/completions con messages y model
└─────────┬─────────┘
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
bundle exec ruby examples/openai/completions/chat.rb
```

Se abre un bucle en consola: escribe mensajes y `salir` para terminar.

## Uso en tu propio código

```ruby
require "llmemory"
require_relative "examples/openai/completions/chat"

chat = Examples::OpenAI::Completions::Chat.new(
  user_id: "user_123",
  session_id: "session_456"
)

respuesta = chat.chat("¿Qué sabes de mis preferencias?")
puts respuesta

# Opcional: consolidar la conversación en memoria a largo plazo
chat.consolidate!
```

## Dependencias

- **llmemory**: memoria unificada (short-term + long-term).
- **faraday**: ya es dependencia de llmemory; el ejemplo lo usa para llamar a la API de OpenAI.
- **OPENAI_API_KEY**: variable de entorno con tu API key de OpenAI.

El ejemplo usa el modelo configurado en llmemory (por defecto `gpt-4o-mini` en el script). Puedes cambiarlo en `Llmemory.configure` o en la inicialización del ejemplo.

## Diferencias con la Responses API

Este ejemplo usa la API clásica de Chat Completions. Si prefieres usar la nueva Responses API de OpenAI (que incluye gestión de estado automática), consulta el ejemplo en `examples/openai/responses/`.
