# 1-lite baseline (stateless, no persistent DB): set each company's fiscal country
# so account.tax.country_id (NOT NULL, defaults from company) resolves without
# loading a full chart of accounts. Run via: odoo-bin shell -d <db> < setup_company.py
import os

# Store NEW attachments in the database, not the on-disk filestore, so DBs cloned with
# `createdb -T` (the warm-base clones used by validate-* and serve.sh) carry their binaries.
# This runs between `-i base` and `-i <modules>`, so module/demo images installed afterwards
# land in the DB and therefore render in a served clone instead of 404ing on a filestore the
# clone never copied. (Assets from `-i base` stay in the filestore but are regenerable.)
env["ir.config_parameter"].sudo().set_param("ir_attachment.location", "db")

code = os.environ.get("COMPANY_COUNTRY", "base.kr")
country = env.ref(code)
companies = env["res.company"].search([])
for c in companies:
    vals = {"country_id": country.id}
    if "account_fiscal_country_id" in c._fields:
        vals["account_fiscal_country_id"] = country.id
    c.write(vals)
env.cr.commit()
print("COMPANY_COUNTRY_SET", country.code, "companies=%d" % len(companies))
