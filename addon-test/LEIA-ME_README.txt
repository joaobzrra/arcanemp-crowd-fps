CrowdFix add-on (TEST BUILD) / CrowdFix (VERSAO DE TESTE)
=========================================================
Not approved by ArcaneMP yet. Use at your own risk.
Ainda nao aprovado pelo ArcaneMP. Use por sua conta e risco.

PORTUGUES
O que faz: jogadores a mais de 25 m passam a animar com menos atualizacoes
(otimizacao do proprio Unreal, URO), com suavizacao. Jogadores perto nao mudam.
Teste: 100 personagens espalhados de 15 a 50 m, junto com a correcao de LOD
(r.SkeletalMeshLODBias=2): 56,8 -> 61 FPS estaveis, sem travadas visiveis.
1. Rode start-crowdfix.bat (antes ou depois de abrir o jogo).
2. Abra o jogo normalmente (Forge ou launcher do ArcaneMP).
3. A janela avisa "CrowdFix loaded" cerca de 30 s depois que o jogo abre.
Para desligar: feche o jogo. Nada fica instalado.
Ajustes: ue4ss\Mods\CrowdFix\settings.txt (distance em cm, enabled=0 desliga).

ENGLISH
What it does: players farther than 25 m animate with fewer updates (Unreal's own
update-rate optimisation, URO), with interpolation. Nearby players are untouched.
Test: 100 characters spread 15-50 m, together with the LOD fix
(r.SkeletalMeshLODBias=2): 56.8 -> stable 61 FPS, no visible stutter.
1. Run start-crowdfix.bat (before or after starting the game).
2. Start the game as usual (Forge or ArcaneMP launcher).
3. The window prints "CrowdFix loaded" about 30 s after the game opens.
To stop: close the game. Nothing stays installed.
Settings: ue4ss\Mods\CrowdFix\settings.txt (distance in cm, enabled=0 turns it off).

Known: a.URO.ForceAnimRate=2 also applies to game NPCs that use URO.
Includes UE4SS v4.0.0 (MIT licence, github.com/UE4SS-RE/RE-UE4SS, see ue4ss\LICENSE).
Source and test data: https://github.com/joaobzrra/arcanemp-crowd-fps
Author: Joao Bezerra. Not affiliated with ArcaneMP, MafiaHub or WB Games.
