import { UpstreamError } from './errors.js';

const GROQ_CHAT_URL = 'https://api.groq.com/openai/v1/chat/completions';

/**
 * Thin wrapper around Groq's OpenAI-compatible chat endpoint.
 * The API key is sent only in the Authorization header. Upstream response
 * bodies are never copied into errors, so they cannot leak to the app.
 *
 * @param {{ apiKey: string, model: string, timeoutMs: number, fetchImpl?: typeof fetch }} options
 */
export function createGroqClient({ apiKey, model, timeoutMs, fetchImpl = fetch }) {
  return {
    /**
     * @param {{ messages: Array<{role: string, content: string}>, jsonMode?: boolean, maxTokens?: number }} request
     * @returns {Promise<string>} the assistant message content
     */
    async complete({ messages, jsonMode = false, maxTokens = 1024 }) {
      const body = {
        model,
        messages,
        temperature: 0.2,
        max_tokens: maxTokens,
        // GPT-OSS models reason before answering. Low effort keeps latency
        // under the 8 second budget. Other models do not take this field.
        ...(model.startsWith('openai/gpt-oss') ? { reasoning_effort: 'low' } : {}),
        ...(jsonMode ? { response_format: { type: 'json_object' } } : {}),
      };

      let response;
      try {
        response = await fetchImpl(GROQ_CHAT_URL, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${apiKey}`,
          },
          body: JSON.stringify(body),
          signal: AbortSignal.timeout(timeoutMs),
        });
      } catch (error) {
        if (error?.name === 'TimeoutError' || error?.name === 'AbortError') {
          throw new UpstreamError('AI service timed out', 504);
        }
        throw new UpstreamError('AI service is unreachable', 502);
      }

      if (!response.ok) {
        throw new UpstreamError(`AI service returned status ${response.status}`, 502);
      }

      const data = await response.json();
      const content = data?.choices?.[0]?.message?.content;
      if (typeof content !== 'string' || content.length === 0) {
        throw new UpstreamError('AI service returned no content', 502);
      }
      return content;
    },
  };
}
