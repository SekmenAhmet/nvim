# 🚀 Neovim Configuration

Une configuration Neovim moderne, rapide et personnalisée avec un thème Tokyo Night et des fonctionnalités avancées.

## ✨ Fonctionnalités

### 🎨 Interface
- **Thème personnalisé** : Tokyo Night Refined avec des couleurs modernes et contrastées
- **Statusline native** : Barre de statut personnalisée affichant le mode, le fichier, les diagnostics et le temps de démarrage
- **Tabline native** : Gestion des buffers avec indicateurs de diagnostics LSP
- **Interface utilisateur** : Icônes personnalisées pour les types de fichiers et les dossiers

### ⚡ Performance
- **Démarrage optimisé** : Chargement différé des modules non critiques
- **Loader Lua** : Cache des modules Lua activé pour des performances maximales
- **Providers désactivés** : Python, Ruby, Node.js et Perl providers désactivés pour réduire le temps de démarrage
- **Plugins natifs désactivés** : Netrw, gzip, tar, etc. désactivés pour améliorer les performances
- **Mesure du temps de démarrage** : Commande `:StartupTime` pour afficher le temps de démarrage

### 🛠️ Développement
- **LSP (Language Server Protocol)** :
  - Support pour Lua, Python, TypeScript, HTML, CSS
  - Autocomplétion native avec suggestions automatiques
  - Diagnostics en temps réel
  - Navigation de code (go to definition, references, etc.)
  
- **Treesitter** :
  - Coloration syntaxique avancée
  - Indentation intelligente
  - Support pour de nombreux langages

- **Mason** :
  - Gestionnaire de serveurs LSP
  - Installation facile via `:Mason`

### 📝 Édition
- **Autopairs** : Fermeture automatique des parenthèses, crochets et guillemets
- **Multicursor** : Support des curseurs multiples
- **Marks** : Gestion des marques
- **Illuminate** : Mise en surbrillance des occurrences du mot sous le curseur
- **Quickfix** : Navigation améliorée dans la liste quickfix

### 🔍 Navigation
- **Finder** : Explorateur de fichiers natif personnalisé
- **Grep** : Recherche dans les fichiers avec aperçu
- **Terminal** : Terminal intégré
- **Window Management** : Gestion avancée des fenêtres

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
