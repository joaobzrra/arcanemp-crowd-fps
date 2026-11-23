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

ENGLISH
1. Close Hogwarts Legacy.
2. Double-click install.bat (strong, +46% FPS with 100 players nearby)
   or install-mild.bat (mild, +15%).
3. Start the game as usual (Forge or ArcaneMP launcher, both use the same folder).
To undo: close the game and double-click uninstall.bat.
The installer changes one line in the file above and keeps a copy in
Engine.ini.before-crowdfix.
Side effect: character models are slightly simpler up close.

What it sets: [SystemSettings] r.SkeletalMeshLODBias=2 (or 1).
Source and test data: <GITHUB_LINK>
Author: Joao Bezerra. MIT licence. Not affiliated with ArcaneMP, MafiaHub or WB Games.
