# Bangla CRM: installation and everyday use

*বাংলায় পড়ুন: [README.bn.md](README.bn.md)*

Bangla CRM is a customer-relationship manager with a **Bangla interface by default**. It covers people and companies, deals, tasks, notes, email and calendar sync, workflows and AI. It is built on the open-source CRM [Twenty](https://github.com/twentyhq/twenty) and runs on your own computer or your own cloud server, so your data stays with you.

---

## 1. What you need

| | Minimum | Recommended |
|---|---|---|
| Computer | Windows 10/11 (64-bit), macOS 14 or newer, or Linux on an Intel/AMD (x86-64) processor | |
| Memory (RAM) | 4 GB | 8 GB or more |
| Free disk | 10 GB | 20 GB or more |
| Internet | Needed for the first download (about 1 GB) and for updates | |
| Docker | **Docker Desktop** (Windows/macOS) or Docker Engine (Linux) | |

- **Windows:** Docker Desktop uses WSL 2, so **hardware virtualization must be enabled** in the BIOS/UEFI (usually called *Virtualization*, *SVM* or *VT-x*).
- **Docker Desktop licence:** Docker Desktop is free for personal use, education and small businesses (fewer than 250 employees **and** less than USD 10 million annual revenue). Larger organisations need a paid Docker subscription, or can use Docker Engine on Linux.
- **Apple Silicon Macs (M1–M4):** Bangla CRM runs through Docker Desktop's built-in emulation. It works, but is slower than on an Intel/AMD computer.
- **Linux on ARM (for example Raspberry Pi, or ARM cloud servers):** not supported.

## 2. Install

### Windows
1. Right-click the downloaded `.zip` → **Properties** → tick **Unblock** → **OK**. (This stops Windows from blocking the installer.)
2. Extract the zip to a permanent folder, for example `Documents\Bangla CRM`. **Keep this folder**: it holds your settings (`.env`) and your backups.
3. Double-click **`Install-Bangla-CRM.cmd`**.
   - If Docker Desktop is missing, the installer offers to install it. Restart Windows afterwards, open Docker Desktop once, accept its terms, wait for *Engine running*, then double-click `Install-Bangla-CRM.cmd` again.
4. Wait. The first start downloads about 1 GB and sets up the database, which takes about 5–15 minutes. Your browser then opens Bangla CRM, and a **Bangla CRM** shortcut appears on your desktop.

**Installer options** (another port, sharing on your network, a specific version): open the Bangla CRM folder, type `cmd` in the folder's address bar and press Enter, then run for example:
`Install-Bangla-CRM.cmd -Port 3100`, `Install-Bangla-CRM.cmd -Lan`, or `Install-Bangla-CRM.cmd -Version 0.1.0`.

### macOS and Linux
```bash
bash install.sh
```
Options: `--port 3100` (another port), `--lan` (share on your network), `--version 0.1.0` (a specific release).

### Cloud server (Ubuntu 22.04 / 24.04, x86-64) with HTTPS
1. Create an **x86-64 (Intel/AMD)** server (2 GB RAM minimum, 4 GB recommended) and point your domain's DNS **A record** at its public IP.
2. Copy this folder to the server. Over SSH, inside the folder, run:
   ```bash
   sudo bash deploy-cloud.sh crm.example.com you@example.com
   ```
   The script installs Docker if needed, opens ports 80/443, gets a free HTTPS certificate (Let's Encrypt), and offers a swap file and a nightly backup.
3. **Setup mode:** at first, only **your own IP address** (the one you connected from over SSH) can open the site, so nobody else can sign up first and become administrator.
   Open `https://your-domain` **right away and sign up**. Then open the site to your team:
   ```bash
   sudo bash bangla-crm.sh finish-setup
   ```
4. If your cloud provider has its own firewall or security group, allow ports **80** and **443** there.

## 3. First steps in the app
1. Open Bangla CRM: the desktop shortcut on Windows, `http://localhost:3000` on a local install, or `https://your-domain` on a cloud server.
2. **Sign up.** The **first account becomes the administrator** of this installation.
3. The interface is in Bangla. Each user can switch language under **Settings → Experience → Language** (সেটিংস → অভিজ্ঞতা → ভাষা).
4. Invite your team from **Settings → Members** (সেটিংস → সদস্যগণ). For invitation emails to be delivered, set up email first (see below).

### Email (SMTP), for invitations and password resets
As the administrator, open **Settings → Admin Panel → Config Variables** (সেটিংস → অ্যাডমিন প্যানেল → কনফিগ ভেরিয়েবলসমূহ), find the email settings, and enter your mail provider's SMTP details. For example, for Gmail use an **App Password**, not your normal password:
- `EMAIL_DRIVER`: SMTP
- `EMAIL_SMTP_HOST`: `smtp.gmail.com`, `EMAIL_SMTP_PORT`: `465`
- `EMAIL_SMTP_USER`: `you@gmail.com`, `EMAIL_SMTP_PASSWORD`: your app password
- `EMAIL_FROM_ADDRESS`: `you@gmail.com`, `EMAIL_FROM_NAME`: your company name

### AI features with OpenRouter (optional)
Bangla CRM can use AI models through [OpenRouter](https://openrouter.ai) with **your own** OpenRouter key. No key is included with Bangla CRM.
1. Create an API key at <https://openrouter.ai/keys>.
2. In Bangla CRM open **Settings → Admin Panel → AI** and click **Add Custom Provider** (সেটিংস → অ্যাডমিন প্যানেল → AI → কাস্টম প্রোভাইডার যোগ করুন).
3. Under **Provider**, pick **OpenRouter** if it is in the list. Otherwise click **Custom provider** (কাস্টম প্রোভাইডার).
4. Fill in **Label**: `OpenRouter`, **API Key**: your key, and **Base URL**: `https://openrouter.ai/api/v1`. Then **Save**.
5. Open the new OpenRouter entry. If it has no models yet, click **Add Model** (মডেল যোগ করুন) and enter the **Model ID** exactly as shown on <https://openrouter.ai/models> (for example a model ending in `:free`) and a label. Make sure the models you want are switched on.
6. The models then appear wherever Bangla CRM offers an AI model.

Notes:
- OpenRouter's free models have daily limits. Paid models are charged to your OpenRouter credits.
- Custom AI providers are offered free of charge by Twenty for installations with **up to 25 members**. Above 25, Twenty requires an Enterprise key.

## 4. Everyday use

| Task | Windows (double-click; options from a `cmd` window in the folder) | macOS / Linux |
|---|---|---|
| Start | `Start-Bangla-CRM.cmd` | `bash bangla-crm.sh start` |
| Stop (data is kept) | `Stop-Bangla-CRM.cmd` | `bash bangla-crm.sh stop` |
| Back up | `Backup-Bangla-CRM.cmd` | `bash bangla-crm.sh backup` |
| Update to the newest release | `Update-Bangla-CRM.cmd` | `bash bangla-crm.sh update` |
| Update to a specific release | `Update-Bangla-CRM.cmd -Version 0.2.0` | `bash bangla-crm.sh update --version 0.2.0` |
| Restore a backup | `Restore-Bangla-CRM.cmd` (asks which one; or drag a backup folder onto it) | `bash bangla-crm.sh restore backups/<date-time>` |
| Logs | `Logs-Bangla-CRM.cmd` | `bash bangla-crm.sh logs` |
| Status | `powershell -ExecutionPolicy Bypass -File bangla-crm.ps1 status` | `bash bangla-crm.sh status` |

Bangla CRM restarts automatically with Docker Desktop if it was running when the computer shut down. To have it available after every restart, enable *Start Docker Desktop when you sign in* in Docker Desktop's settings.

### Backups
- A backup is a folder `backups/<date-time>/` containing `database.dump`, `files/` (uploaded attachments), `env.txt` (a copy of your settings, **including the encryption key**) and `version.txt`.
- **Keep backups private.** Anyone with a backup can read your CRM data. Copy them to another disk or a private cloud folder; a backup on the same disk does not protect you from a disk failure.
- On cloud servers, `deploy-cloud.sh` can set up a nightly backup at 02:30 Bangladesh time that keeps the last 14 days.

### Restore
Restore **replaces all current data** with the chosen backup. You must type `RESTORE` to confirm. Before anything changes, a **safety backup** of the current data is made. The backup is first restored into a temporary database; if that fails, your current data is left untouched. If the backup was made with a different encryption key, Bangla CRM switches to the backup's key and keeps your previous settings in `.env.before-restore-<date-time>`.

### Updates
Update checks for the newest published release. If you are up to date, nothing happens. Otherwise it makes a backup, downloads and starts the new version, and upgrades the database automatically. **If the new version does not start, it goes back to the previous version and the backup automatically.**

### Moving to a new computer, or unpacking a newer zip
You do **not** need a new zip to update: just run Update in your existing folder. If you move to a new computer or folder:
1. Install Docker, and unpack Bangla CRM into the new folder.
2. Copy **`.env`** and the **`backups`** folder from the old folder into the new folder (or rename a backup's `env.txt` to `.env`).
3. Run the installer, then **Restore** your latest backup.

On the same computer, the installer refuses to start from a new folder without the old `.env`, because that would make the existing data unreadable.

## 5. Sharing on your office network
Run the installer with `-Lan` on Windows or `--lan` on macOS/Linux. Other computers then open `http://<this-computer's-IP>:3000`, and the installer prints that address. Ask whoever manages your router to reserve this IP address for the computer, so it does not change. The computer running Bangla CRM must stay on.
On Windows, if others cannot connect, allow **Docker Desktop** through *Windows Defender Firewall* for **Private** networks.

## 6. Troubleshooting
| Problem | What to do |
|---|---|
| "Port 3000 is in use or reserved" | Run the installer with another port: `Install-Bangla-CRM.cmd -Port 3100` / `bash install.sh --port 3100`. |
| The first start takes long | Normal: the database is being created (up to ~15 minutes on slow computers). |
| "Docker is not running" | Open Docker Desktop, wait for *Engine running*, then try again. |
| Docker Desktop says virtualization is not enabled | Turn on *Virtualization* / *SVM* / *VT-x* in the BIOS/UEFI settings, then restart. |
| Download fails with *denied* / *not found* | That version does not exist. Use a release number from the *Releases* page at <https://github.com/Rabbit-s-Hat/bangla-crm/releases>. |
| Cloud site says "being set up" | You are not on the IP address you installed from. Sign up from that connection, or run `sudo bash bangla-crm.sh finish-setup`. |
| Something else | Run Logs (see the table above) and send the last lines to your Bangla CRM support contact. |

## 7. Uninstall
- Stop and remove the program, **keeping your data**: in this folder run `docker compose down`.
- Remove **everything, including all data**: `docker compose down -v`. This cannot be undone, so make a backup first.

## 8. Licence and source code
Bangla CRM is free and open-source software under the **GNU Affero General Public License v3** (AGPL-3.0), based on Twenty. The complete source code of this version is at <https://github.com/Rabbit-s-Hat/bangla-crm>. See [NOTICE.md](NOTICE.md) and `LICENSE` for details, trademarks and third-party components.
