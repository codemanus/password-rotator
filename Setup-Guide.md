# Omada Kids VLAN Password Rotation - Setup Guide

## System Overview

This solution runs on your Raspberry Pi 3B+ and automatically:
- Generates a secure random password daily at 6 AM EST
- Updates your Kids VLAN (192.168.20.0/24) WiFi password
- Emails you the new password
- Logs all activities for troubleshooting

---

## Prerequisites

### 1. Raspberry Pi 3B+ Setup
```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install required packages
sudo apt-get install -y curl jq mailutils postfix

# Install Python alternative if mail issues (optional)
sudo apt-get install -y python3-pip
pip3 install yagmail  # for Gmail SMTP if needed
```

### 2. Configure Email (Choose One Method)

#### Option A: Postfix with Gmail SMTP
```bash
# During postfix installation, select "Internet Site"
# Set hostname to: raspberrypi.local

# Configure Postfix for Gmail
sudo nano /etc/postfix/main.cf
```

Add these lines:
```
relayhost = [smtp.gmail.com]:587
smtp_sasl_auth_enable = yes
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous
smtp_tls_security_level = encrypt
smtp_use_tls = yes
```

Create credentials file:
```bash
sudo nano /etc/postfix/sasl_passwd
```

Add (use App Password, not regular password):
```
[smtp.gmail.com]:587 your_email@gmail.com:your_app_password
```

Secure and reload:
```bash
sudo chmod 600 /etc/postfix/sasl_passwd
sudo postmap /etc/postfix/sasl_passwd
sudo systemctl restart postfix
```

#### Option B: Use External SMTP Script (Alternative)
If postfix is complex, I can provide a Python alternative using SMTP directly.

---

## Step-by-Step Configuration

### Step 1: Extract IDs from Omada Controller

1. **Access your OC200 controller** via web browser
2. **Open Browser Developer Tools** (F12 or Right-click → Inspect)
3. **Navigate to Network tab** in Developer Tools

#### Get SITE_ID and WLAN_ID:
1. In Omada interface: Settings → Wireless Networks → WLAN
2. In Developer Tools Network tab: Search for `wlans`
3. Click the request, view Response
4. Find your site and WLAN IDs in the JSON response

Example response:
```json
{
  "result": {
    "siteId": "620eba7f1396434f662caf0a",  // This is SITE_ID
    "wlanId": "620eba801396434f662caf17"   // This is WLAN_ID
  }
}
```

#### Get RATE_LIMIT_ID:
1. In Omada: Settings → Profiles → Rate Limits
2. In Developer Tools: Search for `rateLimits`
3. Find the ID in the response

#### Get SSID_ID:
1. In Omada: Wireless Networks → WLAN → Your Kids SSID
2. In Developer Tools: Search for `ssids?currentPage`
3. Find your Kids WiFi in the list, get its ID

Example:
```json
{
  "name": "Kids WiFi",
  "id": "665d2ab2a51357566e31b6b8",  // This is SSID_ID
  "vlanId": 20
}
```

### Step 2: Install Scripts on Raspberry Pi

```bash
# Create directory
mkdir -p ~/omada-rotation
cd ~/omada-rotation

# Download/create the scripts
# (Copy the script contents from the artifacts above)

# Set permissions
chmod 700 rotate_password.sh
chmod 600 omada_config.conf
```

### Step 3: Configure the Config File

Edit `omada_config.conf` with your values:
```bash
nano omada_config.conf
```

Fill in all the values you collected:
- Your OC200 IP address
- Admin credentials
- All the IDs from Step 1
- Your email address

### Step 4: Test the Script

```bash
# Run manually first to test
./rotate_password.sh

# Check the log
cat omada_rotation.log

# Verify password changed in Omada Controller
# Check your email for the notification
```

### Step 5: Set Up Cron Job (6 AM EST Daily)

```bash
# Edit crontab
crontab -e

# Add this line (adjust timezone if needed)
# This runs at 6 AM EST (11 AM UTC during DST, 10 AM UTC in winter)
0 6 * * * TZ=America/New_York /home/pi/omada-rotation/rotate_password.sh

# Or for more reliability with explicit path:
0 6 * * * cd /home/pi/omada-rotation && TZ=America/New_York /bin/bash /home/pi/omada-rotation/rotate_password.sh >> /home/pi/omada-rotation/cron.log 2>&1
```

**Note on Timezone**: The script will run at 6 AM EST/EDT automatically with the TZ setting.

---

## Verification Checklist

- [ ] All required packages installed (curl, jq, mail)
- [ ] Email system working (test with `echo "test" | mail -s "Test" your@email.com`)
- [ ] Config file has all IDs filled in
- [ ] Config file permissions set to 600
- [ ] Script permissions set to 700
- [ ] Manual test run successful
- [ ] Password visible in Omada Controller changed
- [ ] Email received with new password
- [ ] Cron job added
- [ ] Log file created and readable

