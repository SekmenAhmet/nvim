## 🚀 Neovim Configuration (MVC Native Edition)

Une configuration Neovim moderne, ultra-rapide et totalement native, structurée selon un pattern **MVC (Model-View-Controller)** pour une maintenance et une performance optimales.

## ✨ Fonctionnalités Majeures (Native Tools)

### 🐳 Docker Commander (Native MVC)
- **Gestion complète** : Conteneurs, Images et Volumes dans une interface flottante.
- **Performance** : Totalement asynchrone via `vim.uv` (ne bloque jamais l'UI).
- **Intégration** : Logs en temps réel et terminaux exécutés directement dans Neovim.

### 󰊢 Git Ninja (Native MVC)
- **Dashboard Git** : Interface complète pour le staging, les branches, les stashes et les commits.
- **AI Commit** : Génération de messages de commit intelligents via IA (Ollama/OpenAI) intégrée.
- **Diff & Patch** : Prévisualisation des diffs et application sélective de hunks nativement.

### 󰖟 REST Architect (Native MVC)
- **Client HTTP complet** : Support OpenAPI (YAML), variables d'environnement (.env) et historique.
- **Asynchrone** : Exécution de requêtes via `curl` en arrière-plan avec prévisualisation du corps et des headers.
- **UI Tabulée** : Navigation fluide entre le body, les headers et la réponse.

### 🧠 Workflow Integrator
- **Automatisation** : Connexion intelligente entre les outils (ex: Docker triggers Git actions).
- **Central State** : Source de vérité unique (`core.state`) pour une interface réactive.

## 🎨 Interface & UX
- **Tokyo Night Refined** : Thème sombre moderne et contrasté.
- **Native UI Kit** : Utilisation exclusive des fenêtres flottantes natives, `vim.ui.select` et `vim.ui.input` personnalisés.
- **Responsive** : Redimensionnement automatique des panneaux et disposition adaptative.

## ⚡ Performance & Qualité
- **Async First** : Toutes les opérations d'I/O et de processus utilisent `vim.uv` (Anti-Freeze).
- **Structure Propre** : Code modulaire (Model/View/Controller) validé par `lua-doctor`.
- **Zéro Bloat** : Dépendances externes minimales (Lazy, Mason, Treesitter).

## ⌨️ Raccourcis Clavier Principaux

| Raccourci | Description |
|-----------|-------------|
| `<C-g>` | Toggle Git Dashboard |
| `<C-d>` | Toggle Docker Client |
| `<C-p>` | Toggle REST Client |
| `<C-t>` | Toggle Terminal |
| `<C-b>` | Toggle File Tree (Netrw) |
| `<Leader>ff` | Find Files (Native) |
| `<Leader>fg` | Live Grep (Native) |

## 📁 Structure du Projet (MVC)

```
nvim/
├── init.lua                 # Point d'entrée optimisé
├── lua/
│   ├── core/
│   │   └── state.lua        # Modèle d'état central (Single Source of Truth)
│   ├── modules/             # Outils All-in-One (MVC Pattern)
│   │   ├── docker/          # Model, View, Controller pour Docker
│   │   ├── git/             # Model, View, Controller pour Git
│   │   └── rest/            # Model, View, Controller pour REST
│   ├── config/              # Configurations & Bridges
│   └── utils/               # Helpers UI, IO, AI et Picker
└── README.md
```

## 📦 Installation

### Prérequis
- Neovim >= 0.9.0
- Git
- Un terminal avec support des couleurs true (termguicolors)
- [Nerd Font](https://www.nerdfonts.com/) pour les icônes (recommandé)
- `ripgrep` pour la recherche (optionnel mais recommandé)
- Fish shell (ou modifier `lua/config/options.lua` pour votre shell préféré)

### Installation

1. **Sauvegarder votre configuration actuelle** (si elle existe) :
```bash
mv ~/.config/nvim ~/.config/nvim.backup
mv ~/.local/share/nvim ~/.local/share/nvim.backup
```

2. **Cloner cette configuration** :
```bash
git clone https://github.com/SekmenAhmet/nvim.git ~/.config/nvim
```

3. **Lancer Neovim** :
```bash
nvim
```

Au premier lancement, [lazy.nvim](https://github.com/folke/lazy.nvim) sera automatiquement installé et téléchargera tous les plugins.

4. **Installer les serveurs LSP** (optionnel) :
```vim
:Mason
```
Puis sélectionnez et installez les serveurs de langage dont vous avez besoin.

## ⌨️ Raccourcis Clavier

### Général
| Raccourci | Mode | Description |
|-----------|------|-------------|
| `<Space>` | Normal | Leader key |
| `<C-s>` | Normal/Insert/Visual | Sauvegarder le fichier |
| `<Tab>` | Normal | Buffer suivant |
| `<S-Tab>` | Normal | Buffer précédent |
| `<C-q>` | Normal | Fermer le buffer courant |

### Navigation entre Fenêtres
| Raccourci | Mode | Description |
|-----------|------|-------------|
| `<C-h>` | Normal/Terminal | Aller à la fenêtre de gauche |
| `<C-j>` | Normal/Terminal | Aller à la fenêtre du bas |
| `<C-k>` | Normal/Terminal | Aller à la fenêtre du haut |
| `<C-l>` | Normal/Terminal | Aller à la fenêtre de droite |

### Redimensionnement de Fenêtres
| Raccourci | Mode | Description |
|-----------|------|-------------|
| `<C-M-Left>` | Normal | Augmenter la largeur |
| `<C-M-Right>` | Normal | Diminuer la largeur |

### Explorateur de Fichiers
| Raccourci | Mode | Description |
|-----------|------|-------------|
| `<Leader>e` | Normal | Ouvrir/Fermer l'explorateur |
| `<Leader>f` | Normal | Trouver un fichier |
| `<Leader>g` | Normal | Rechercher dans les fichiers (grep) |

### LSP
| Raccourci | Mode | Description |
|-----------|------|-------------|
| `gd` | Normal | Aller à la définition |
| `gr` | Normal | Voir les références |
| `K` | Normal | Afficher la documentation |
| `<Leader>rn` | Normal | Renommer |
| `<Leader>ca` | Normal | Actions de code |
| `[d` | Normal | Diagnostic précédent |
| `]d` | Normal | Diagnostic suivant |

### Complétion
| Raccourci | Mode | Description |
|-----------|------|-------------|
| `<C-n>` | Insert | Suggestion suivante |
| `<C-p>` | Insert | Suggestion précédente |
| `<CR>` | Insert | Confirmer la sélection |
| `<C-e>` | Insert | Annuler la complétion |

### Terminal
| Raccourci | Mode | Description |
|-----------|------|-------------|
| `<Leader>t` | Normal | Ouvrir le terminal |
| `<Esc>` | Terminal | Mode normal |

## 📁 Structure du Projet

```
nvim/
├── init.lua                 # Point d'entrée principal
├── lazy-lock.json          # Versions verrouillées des plugins
├── lua/
│   ├── config/             # Configurations principales
│   │   ├── options.lua     # Options Vim
│   │   ├── keymaps.lua     # Raccourcis clavier
│   │   ├── colors.lua      # Thème Tokyo Night personnalisé
│   │   ├── lazy.lua        # Configuration de lazy.nvim
│   │   ├── lsp.lua         # Configuration LSP
│   │   ├── completion.lua  # Autocomplétion native
│   │   ├── autopairs.lua   # Fermeture automatique
│   │   ├── statusline.lua  # Barre de statut
│   │   ├── tabline.lua     # Ligne d'onglets
│   │   ├── finder.lua      # Explorateur de fichiers
│   │   ├── grep.lua        # Recherche dans les fichiers
│   │   ├── terminal.lua    # Terminal intégré
│   │   ├── ui.lua          # Interface utilisateur
│   │   ├── autocmds.lua    # Autocommandes
│   │   ├── moves.lua       # Mouvements personnalisés
│   │   ├── illuminate.lua  # Surlignage de mots
│   │   ├── marks.lua       # Gestion des marques
│   │   ├── multicursor.lua # Curseurs multiples
│   │   ├── quickfix.lua    # Liste quickfix
│   │   └── window.lua      # Gestion des fenêtres
│   └── plugins/            # Configurations des plugins
│       ├── mason.lua       # Mason LSP manager
│       └── treesitter.lua  # Treesitter configuration
└── README.md               # Ce fichier
```

## 🎨 Thème

Cette configuration utilise un thème personnalisé basé sur **Tokyo Night** avec :
- Fond sombre moderne (#1a1b26)
- Palette de couleurs raffinée et contrastée
- Support complet de Treesitter pour une coloration syntaxique avancée
- Diagnostics LSP colorés et lisibles

## 🔧 Personnalisation

### Changer le Shell
Par défaut, la configuration utilise Fish shell. Pour changer :
```lua
-- Dans lua/config/options.lua
vim.opt.shell = "bash"  -- ou "zsh", "powershell", etc.
```

### Modifier le Leader Key
```lua
-- Dans lua/config/options.lua
vim.g.mapleader = ","  -- Par défaut " " (espace)
```

### Ajouter des Serveurs LSP
```lua
-- Dans lua/plugins/mason.lua
ensure_installed = { "lua_ls", "pyright", "ts_ls", "html", "cssls", "votre_serveur" }
```

### Désactiver les Fonctionnalités
Commentez simplement la ligne correspondante dans `init.lua` :
```lua
-- require("config.autopairs")  -- Désactive les autopairs
```

## 🚀 Commandes Utiles

| Commande | Description |
|----------|-------------|
| `:StartupTime` | Affiche le temps de démarrage de Neovim |
| `:Mason` | Ouvre le gestionnaire de serveurs LSP |
| `:TSUpdate` | Met à jour les parseurs Treesitter |
| `:Lazy` | Ouvre le gestionnaire de plugins |
| `:checkhealth` | Vérifie l'état de la configuration |

## 📝 Notes

- Cette configuration privilégie les performances avec un temps de démarrage optimisé
- L'autocomplétion se déclenche automatiquement après 2 caractères
- Les modules lourds sont chargés de manière différée pour ne pas bloquer l'interface
- La configuration utilise des solutions natives autant que possible pour minimiser les dépendances

## 🤝 Contribution

Les contributions sont les bienvenues ! N'hésitez pas à ouvrir une issue ou une pull request.

## 📄 Licence

Ce projet est libre d'utilisation. Vous pouvez le modifier et le distribuer comme vous le souhaitez.

## 🙏 Remerciements

- [Neovim](https://neovim.io/) - L'éditeur de texte moderne
- [lazy.nvim](https://github.com/folke/lazy.nvim) - Gestionnaire de plugins rapide
- [Tokyo Night](https://github.com/folke/tokyonight.nvim) - Inspiration pour le thème
- La communauté Neovim pour tous les plugins et ressources

---

Made with ❤️ for Neovim
