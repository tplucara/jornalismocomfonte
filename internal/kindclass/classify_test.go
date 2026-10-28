package kindclass

import "testing"

func TestClassifySeedTexts(t *testing.T) {
	cases := []struct {
		name string
		text string
		kind string
	}{
		{
			name: "inflação é análise",
			text: "Por que a inflação de alimentos caiu mais rápido que o previsto Três fatores explicam a queda. Minha leitura: o efeito do frete é subestimado.",
			kind: KindAnalysis,
		},
		{
			name: "câmara é reportagem",
			text: "Câmara aprova novo marco das concessões rodoviárias O plenário aprovou por 312 votos a 140 o texto-base.",
			kind: KindReport,
		},
		{
			name: "tarifa é opinião",
			text: "A tarifa zero no ônibus é cara, mas o congestionamento é mais Defendo que o custo fiscal é menor. É uma posição, não um dado.",
			kind: KindOpinion,
		},
		{
			name: "streaming é análise",
			text: "Streaming já responde por metade da receita da música no país Isso significa que shows perderam relevância na renda dos artistas.",
			kind: KindAnalysis,
		},
		{
			name: "banco central é reportagem",
			text: "Banco central argentino mantém taxa e sinaliza pausa A autoridade monetária argentina manteve a taxa básica em 29%.",
			kind: KindReport,
		},
		{
			name: "posição vence interpretação",
			text: "Minha leitura dos números. Defendo que a tarifa deveria acabar.",
			kind: KindOpinion,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Classify(tc.text)
			if got.Kind != tc.kind {
				t.Fatalf("kind %s, esperado %s (%s)", got.Kind, tc.kind, got.Reason)
			}
			if _, ok := Accept(got.Kind, got.Reason); !ok {
				t.Fatalf("motivo recusado: %q", got.Reason)
			}
		})
	}
}

func TestAcceptRejectsMarkupAndUnknownKind(t *testing.T) {
	if _, ok := Accept("truth", "um motivo longo o bastante para passar"); ok {
		t.Fatal("kind fora das três tags")
	}
	if _, ok := Accept(KindReport, "curto"); ok {
		t.Fatal("motivo curto")
	}
	if _, ok := Accept(KindReport, "Reportagem com <script> no motivo da classificação"); ok {
		t.Fatal("marcação no motivo")
	}
}
