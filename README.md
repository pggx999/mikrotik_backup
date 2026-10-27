# mikrotik_backup
Mikrotik to Git backup


Mikrotik - Backup Script (To Git)
Problem: I have a handful of Mikrotik RouterOS based devices, and I would like a source-controlled versioning solution.

Solution: A simple bash script, with a cron job.

This post, provides a script, which allows automated backups of mikrotik configuration over ssh, from a linux host.

Schedule in Cron
To run the script automatically, I am using cron. The script below will schedule it to run at 2am everyday.


# Daily at 2:00 AM
(crontab -l 2>/dev/null; echo "0 2 * * * /path/to/backup.sh >> /var/log/mikrotik-backup.log 2>&1") | crontab -
Mikrotik Script - Create Backup User
Here is a simple mikrotik script to create the backup user.


# Create backup group with minimal read permissions
/user group add name=backup-group policy=read,ssh,api,test

# Create backup user
/user add name=mikrotik-backup-user group=backup-group disabled=no

# Add SSH public key directly (replace the key below with yours)

/user ssh-keys add key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDASM22nSot5CdMtn0Nmcu2ZhmC44U8hPUlW7j8NfFGSV6bkmHMC/emXDGFSWESlhjYmS054J75rheiFMLgp5MSbPC8Kbh9+pRzNae7/+HtMcwDds4x0iYD0uiyJSPWeVnHIxPZ8P8n6vHMxbIXmKcr5wd372oLLXWx31ErqqOlXr6aIRNfXM6ghz3fLffVhOHOIMYm6R24CSIhgdr1jTP0P7jjWXaFAp4aYHqBopqEnZ2MGU7eVo0yebACN63mZzYoc77kVW/bXZz9wXOid853OxuKOtGjKVmmhHUc/uvKz8rQygzM1Te2H1Un3LL89UpgrWgepdS6r8n7X0raWB8R5UZBHI7b0KIYb9234ioclQx3MEH8muh2pabU7YzwmM1vaK+uq8aYAO/RwriqAE89vnRZEvjlO3AKxJLyX6q6wYeBXBuN+s04+Xtck5MZKt/R5bliQbtO1VQlepYCGO5hfoMYPcXl+62+PRiH2XTQ/3lxEJCfZT4cf3Qo4IKgjw0= your-key-name" user=backup


# Verify the setup
/user print where name=backup
/user ssh-keys print where user=backup
Info

For those concerned about the above key being sensitive information, Its a randomly generated key. As well, its the public key, which is not sensitive.

The End Result? Backups.
This script has went through a few versions before I finally published this post.

I originally wrote this post in April, but, just now pushed it to here mid-way through October.

I only wanted a commit performed, when there were changes. I did not want my git repo spammed with empty commits. And- the script is able to deliver.

Image showing the occasional commit to my git repo

As, an example, a few days ago my ISP called, and let me know I needed to update my PPPoe credentials. The script was able to automatically capture the commit.

Imagine showing a commit in my git repo, regarding PPPOe configurations

Overall, its a simple, stupid solution, which is fit for use, and fit for purpose. And… its been working well for half of the year so far.
