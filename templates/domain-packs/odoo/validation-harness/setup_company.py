# 1-lite baseline (stateless, no persistent DB): set each company's fiscal country
# so account.tax.country_id (NOT NULL, defaults from company) resolves without
# loading a full chart of accounts. Run via: odoo-bin shell -d <db> < setup_company.py
import os
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
