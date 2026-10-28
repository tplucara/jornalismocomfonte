package kindclass

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
	"unicode/utf8"
)

const (
	maxPlainRunes = 8000
	maxModelBytes = 16 << 10
)

// PromptV1 é o contrato enviado ao modelo. A resposta tem de ser JSON com kind e reason.
const PromptV1 = `Classifique o texto jornalístico em exatamente uma categoria:
- report: relato factual do que aconteceu, sem posição defendida pelo autor e sem conclusão interpretativa própria
- analysis: interpretação ou explicação de fatos, com leitura do autor sobre causas ou significado
- opinion: posição defendida pelo autor

Responda somente um objeto JSON com as chaves kind e reason. reason é uma frase em português, entre 20 e 500 caracteres, sem HTML. Não julgue se o texto é verdadeiro.`

// ClassifyRemote chama um endpoint compatível com chat completions.
// baseURL é a raiz com /v1 (por exemplo https://api.openai.com/v1).
// allowHTTP só vale fora de produção, para um modelo local.
func ClassifyRemote(ctx context.Context, baseURL, apiKey, model, plain string, allowHTTP bool) (Result, error) {
	endpoint, err := chatEndpoint(baseURL, allowHTTP)
	if err != nil {
		return Result{}, err
	}
	if model == "" || apiKey == "" {
		return Result{}, fmt.Errorf("modelo ou chave ausente")
	}
	body, err := json.Marshal(map[string]any{
		"model":       model,
		"temperature": 0,
		"messages": []map[string]string{
			{"role": "system", "content": PromptV1},
			{"role": "user", "content": truncateRunes(plain, maxPlainRunes)},
		},
	})
	if err != nil {
		return Result{}, err
	}
	reqCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(reqCtx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return Result{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)
	client := &http.Client{Timeout: 25 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error {
		return http.ErrUseLastResponse
	}}
	res, err := client.Do(req)
	if err != nil {
		return Result{}, err
	}
	defer res.Body.Close()
	payload, err := io.ReadAll(io.LimitReader(res.Body, maxModelBytes+1))
	if err != nil {
		return Result{}, err
	}
	if len(payload) > maxModelBytes {
		return Result{}, fmt.Errorf("resposta do modelo grande demais")
	}
	if res.StatusCode != http.StatusOK {
		return Result{}, fmt.Errorf("modelo respondeu %d", res.StatusCode)
	}
	return ParseModelContent(extractContent(payload))
}

func chatEndpoint(baseURL string, allowHTTP bool) (string, error) {
	u, err := url.Parse(strings.TrimSpace(baseURL))
	if err != nil || u.Host == "" {
		return "", fmt.Errorf("URL do modelo inválida")
	}
	if u.Scheme != "https" && !(allowHTTP && u.Scheme == "http") {
		return "", fmt.Errorf("URL do modelo precisa de https")
	}
	if u.User != nil {
		return "", fmt.Errorf("URL do modelo não leva credencial")
	}
	u.RawQuery = ""
	u.Fragment = ""
	u.Path = strings.TrimRight(u.Path, "/") + "/chat/completions"
	return u.String(), nil
}

func extractContent(payload []byte) string {
	var envelope struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal(payload, &envelope); err != nil || len(envelope.Choices) == 0 {
		return strings.TrimSpace(string(payload))
	}
	return envelope.Choices[0].Message.Content
}

// ParseModelContent aceita o JSON do modelo, com ou sem cerca de markdown.
func ParseModelContent(content string) (Result, error) {
	content = strings.TrimSpace(content)
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)
	var raw struct {
		Kind   string `json:"kind"`
		Reason string `json:"reason"`
	}
	if err := json.Unmarshal([]byte(content), &raw); err != nil {
		return Result{}, fmt.Errorf("json do modelo inválido")
	}
	got, ok := Accept(raw.Kind, raw.Reason)
	if !ok {
		return Result{}, fmt.Errorf("saída do modelo recusada")
	}
	return got, nil
}

func truncateRunes(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	i := 0
	for count := 0; i < len(s) && count < n; count++ {
		_, size := utf8.DecodeRuneInString(s[i:])
		i += size
	}
	return s[:i]
}
