CrowdFix add-on (TEST BUILD) / CrowdFix (VERSAO DE TESTE)
=========================================================
Not approved by ArcaneMP yet. Use at your own risk.
Ainda nao aprovado pelo ArcaneMP. Use por sua conta e risco.

PORTUGUES
O que faz: jogadores a mais de 25 m passam a animar com menos atualizacoes
(otimizacao do proprio Unreal, URO), com suavizacao. Jogadores perto nao mudam.
Teste: 100 personagens espalhados de 15 a 50 m, junto com a correcao de LOD
(r.SkeletalMeshLODBias=2): 56,8 -> 61 FPS estaveis, sem travadas visiveis.
1. Rode start-crowdfix.bat (antes ou depois de abrir o jogo) e escolha o modo:
   1 Ultra Performance (100 m): jogadores a mais de 100 m dormem (nao sao desenhados
     nem animados neste PC); a mais de 10 m animam com menos atualizacoes.
   2 Performance (200 m): jogadores a mais de 200 m dormem; menos atualizacoes a mais de 15 m.
   3 Balanced: ninguem dorme; menos atualizacoes a mais de 20 m.
   4 Quality: ninguem dorme; menos atualizacoes a mais de 25 m (padrao testado).
   PC fraco: 1 ou 2. Rodar de novo com o jogo aberto so troca o modo.
2. Abra o jogo normalmente (Forge ou launcher do ArcaneMP).
3. A janela avisa "CrowdFix loaded" cerca de 30 s depois que o jogo abre.
Para desligar: feche o jogo. Nada fica instalado.
Ajustes: ue4ss\Mods\CrowdFix\settings.txt (distance em cm, enabled=0 desliga).
Novo: jogadores a mais de 50 m (fardistance=5000) animam so 5 vezes por segundo
(farinterval=0.2; farinterval=0 desliga). Teste ao vivo, 30-38 jogadores: 57 -> 66 FPS.
Novo: dormir (sleepdistance, em cm; 0 desliga). Fora de uma aula o jogo carrega o
servidor inteiro, mesmo quem esta a centenas de metros. Quem esta alem da distancia
some so no seu PC e para de animar; acorda sozinho quando chega perto (a 90% da
distancia). Nada e enviado ao servidor e ninguem mais ve diferenca.
Teste ao vivo, 65-88 jogadores carregados, quase todos a mais de 100 m:
200 m: 44 -> 63 FPS; 100 m: 46 -> 74 FPS (limite de 75).
Limite: uma multidao perto de voce (todos a menos de 30 m) nao melhora com este add-on.

ENGLISH
What it does: players farther than 25 m animate with fewer updates (Unreal's own
update-rate optimisation, URO), with interpolation. Nearby players are untouched.
Test: 100 characters spread 15-50 m, together with the LOD fix
(r.SkeletalMeshLODBias=2): 56.8 -> stable 61 FPS, no visible stutter.
1. Run start-crowdfix.bat (before or after starting the game) and pick a preset:
   1 Ultra Performance (100 m): players farther than 100 m sleep (not drawn and not
     animated on this PC); farther than 10 m they animate with fewer updates.
   2 Performance (200 m): players farther than 200 m sleep; fewer updates beyond 15 m.
   3 Balanced: nobody sleeps; fewer updates beyond 20 m.
   4 Quality: nobody sleeps; fewer updates beyond 25 m (tested default).
   Weak PC: 1 or 2. Running it again while the game is open only switches the preset.
2. Start the game as usual (Forge or ArcaneMP launcher).
3. The window prints "CrowdFix loaded" about 30 s after the game opens.
To stop: close the game. Nothing stays installed.
Settings: ue4ss\Mods\CrowdFix\settings.txt (distance in cm, enabled=0 turns it off).
New: players farther than 50 m (fardistance=5000) animate only 5 times a second
(farinterval=0.2; farinterval=0 turns it off). Live test, 30-38 players: 57 -> 66 FPS.
New: sleep (sleepdistance, in cm; 0 turns it off). Outside a class the game loads the
whole server, including players hundreds of metres away. Players beyond the distance
disappear on your PC only and stop animating; they wake up by themselves when they
come closer (at 90% of the distance). Nothing is sent to the server and nobody else
sees a difference.
Live test, 65-88 players loaded, almost all farther than 100 m:
200 m: 44 -> 63 FPS; 100 m: 46 -> 74 FPS (75 cap).
Limit: a crowd close to you (everybody within 30 m) does not improve with this add-on.

Known: a.URO.ForceAnimRate=2 also applies to game NPCs that use URO.
Includes UE4SS v4.0.0 (MIT licence, github.com/UE4SS-RE/RE-UE4SS, see ue4ss\LICENSE).
Source and test data: https://github.com/joaobzrra/arcanemp-crowd-fps
Author: Joao Bezerra. Not affiliated with ArcaneMP, MafiaHub or WB Games.
