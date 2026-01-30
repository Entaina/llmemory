# frozen_string_literal: true

# Ejemplo de chat con OpenAI usando llmemory para contexto y persistencia.
# Ejecutar desde la raíz de la gema: bundle exec ruby examples/openai/responses/chat.rb
# Requiere OPENAI_API_KEY en el entorno.

require "bundler/setup"
require "llmemory"
require "faraday"
require "json"

module Examples
  module OpenAI
    module Responses
      class Chat
        def initialize(user_id: "default_user", session_id: "default_session")
          Llmemory.configure do |config|
            config.llm_provider = :openai
            config.llm_api_key = ENV["OPENAI_API_KEY"]
            config.llm_model = "gpt-4o-mini"
          end
          @memory = Llmemory::Memory.new(user_id: user_id, session_id: session_id)
          @model = Llmemory.configuration.llm_model
          @api_key = Llmemory.configuration.llm_api_key
        end

        # Recibe el mensaje del usuario, llama a OpenAI con el contexto de la memoria,
        # guarda mensaje y respuesta en memoria y devuelve la respuesta del asistente.
        def chat(user_message)
          @memory.add_message(role: :user, content: user_message)

          context = @memory.retrieve(user_message, max_tokens: 2000)
          messages = build_messages(context, user_message)
          response_content = call_openai(messages)

          @memory.add_message(role: :assistant, content: response_content)
          response_content
        end

        # Opcional: consolidar la conversación actual en memoria a largo plazo.
        def consolidate!
          @memory.consolidate!
        end

        def messages
          @memory.messages
        end

        private

        def build_messages(context, new_user_message)
          system_content = if context.to_s.strip.empty?
            "Eres un asistente útil. Mantén respuestas concisas cuando sea posible."
          else
            <<~TEXT
              Eres un asistente útil. Usa la siguiente información recordada del usuario para personalizar tu respuesta.
              Mantén respuestas concisas cuando sea posible.

              #{context}
            TEXT
          end

          msgs = [{ role: "system", content: system_content.strip }]

          history = @memory.messages
          history.each do |m|
            role = (m[:role] || m["role"]).to_s
            content = (m[:content] || m["content"]).to_s
            msgs << { role: role, content: content }
          end

          msgs
        end

        def call_openai(messages)
          conn = Faraday.new(url: "https://api.openai.com/v1") do |f|
            f.request :json
            f.response :json
            f.adapter Faraday.default_adapter
          end

          response = conn.post("/chat/completions") do |req|
            req.headers["Authorization"] = "Bearer #{@api_key}"
            req.headers["Content-Type"] = "application/json"
            req.body = {
              model: @model,
              messages: messages,
              temperature: 0.7
            }.to_json
          end

          unless response.success?
            raise "OpenAI API error: #{response.status} #{response.body}"
          end

          body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
          body.dig("choices", 0, "message", "content")&.strip || ""
        end
      end
    end
  end
end

# Ejecución directa: un par de turnos de ejemplo (requiere OPENAI_API_KEY).
if __FILE__ == $PROGRAM_NAME
  unless ENV["OPENAI_API_KEY"]
    puts "Configura OPENAI_API_KEY para ejecutar el ejemplo."
    exit 1
  end

  chat = Examples::OpenAI::Responses::Chat.new(user_id: "demo", session_id: "cli")

  puts "Chat con memoria (llmemory + OpenAI). Escribe mensajes y 'salir' para terminar.\n\n"

  loop do
    print "Tú: "
    input = $stdin.gets&.strip
    break if input.nil? || input.downcase == "salir"

    next if input.empty?

    begin
      reply = chat.chat(input)
      puts "Asistente: #{reply}\n\n"
    rescue StandardError => e
      puts "Error: #{e.message}\n\n"
    end
  end

  puts "Hasta luego."
end