---

## Testing Email Configuration

```bash
# Test basic email
echo "This is a test email" | mail -s "Test Email" your@email.com

# If no mail command:
echo "Subject: Test Email" | sendmail your@email.com
```

---

## Troubleshooting

### Script fails to authenticate:
- Verify OMADA_URL is correct (include https://)
- Check username/password in config
- Test accessing controller in browser
- Check if OC200 is accessible from Pi: `ping <OC200_IP>`

### Email not received:
- Check spam folder
- Verify postfix is running: `sudo systemctl status postfix`
- Check mail logs: `sudo tail -f /var/log/mail.log`
- Test email: `echo "test" | mail -s "test" your@email.com`

### Password not updating:
- Verify all IDs are correct in config
- Check log file: `cat ~/omada-rotation/omada_rotation.log`
- Ensure SSID exists and VLAN_ID matches (20)
- Run script manually with verbose: `bash -x ./rotate_password.sh`

### Cron job not running:
- Check cron logs: `grep CRON /var/log/syslog`
- Verify cron service: `sudo systemctl status cron`
- Check cron.log: `cat ~/omada-rotation/cron.log`
- Ensure script has shebang line and execute permissions

---

## Security Best Practices

1. **Secure the config file:**
   ```bash
   chmod 600 omada_config.conf
   chown pi:pi omada_config.conf
   ```

2. **Consider dedicated Omada user:**
   - Create a separate Omada admin account
   - Use it only for this script
   - Easier to audit and revoke if needed

3. **Rotate admin credentials periodically:**
   - Update PASSWORD in config file when you change admin password

4. **Monitor the logs:**
   ```bash
   # Set up log rotation
   sudo nano /etc/logrotate.d/omada-rotation
   ```
   
   Add:
   ```
   /home/pi/omada-rotation/omada_rotation.log {
       weekly
       rotate 4
       compress
       missingok
       notifempty
   }
   ```

5. **Backup configuration:**
   ```bash
   # Backup config (keep secure!)
   cp omada_config.conf omada_config.conf.backup
   ```

---

## Advanced: Monitoring and Alerting

### Set up monitoring for failures:

Create a monitoring script (`monitor.sh`):
```bash
#!/bin/bash
LAST_SUCCESS=$(grep "completed successfully" /home/pi/omada-rotation/omada_rotation.log | tail -1)
LAST_DATE=$(echo "$LAST_SUCCESS" | grep -oP '\[\K[^]]+')

if [[ -z "$LAST_DATE" ]]; then
    echo "WARNING: No successful rotations found!" | mail -s "Omada Rotation Alert" your@email.com
else
    LAST_EPOCH=$(date -d "$LAST_DATE" +%s)
    NOW_EPOCH=$(date +%s)
    DIFF=$((NOW_EPOCH - LAST_EPOCH))
    
    # Alert if no success in 48 hours
    if [[ $DIFF -gt 172800 ]]; then
        echo "WARNING: No successful password rotation in 48 hours!" | mail -s "Omada Rotation Alert" your@email.com
    fi
fi
```

Add to cron to run daily at noon:
```bash
0 12 * * * /home/pi/omada-rotation/monitor.sh
```

---

## Customization Options

### Change password length:
Edit `PASSWORD_LENGTH` in config file (minimum 8, recommended 16+)

### Change rotation time:
Modify the cron schedule (currently `0 6 * * *` for 6 AM)

### Custom password format:
Edit the `generate_password()` function in the script for different character sets

### Multiple SSIDs:
Duplicate the script and config for each SSID you want to rotate

---

## Maintenance

### Monthly tasks:
- Review logs for any errors
- Verify email notifications are arriving
- Check disk space: `df -h`

### Quarterly tasks:
- Update system packages
- Review and rotate admin credentials
- Test manual script execution

### Annual tasks:
- Review and update security practices
- Consider password policy changes
- Backup configuration files

---

## Support & Additional Resources

- **Omada API Documentation**: Check TP-Link forums for unofficial API docs
- **Log Location**: `~/omada-rotation/omada_rotation.log`
- **Original Blog Post**: https://0xjams.com/blog/rotating-guest-password-omada-controller/

---

## Quick Reference Commands

```bash
# Manual run
cd ~/omada-rotation && ./rotate_password.sh

# View logs
tail -f ~/omada-rotation/omada_rotation.log

# Check last rotation
grep "completed successfully" ~/omada-rotation/omada_rotation.log | tail -1

# Test email
echo "test" | mail -s "Test" your@email.com

# View cron jobs
crontab -l

# Check cron logs
grep CRON /var/log/syslog | tail -20
```