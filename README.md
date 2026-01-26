# infra-backup
WARNING -> Au fost utilizate conștient AI-tools la crearea **system-repro**

> Prototip funcțional pentru backup + reproducere declarativă a infrastructurii locale pe **Arch Linux / EndeavourOS**

`infra-backup` este un toolkit simplu (Bash) care face **inventory → declarative → restore → validate** pentru o stație locală, astfel încât după o reinstalare să poți reface rapid configurația de bază.

---

## Scop

Tool-ul permite **backup și restore declarativ** pentru infrastructura locală, incluzând:

- **Pachete** instalate explicit (pacman + AUR)
- **Servicii systemd** activate manual
- **Config-uri selectate** (user + system)
- **Docker**: proiecte `docker-compose`, metadate volume, politici de restore
- **Backup pentru volume Docker** într-un mod reproductibil *după reinstalarea dependențelor*

> Notă: proiectul este intenționat **minimal** și servește ca demonstrație de concept pentru automatizare DevOps pe Linux.

---

## Design philosophy

### 1) Separare clară pe faze
- **Inventory** *(what exists)* → colectează starea curentă
- **Declarative** *(what should exist)* → definește starea dorită
- **Execution** *(make it so)* → aplică restore-ul
- **Validation** *(did it work)* → verifică rezultatul

### 2) Siguranță + idempotent
- operațiile pot fi rulate de mai multe ori (pe cât posibil) fără efecte adverse
- backup înainte de suprascriere (unde e cazul)
- validare înainte / după execuție

### 3) Declarativ vs imperativ (asumat)
- ❌ NU face backup la containere Docker (ele sunt reproductibile din `compose`)
- ❌ NU backup-ează secrete (`.env`, chei private, parole)
- ✅ păstrează configurații + metadate
- ✅ permite selecții și excluderi

---

## Structură

```
infra-backup/
├── cli/
│   └── menu.sh              # CLI principal (meniu interactiv)
├── inventory/               # Colectare stare curentă
│   ├── packages/            # Inventariere pachete
│   ├── services/            # Inventariere servicii systemd
│   ├── docker/              # Inventariere Docker
│   └── config/              # Inventariere fișiere config
├── declarative/             # Stare dorită (manifest)
│   ├── system.conf          # Pachete/servicii/config dorite
│   └── docker.conf          # Stare dorită Docker
├── execution/               # Orchestrare restore
│   ├── backup.sh            # Rulează inventory + generează manifest
│   ├── restore.sh           # Aplică starea declarativă
│   └── validate.sh          # Compară declared vs actual
├── config/
│   ├── include.conf         # Patterns pentru includere
│   └── exclude.conf         # Patterns pentru excludere
├── docker/
│   ├── compose/             # docker-compose projects
│   ├── volumes.meta         # metadate volume
│   └── restore.policy       # politici restore
└── README.md
```

---

## Cerințe

- **OS:** Arch Linux / EndeavourOS
- **Shell:** bash 5.0+
- **Privilegii:** root pentru operații system-wide (pachete, systemd, /etc)

---

## Instalare rapidă

```bash
git clone <repository-url>
cd infra-backup

chmod +x cli/menu.sh
chmod +x inventory/*/inventory.sh
chmod +x inventory/*/restore_*.sh
chmod +x execution/*.sh

./cli/menu.sh
```

---

## Flow tipic

### 1) Backup (Inventory phase)

```bash
./execution/backup.sh --all
./execution/backup.sh --system
./execution/backup.sh --docker
```

Ce se întâmplă în spate (simplificat):
1. colectează pachetele instalate explicit (`pacman -Qqe`)
2. colectează servicii `systemd` activate manual
3. detectează proiecte `docker-compose`
4. copiază config-urile selectate (include/exclude)
5. generează manifest declarativ (`declarative/*.conf`)

---

### 2) Review manifest (Declarative phase)

Înainte de restore, **revizuiește și editează**:

- `declarative/system.conf`
- `declarative/docker.conf`

Exemplu `system.conf`:
```conf
package.official.vim=required
package.aur.yay=required
service.system.ssh.enabled=enabled
config.system.etc_fstab.state=present
```

Exemplu `docker.conf`:
```conf
docker.compose.nextcloud.file=inventory/docker/compose/nextcloud/docker-compose.yml
docker.volume.nextcloud_data.state=present
```

---

### 3) Restore (Execution phase)

```bash
./execution/restore.sh --all --dry-run
sudo ./execution/restore.sh --all

sudo ./execution/restore.sh --system
./execution/restore.sh --docker
```

---

### 4) Validate

```bash
./execution/validate.sh --all
./execution/validate.sh --all --report json --output validation.json
./execution/validate.sh --system --detailed
```

---

## CLI menu

Tool-ul include un meniu interactiv:

```
🚀 INFRA-BACKUP v0.1.0

System:
  1) Backup System
  2) Restore System
  3) Validate System

Docker:
  4) Backup Docker
  5) Restore Docker
  6) Validate Docker

Utility:
  0) Exit
```

---

## Siguranță & securitate

### Ce NU este backup-uit
- `.env` cu date personale
- chei private SSH/GPG
- certificate/parole
- date sensibile din aplicații
- cache / fișiere temporare

### Recomandări `.gitignore`
```gitignore
*.key
*.pem
.env*
inventory/config/files/*id_rsa*
inventory/config/files/*gnupg*
```

---

## Extensibilitate

### Adăugare module nou
1. creează director în `inventory/<modul>/`
2. implementează:
   - `inventory.sh`
   - `restore_<modul>.sh`
3. adaugă opțiuni în `cli/menu.sh`

### Hooks (opțional)
```bash
infra-backup/hooks/pre-backup.sh
infra-backup/hooks/post-restore.sh
```

---

## Troubleshooting

### Permission denied
```bash
sudo ./execution/restore.sh --system
```

### Docker daemon not running
```bash
sudo systemctl start docker
sudo systemctl enable docker
```

### Package not found
```bash
sudo pacman -Sy
yay -Ss <package>
```

### Service not found
```bash
systemctl list-unit-files | grep <service>
```

---

## Limitări (asumate)
- prototip / nu e testat pe multe configurații
- suport AUR limitat (yay/paru)
- config-uri complexe pot necesita intervenție manuală
- nu e cross-distro (Arch-only)

---

## Roadmap (opțional)
- [ ] shellcheck + CI minimal
- [ ] split manifest pe profile (`base`, `desktop`, `dev`)
- [ ] remote restore (SSH)
- [ ] incremental backups (config/data)
- [ ] semnături criptografice pentru inventory

---

## Contribuții
1. Fork + branch
2. Modifică
3. Documentează
4. Pull Request
