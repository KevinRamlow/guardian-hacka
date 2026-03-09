# Anton CEO Pitch - Presentation Slides

**Created:** 2026-03-08 using nano-banana (Gemini Pro Image)
**Format:** PNG, 16:9 aspect ratio, high quality (~600KB each)
**Total size:** 4.2MB

## Slides

1. **slide-01-title.png** - Title/Cover
   - ANTON: AI Orchestration Platform
   - Apresentação para CEO - Brandlovrs
   
2. **slide-02-summary.png** - Executive Summary
   - 3 dias de operação
   - Métricas principais: +5.7pp, 10 evals, 2,579 lines
   
3. **slide-03-problem.png** - O Problema
   - Antes do Anton vs Depois do Anton
   - Serial vs Parallel execution
   
4. **slide-04-results.png** - Resultados Concretos
   - Guardian: 73.6% → 79.3%
   - GitHub: 5 commits, 2,579 linhas
   - Evals: 10 runs, 1,210 validações
   
5. **slide-05-roi.png** - ROI
   - 375:1 ROI
   - R$750k GMV adicional/mês
   - R$2k custo
   
6. **slide-06-roadmap.png** - Roadmap Q2 2026
   - Guardian: 85% accuracy target
   - Billy: Deploy to Marketing/GTM
   - Platform: Son of Anton, multi-tenancy
   
7. **slide-07-recommendation.png** - Recomendação
   - Aprovar investimento contínuo
   - Investment ask: R$6k→R$15k/mês
   - Expected return: R$2-3M/ano

## How to Use

### Option 1: Google Slides
1. Abrir Google Slides
2. Criar apresentação vazia
3. Inserir → Imagem → cada slide
4. Ajustar para fit full slide

### Option 2: PowerPoint
1. Abrir PowerPoint
2. Criar apresentação vazia (16:9)
3. Inserir → Imagens → cada slide
4. Ajustar para full slide

### Option 3: Keynote (Mac)
1. Abrir Keynote
2. Criar apresentação vazia (Wide)
3. Arrastar e soltar cada imagem
4. Ajustar para fit slide

### Option 4: PDF
```bash
# Convert to PDF
convert slide-*.png anton-ceo-pitch.pdf
```

## Editing

Se precisar editar texto/números:
1. Use os slides como base visual
2. Adicione text boxes por cima no Google Slides/PowerPoint
3. Ou re-gere slides com nano-banana ajustando prompts

## Regenerate

Se quiser re-gerar algum slide:
```bash
cd ~/.openclaw/workspace
python3 skills/nano-banana/scripts/generate_image.py \
  --prompt "seu prompt aqui" \
  --output presentations/anton-ceo-pitch/slide-XX-name.png \
  --model gemini-3-pro-image-preview \
  --aspect-ratio 16:9
```

---

**Source doc:** `docs/ANTON-CEO-PITCH.md`
**Notion version:** https://www.notion.so/Anton-CEO-Pitch-31d515fa19fc8108a774c32cf551ffa1
