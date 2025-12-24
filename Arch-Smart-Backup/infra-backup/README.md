# infra-backup
> Prototip funcțional pentru backup și reproducere automată a infrastructurii locale pe Arch Linux / EndeavourOS

##  Scop

Acest tool permite **backup și restore declarativ** al întregii infrastructuri locale, inclusiv:
-  Pachete de sistem (pacman + AUR) - doar cele explicit instalate
-  Servicii systemd activate manual
-  Fișiere de configurare selectate (user + system)
-  Docker (configurație, docker-compose, volume metadata)
-  Backup al volumelor Docker într-un mod **reproductibil după reinstalarea dependențelor**

## Design Philosophy

1. **Separare clară între faze:**
   - **Inventory** (what exists) - colectare stare curentă
   - **Declarative** (what should exist) - definirea stării dorite
   - **Execution** (make it so) - aplicarea schimbărilor
   - **Validation** (did it work) - verificarea rezultatului

2. **Idempotent și Sigur:**
   - Operațiunile pot fi executate de multiple ori fără efecte adverse
   - Backup-uri automate înainte de suprascriere
   - Validare înainte de execuție

3. **Declarativ vs Imperativ:**
   - **NU** face backup la containere Docker (sunt reproductibile din compose)
   - **NU** backup-ează secrete (.env, chei private)
   - **DA** păstrează configurația și metadatele
   - **DA** permite selecție și excluderi

## Structură

```
infra-backup/
├── cli/
│   └── menu.sh              # CLI principal cu meniu interactiv
├── inventory/               # Colectare stare curentă
│   ├── packages/           # Inventariere pachete
│   ├── services/           # Inventariere servicii systemd
│   ├── docker/             # Inventariere Docker
│   └── config/             # Inventariere fișiere config
├── declarative/            # Configurații declarative
│   ├── system.conf         # Stare dorită sistem
│   └── docker.conf         # Stare dorită Docker
├── execution/              # Execuție restore
│   ├── backup.sh           # Orchestrare backup
│   ├── restore.sh          # Orchestrare restore
│   └── validate.sh         # Validare stare
├── config/                 # Configurări
│   ├── include.conf        # Patterns pentru includere
│   └── exclude.conf        # Patterns pentru excludere
├── docker/                 # Configurații Docker
│   ├── compose/           # Fișiere docker-compose
│   ├── volumes.meta       # Metadate volume
│   └── restore.policy     # Politici restore
└── README.md              # Documentație
```

## Instalare și Utilizare

### Cerințe

- **OS:** Arch Linux / EndeavourOS
- **Shell:** bash 5.0+
- **Privilegii:** root pentru operațiuni system-wide

### Instalare Rapidă

```bash
# Clonează repository-ul
git clone <repository-url>
cd infra-backup

# Asigură permisiuni de execuție
chmod +x cli/menu.sh
chmod +x inventory/*/inventory.sh
chmod +x inventory/*/restore_*.sh
chmod +x execution/*.sh

# Rulează CLI-ul
./cli/menu.sh
```

### Flow Tipic de Utilizare

#### 1. Backup (Inventory Phase)

```bash
# Backup complet sistem + Docker
./execution/backup.sh --all

# Doar sistem
./execution/backup.sh --system

# Doar Docker
./execution/backup.sh --docker
```

**Ce se întâmplă în spate:**
1.  Se colectează pachetele explicit instalate (pacman -Qqe)
2.  Se identifică serviciile systemd activate
3.  Se găsesc fișierele docker-compose.yml
4.  Se copiază configurațiile selectate
5.  Se generează fișierele declarative
6.  Se creează scripturi de restore automatizate

#### 2. Review Declarative Configuration

**IMPORTANT:** Înainte de restore, **revizuiește și editează** fișierele:

- `declarative/system.conf` - definește ce pachete/servicii/configurări vrei
- `declarative/docker.conf` - definește proiectele Docker dorite

```bash
# Exemplu system.conf:
package.official.vim=required
package.aur.yay=required
service.system.ssh.enabled=enabled
config.system.etc_fstab.state=present

# Exemplu docker.conf:
docker.compose.nextcloud.file=inventory/docker/compose/nextcloud/docker-compose.yml
docker.volume.nextcloud_data.state=present
```

#### 3. Restore (Execution Phase)

```bash
# Dry-run (simulare) - RECOMANDAT prima dată
./execution/restore.sh --all --dry-run

# Restore complet
sudo ./execution/restore.sh --all

# Doar sistem
sudo ./execution/restore.sh --system

# Doar Docker
./execution/restore.sh --docker

# Restore cu excluderi
./execution/restore.sh --all --excludes config/exclude.txt
```

#### 4. Validation

```bash
# Validare completă
./execution/validate.sh --all

# Validare cu raport JSON
./execution/validate.sh --all --report json --output validation.json

# Validare detaliată
./execution/validate.sh --system --detailed
```

## 🔧 CLI Menu

Tool-ul include un CLI interactiv complet:

