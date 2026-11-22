# Boat Electrical Splunk app

This folder is the importable Splunk app for the Tessa Jane electrical demo:

- `otel_demo_studio_viz` custom visualization (KPI tiles)
- **Tessa Jane Electrical Glass Table** (`boat_electrical_glass`)
- **Boat Electrical Data** (`boat_electrical`)
- Glass-table background image and Observability click-through

The XML views under `otel_demo_studio_viz/default/data/ui/views/` are what Splunk loads. Editable Dashboard Studio JSON (for regenerating those XML files) is in `studio_source/`.

## Manual import (existing Splunk)

```bash
sudo cp -a splunk_apps/otel_demo_studio_viz /opt/splunk/etc/apps/
sudo chown -R splunk:splunk /opt/splunk/etc/apps/otel_demo_studio_viz
sudo /opt/splunk/bin/splunk add index sim_metrics -datatype metric -auth admin:<password>
sudo systemctl restart Splunkd
```

Then open:

`https://<fqdn>:8000/en-US/app/otel_demo_studio_viz/boat_electrical_glass`

## SIM inputs

Dashboards read `index=sim_metrics`. The SignalFlow programs live in `config_files/splunk_ta_sim_tessa_jane_inputs.conf`. Terraform substitutes `__SIM_ORG_ID__` from `splunk_sim_org_id` and creates the Infrastructure Monitoring add-on account from `realm` and `access_token`.
