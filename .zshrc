export DOTNET_CLI_TELEMETRY_OPTOUT=1
export AZURE_DEV_COLLECT_TELEMETRY=no

alias brewup="brew update && brew upgrade --yes"

# Point the awards Postgres roaming firewall rule at my current public IP.
# (create acts as an upsert, so re-running just repoints the same rule.)
awardsfw() {
  local ip
  ip=$(curl -fsS https://api.ipify.org) || { echo "awardsfw: couldn't get public IP" >&2; return 1; }
  az postgres flexible-server firewall-rule create \
    --resource-group Awards-Db \
    --server-name corsair-awards-db \
    --name daniel-roaming \
    --start-ip-address "$ip" --end-ip-address "$ip" \
    && echo "awardsfw: allowed $ip"
}

# Source local machine-specific config (loaded last so local overrides win)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