```
🚀 INFRA-BACKUP v0.1.0 - DevOps Edition

=== MAIN MENU ===

System Operations:
  1) Backup System          - Inventory packages, services, configs
  2) Restore System         - Restore from declarative state
  3) Validate System State  - Check current vs declared state

Docker Operations:
  4) Backup Docker          - Inventory Docker configuration
  5) Restore Docker         - Restore Docker stack and volumes
  6) Validate Docker State  - Check Docker configuration

Advanced Operations:
  7) Dry-Run Restore        - Simulate restore without changes
  8) Restore with Excludes  - Selective restore excluding items
  9) Generate Report        - Create system state report

Utility:
  0) Exit
```

## Siguranță și Securitate

### Ce NU este backup-uit
- ❌ `.env` files cu date personale pentru execuție
- ❌ Chei private SSH/GPG
- ❌ Certificate sau parole
- ❌ Date sensibile din aplicații
- ❌ Cache-uri și fișiere temporare

### Mecanisme de Protecție

1. **Backup automat:** Fișiere existente sunt backup-uite înainte de suprascriere
2. **Validare:** Verificări ample înainte de execuție
3. **Dry-run:** Simulare completă înainte de aplicare
4. **Logging:** Toate operațiunile sunt logate și auditable

### Git Best Practices

```bash
# Adaugă în .gitignore
*.key
*.pem
.env*
inventory/config/files/*id_rsa*
inventory/config/files/*gnupg*
```

## 🧪 Extensibilitate

### Adăugare Module Noi

1. Creează director în `inventory/nume-modul/`
2. Implementează `inventory.sh` și `restore_nume.sh`
3. Adaugă opțiuni în CLI menu

### Custom Hooks

Tool-ul suportă hook-uri pentru extensibilitate:

```bash
# Pre-backup hook
infra-backup/hooks/pre-backup.sh

# Post-restore hook
infra-backup/hooks/post-restore.sh
```

## 📊 Exemple de Utilizare

### Exemplu 1: Setup Development Machine Nou

```bash
# 1. Backup pe mașina veche
./execution/backup.sh --all

# 2. Copiază doar fișierele declarative pe mașina nouă
scp declarative/* new-machine:~/infra-backup/declarative/

# 3. Editează declarativele pe mașina nouă (adaptează)

# 4. Restore
ssh new-machine 'cd ~/infra-backup && sudo ./execution/restore.sh --all'
```

### Exemplu 2: Disaster Recovery

```bash
# 1. Restore din backup
sudo ./execution/restore.sh --system --force

# 2. Restore Docker stacks
./execution/restore.sh --docker

# 3. Restore volume data (după ce serviciile sunt create)
./docker/restore_volumes.sh

# 4. Validează totul
./execution/validate.sh --all
```

### Exemplu 3: Sincronizare Configurări

```bash
# 1. Backup pe mașina sursă
./execution/backup.sh --system

# 2. Validează pe mașina țintă
./execution/validate.sh --system --detailed

# 3. Aplică diferențele
./execution/restore.sh --system --selective
```

## 🔍 Troubleshooting

### Probleme Comune

#### 1. "Permission denied" la restore

```bash
# Rulează cu sudo pentru operațiuni system-wide
sudo ./execution/restore.sh --system
```

#### 2. "Docker daemon not running"

```bash
# Pornește Docker
sudo systemctl start docker
sudo systemctl enable docker
```

#### 3. "Package not found"

```bash
# Actualizează baza de date pacman
sudo pacman -Sy

# Verifică dacă pachetul e în AUR
yay -Ss nume-pachet
```

#### 4. "Service not found"

```bash
# Verifică dacă serviciul există
systemctl list-unit-files | grep nume-serviciu

# Dacă nu există, șterge-l din declarative/system.conf
```

### Debugging

```bash
# Verbose logging
bash -x ./execution/restore.sh --system

# Verifică fișierele generate
cat inventory/packages/packages_*.inventory
cat declarative/system.conf

# Testează module individual
./inventory/packages/inventory.sh
```

## Limitări și TODO

### Limitări Cunoscute

1. **Prototip:** Nu este încă testat pe scară largă
2. **AUR Helpers:** Suport limitat (yay, paru)
3. **Complex Configs:** Configurații foarte complexe pot necesita intervenție manuală
4. **Cross-Arch:** Nu suportă migrare între arhitecturi diferite

### Roadmap (Posibile Îmbunătățiri)

- [ ] Suport pentru mai multe AUR helpers
- [ ] Backup/restore selectiv pe versiuni
- [ ] Integrare cu Git pentru versioning
- [ ] Suport pentru alte distribuții
- [ ] GUI pentru vizualizare diferențe
- [ ] Remote backup/restore (SSH)
- [ ] Incremental backups
- [ ] Cryptographic signatures

### Cum să Contribui

1. Fork și creează un branch
2. Adaugă teste pentru modificările tale
3. Documentează schimbările
4. Creează un Pull Request