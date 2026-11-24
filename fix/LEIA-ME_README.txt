ArcaneMP crowd FPS fix  /  Correcao de FPS em multidao
=====================================================

PORTUGUES
1. Feche o Hogwarts Legacy.
2. De dois cliques em install.bat (forte, +46% FPS com 100 jogadores perto)
   ou install-mild.bat (leve, +15%).
3. Abra o jogo normalmente (Forge ou ArcaneMP, os dois usam a mesma pasta).
Para desfazer: feche o jogo e de dois cliques em uninstall.bat.
O instalador muda uma linha em:
%LOCALAPPDATA%\Hogwarts Legacy\ArcaneMP\Saved\Config\WindowsNoEditor\Engine.ini
e guarda uma copia em Engine.ini.before-crowdfix.
Efeito colateral: personagens com modelo um pouco mais simples de perto.

Copiar suas configuracoes para o ArcaneMP
O ArcaneMP tem configuracoes proprias, separadas do jogo normal, e alguns
servidores travam o menu. Para levar as configuracoes do jogo normal:
1. Abra o Hogwarts Legacy SEM o ArcaneMP, ajuste graficos, camera, som e HUD,
   e feche o jogo.
2. De dois cliques em copy-settings.bat.
3. Entre no servidor normalmente.
Para desfazer: feche o jogo e de dois cliques em restore-settings.bat.
A geracao de quadros (frame generation) fica desligada na copia, porque trava
o ArcaneMP. O limite de FPS vem do jogo normal: ajuste-o la antes de copiar.

ENGLISH
1. Close Hogwarts Legacy.
2. Double-click install.bat (strong, +46% FPS with 100 players nearby)
   or install-mild.bat (mild, +15%).
3. Start the game as usual (Forge or ArcaneMP launcher, both use the same folder).
To undo: close the game and double-click uninstall.bat.
The installer changes one line in the file above and keeps a copy in
Engine.ini.before-crowdfix.
Side effect: character models are slightly simpler up close.

Copy your settings into ArcaneMP
ArcaneMP has its own settings, separate from the normal game, and some servers
lock the menu. To bring over the normal game's settings:
1. Start Hogwarts Legacy WITHOUT ArcaneMP, set graphics, camera, sound and HUD,
   and quit.
2. Double-click copy-settings.bat.
3. Join the server as usual.
To undo: close the game and double-click restore-settings.bat.
Frame generation is switched off in the copy, because it crashes ArcaneMP.
The FPS cap comes from the normal game: set it there before copying.

What it sets: [SystemSettings] r.SkeletalMeshLODBias=2 (or 1).
Source and test data: https://github.com/joaobzrra/arcanemp-crowd-fps
Author: Joao Bezerra. MIT licence. Not affiliated with ArcaneMP, MafiaHub or WB Games.
