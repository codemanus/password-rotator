# Omada Kids VLAN Password Rotator

Automatically rotates WiFi passwords for your Kids VLAN on a daily schedule using the Omada Controller API. Designed for Raspberry Pi.

## Features

- 🔄 **Daily Password Rotation**: Automatically generates and updates WiFi passwords at 6 AM EST
- 🎮 **Kid-Friendly Passphrases**: Uses easy-to-type passphrases like "Red-Tiger-34" instead of complex passwords
- 📧 **Email Notifications**: Sends the new password via email each day
- 📝 **Comprehensive Logging**: Tracks all operations for troubleshooting
- 🔒 **Secure**: Uses secure authentication and proper file permissions

## Quick Install

### Option 1: Simple Installer (Recommended)

The simplest and most reliable installation method:

```bash
curl -fsSL https://raw.githubusercontent.com/codemanus/password-rotator/main/install-simple.sh | bash
```

This will:
- Install all dependencies
- Clone the repository
- Set up the config file from template
- Set proper permissions
- Guide you through the rest

### Option 2: Clone and Install

```bash
git clone https://github.com/codemanus/password-rotator.git
cd password-rotator
bash install-simple.sh
```

### Option 3: Install from Release Package

If you prefer a packaged release:

```bash
curl -fsSL https://raw.githubusercontent.com/codemanus/password-rotator/main/install-from-release.sh | bash
```

(Requires creating a GitHub release with a tarball - see Makefile)

### Option 2: Manual Installation

1. **Install dependencies:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y curl jq mailutils python3 python3-pip
   ```

2. **Create installation directory:**
   ```bash
   mkdir -p ~/omada-rotation
   cd ~/omada-rotation
   ```

3. **Download files:**
   - Copy `omada_rotation.sh` and `omada_config.conf` to `~/omada-rotation/`

4. **Set permissions:**
   ```bash
   chmod 700 omada_rotation.sh
   chmod 600 omada_config.conf
   ```

5. **Configure:**
   ```bash
   nano omada_config.conf
   ```
   Fill in your Omada Controller settings (see Configuration section below)

6. **Test:**
   ```bash
   ./omada_rotation.sh
   ```

7. **Set up cron job:**
   ```bash
   crontab -e
   ```
   Add this line:
   ```
   0 6 * * * cd ~/omada-rotation && TZ=America/New_York /bin/bash ~/omada-rotation/omada_rotation.sh >> ~/omada-rotation/cron.log 2>&1
   ```

## Configuration

Edit `omada_config.conf` with your settings:

### Required Settings

- **OMADA_URL**: Your Omada Controller URL (e.g., `https://192.168.0.2`)
- **USERNAME**: Omada Controller admin username
- **PASSWORD**: Omada Controller admin password
- **SITE_ID**: Your site ID (get from browser Developer Tools)
- **WLAN_ID**: Your WLAN ID
- **SSID_ID**: Your SSID ID
- **SSID_NAME**: The name of your Kids WiFi network
- **RATE_LIMIT_ID**: Rate limit profile ID
- **VLAN_ID**: VLAN ID (typically 20 for Kids VLAN)
- **EMAIL_TO**: Email address to receive password notifications
- **EMAIL_FROM**: Sender email address

### Getting Omada IDs

See the [Setup Guide](Setup-Guide.md) for detailed instructions on how to find these IDs using browser Developer Tools.

## Password Format

Passwords are generated in a kid-friendly format:
- **Format**: `Adjective-Noun-Number`
- **Example**: `Red-Tiger-34`, `Blue-Panda-67`, `Super-Dragon-42`

The script uses a large word list with:
- 40+ adjectives (colors, emotions, descriptive words)
- 50+ nouns (animals, characters, objects, food)
- Random numbers 10-99

This provides over 194,000 unique password combinations!

## Email Setup

The script supports multiple email methods:

1. **System mail** (mailutils) - Recommended for Raspberry Pi
2. **Sendmail** - Alternative system mail
3. **Gmail SMTP** (Python helper) - If system mail isn't configured

For Gmail, you'll need:
- Gmail account
- App Password (get from https://myaccount.google.com/apppasswords)
- Optional: `send_email.py` helper script

## Logging

- **Main log**: `~/omada-rotation/omada_rotation.log`
- **Cron log**: `~/omada-rotation/cron.log`

View logs:
```bash
tail -f ~/omada-rotation/omada_rotation.log
```

## Troubleshooting

### Script fails to authenticate
- Verify `OMADA_URL` is correct (include `https://`)
- Check username/password in config
- Test accessing controller in browser
- Check if controller is accessible: `ping <CONTROLLER_IP>`

### Email not received
- Check spam folder
- Verify postfix is running: `sudo systemctl status postfix`
- Check mail logs: `sudo tail -f /var/log/mail.log`
- Test email: `echo "test" | mail -s "test" your@email.com`

### Password not updating
- Verify all IDs are correct in config
- Check log file: `cat ~/omada-rotation/omada_rotation.log`
- Ensure SSID exists and VLAN_ID matches
- Run script manually: `bash -x ~/omada-rotation/omada_rotation.sh`

### Cron job not running
- Check cron logs: `grep CRON /var/log/syslog`
- Verify cron service: `sudo systemctl status cron`
- Check cron.log: `cat ~/omada-rotation/cron.log`
- Verify cron job: `crontab -l`

## Security Best Practices

1. **Secure the config file:**
   ```bash
   chmod 600 ~/omada-rotation/omada_config.conf
   ```

2. **Use a dedicated Omada user:**
   - Create a separate Omada admin account
   - Use it only for this script
   - Easier to audit and revoke if needed

3. **Never commit config file:**
   - Add `omada_config.conf` to `.gitignore`
   - Keep backups secure

4. **Monitor logs regularly:**
   - Set up log rotation
   - Check for errors periodically

## Files

- `omada_rotation.sh` - Main rotation script
- `omada_config.conf` - Configuration file (create from template)
- `install.sh` - Installation script
- `Setup-Guide.md` - Detailed setup instructions

## License

[Add your license here]

## Support

For issues and questions, please open an issue on GitHub.

