// Package kindclass atribui a tag do artigo (reportagem, análise, opinião)
// a partir do texto. A rubrica local é determinística e versionada. Um modelo
// externo só entra quando a configuração traz URL, chave e nome; a saída é
// validada antes de valer. Nenhum dos dois decide se o texto é verdadeiro.
package kindclass

import (
	"strings"
	"unicode/utf8"
)

const (
	RubricModel  = "kind-rubric-v1"
	RubricMethod = "rubric:kind-v1"
	PromptMethod = "ai_model:kind-prompt-v1"

	KindReport   = "report"
	KindAnalysis = "analysis"
	KindOpinion  = "opinion"
)

const (
	reasonOpinion  = "Opinião: o texto toma uma posição do autor, em vez de só relatar o fato."
	reasonAnalysis = "Análise: o texto interpreta os fatos citados e explica causas ou significado."
	reasonReport   = "Reportagem: o texto relata o ocorrido, sem posição defendida e sem conclusão própria."
)

// Result é a saída aceita para gravar. Reason já está em português e dentro do limite.
type Result struct {
	Kind   string
	Reason string
}

// Classify aplica a rubrica kind-rubric-v1 ao texto plano (título + parágrafos).
func Classify(plain string) Result {
	text := strings.ToLower(plain)
	switch {
	case hasAny(text, "defendo", "é uma posição", "minha opinião", "na minha opinião", "acho que", "acredito que"):
		return Result{Kind: KindOpinion, Reason: reasonOpinion}
	case hasAny(text, "minha leitura", "isso significa", "por que", "fatores explicam"):
		return Result{Kind: KindAnalysis, Reason: reasonAnalysis}
	default:
		return Result{Kind: KindReport, Reason: reasonReport}
	}
}

func hasAny(text string, cues ...string) bool {
	for _, cue := range cues {
		if strings.Contains(text, cue) {
			return true
		}
	}
	return false
}

// Accept rejeita kind fora das três tags, motivo curto demais ou com marcação.
func Accept(kind, reason string) (Result, bool) {
	kind = strings.TrimSpace(kind)
	reason = strings.TrimSpace(reason)
	switch kind {
	case KindReport, KindAnalysis, KindOpinion:
	default:
		return Result{}, false
	}
	n := utf8.RuneCountInString(reason)
	if n < 20 || n > 500 {
		return Result{}, false
	}
	if strings.ContainsAny(reason, "<>") {
		return Result{}, false
	}
	for _, r := range reason {
		if r < 0x20 && r != '\n' && r != '\t' {
			return Result{}, false
		}
	}
	return Result{Kind: kind, Reason: reason}, true
}
