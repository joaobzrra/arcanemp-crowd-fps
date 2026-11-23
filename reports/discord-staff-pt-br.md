**Queda de FPS com muitos jogadores: testes + correção**

Testei num servidor local com N personagens (mesmo modelo dos jogadores remotos) em volta de um cliente. Ryzen 9 5900XT, RTX 5060 Ti, 1080p, sem limite de FPS, Detalhe de multidão = Médio.
```
Personagens perto   0      25    50    100   150   200
FPS                 118.6  79.6  60.1  36.3  28.9  23.6
Uso da GPU          90%  ->  28%   (gargalo é o processador)
```
**Resultado**
- O que pesa é a quantidade de personagens perto, não o que eles fazem. Andar, parar, lançar feitiço, sentar, trocar roupa, efeitos: diferença máxima de ±15%.
- Cada personagem custa ~0,17 ms por frame, dividido entre a thread do jogo e a de renderização.
- Grupo novo aparecendo = um travamento de 290-330 ms.
- Limitar o jogo a 4 núcleos custou no máximo 26%: o que importa é a velocidade de cada núcleo, não a quantidade.

**Correção que já funciona (lado do jogador)**
`r.SkeletalMeshLODBias=2` em `[SystemSettings]` no arquivo `%LOCALAPPDATA%\Hogwarts Legacy\ArcaneMP\Saved\Config\WindowsNoEditor\Engine.ini`
Com 100 personagens: **39,3 → 57,3 FPS (+46%)**. Vale para o launcher Forge também (mesma pasta).
Instalador de 1 clique (instalar/desinstalar): <GITHUB_LINK>
Custo: modelos de personagem um pouco mais simples de perto.

**Não usar**: `p.ClothPhysics=0` trava o jogo ao teleportar (testado 2 vezes).

**O que depende do ArcaneMP** (já enviado a eles): reduzir detalhe dos jogadores distantes automaticamente, atualizar menos vezes os jogadores longe, espalhar o spawn em vários frames, e um limite de jogadores visíveis por cliente configurável pelo servidor.

— João Bezerra
